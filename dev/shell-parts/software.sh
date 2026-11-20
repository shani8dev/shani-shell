# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=software)
# ---- Software (GNOME Software / Warehouse / Gear Lever parity) against a stand-in
#      flatpak and a two-app catalogue (tests/fixtures/appstream.xml): a category,
#      a search, an app's page, an install with progress, the installed list,
#      leftovers of a removed app ----
export SHANI_QS_CONFIG=/work/shani
A11Y=${A11Y:-/testbed/lib/a11y_client.py}
F=/tmp/fake-flatpak-store; rm -rf $F; mkdir -p $F; : > $F/installed
cat > /usr/local/bin/flatpak <<FP
#!/bin/sh
echo "\$*" >> $F/calls
case "\$1 \$2" in
"list --app") case "\$3" in --columns=application) cat $F/installed;; *) while read -r id; do [ -n "\$id" ] && printf '%s\tNotes\t1.2\tflathub\tsystem\t12.0 MB\n' "\$id"; done < $F/installed;; esac ;;
"remote-ls --updates") ;;
"install -y") for p in 10 40 80 100; do printf 'Installing org.example.Notes %s%%\n' \$p; sleep 0.3; done; echo org.example.Notes >> $F/installed ;;
esac
FP
chmod +x /usr/local/bin/flatpak
mkdir -p "$HOME/.var/app/org.gone.Old/config"; printf x > "$HOME/.var/app/org.gone.Old/config/x"
python3 /work/bin/shani app software >/dev/null 2>&1
waitfor "d['softwareShown'] and d['softwareResults'] == ['org.example.Notes']" 10 && result software-category PASS || result software-category FAIL "$(q "['softwareShown'], d['softwareResults']")"
shot app-software 0.3
if [ -f "$A11Y" ]; then
    timeout 20 python3 "$A11Y" press "radio button:^Games$" >/dev/null 2>&1
    waitfor "d['softwareResults'] == ['org.example.Game']" 6 && result software-games PASS || result software-games FAIL "$(q "['softwareResults']")"
    timeout 20 python3 "$A11Y" press "radio button:^Office$" >/dev/null 2>&1; sleep 0.8
    timeout 20 python3 "$A11Y" press "button:^Notes$" >/dev/null 2>&1
    waitfor "d['softwareApp'] == 'org.example.Notes'" 6 && result software-app-page PASS || result software-app-page FAIL "$(q "['softwareApp']")"
    shot app-software-page 0.3
    timeout 20 python3 "$A11Y" press "button:^Install$" >/dev/null 2>&1
    waitfor "d['softwareDone'] == 'org.example.Notes:ok' and d['softwareInstalled'] == ['org.example.Notes']" 15 \
        && grep -q 'install -y --noninteractive flathub org.example.Notes' $F/calls && result software-install PASS || result software-install FAIL "$(q "['softwareDone'], d['softwareInstalled']") $(tail -2 $F/calls | tr '\n' ';')"
    timeout 20 python3 "$A11Y" press "radio button:^Leftovers$" >/dev/null 2>&1
    waitfor "'org.gone.Old' in d['softwareLeftovers']" 6 && result software-leftovers PASS || result software-leftovers FAIL "$(q "['softwareLeftovers']")"
fi
rm -f /usr/local/bin/flatpak; rm -rf $F "$HOME/.var/app/org.gone.Old"; ipc closeAll
