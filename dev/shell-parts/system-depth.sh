# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=system-depth)
# ---- Cassini depth gaps 3, 17-24, driven through the shell's own Settings pages.
#      Every read comes from a bridge and a harness stand-in; nothing here opens
#      a window on the person's display.
A11Y=${A11Y:-/testbed/lib/a11y_client.py}

# ---- Boot: secure-boot probe and the buttoned verify-existing read ----------
ipc settingsCategory boot; sleep 1.6
waitfor "d.get('bootSecure',{}).get('secure_boot') in ('on','off','setup','legacy','unknown')" 8 \
    && result boot-secureboot-state PASS || result boot-secureboot-state FAIL "$(q "['bootSecure']")"
waitfor "isinstance(d.get('bootSecure',{}).get('enrolled_keys'), int)" 8 \
    && result boot-enrolled-key-count PASS || result boot-enrolled-key-count FAIL "$(q "['bootSecure']")"
# ipc takes the same path as the button, without depending on AT-SPI timing
ipc bootVerify
waitfor "len(d.get('bootVerify',[])) >= 4" 12 \
    && result boot-verify-existing-rows PASS || result boot-verify-existing-rows FAIL "$(q "['bootVerify'], ['bootVerifyNote']")"
shot boot-depth 0.3

# ---- Disks: fi show / fi df / never-scrubbed and the smartd schedule --------
ipc settingsCategory disksfs; sleep 2.2
waitfor "d.get('systemState',{}).get('disksfs',{}).get('scrubState') in ('never','finished','running','unknown')" 10 \
    && result btrfs-scrub-state PASS || result btrfs-scrub-state FAIL "$(q "['systemState']")"
waitfor "len(d.get('systemState',{}).get('disksfs',{}).get('show',{})) >= 1" 10 \
    && result btrfs-fi-show PASS || result btrfs-fi-show FAIL "$(q "['systemState']")"
waitfor "len(d.get('systemState',{}).get('disksfs',{}).get('df',[])) >= 1" 10 \
    && result btrfs-fi-df PASS || result btrfs-fi-df FAIL "$(q "['systemState']")"
waitfor "len(d.get('systemState',{}).get('disksfs',{}).get('smartd',{})) >= 1" 10 \
    && result smartd-schedule-state PASS || result smartd-schedule-state FAIL "$(q "['systemState']")"
shot disksfs-depth 0.3

# ---- Storage: capacity and maintenance from the storage-info report --------
ipc settingsCategory storage; sleep 2.2
waitfor "d.get('systemState',{}).get('storageInfo',{}).get('have') is True" 12 \
    && result storage-info-read PASS || result storage-info-read FAIL "$(q "['systemState']")"
waitfor "len(d.get('systemState',{}).get('storageInfo',{}).get('summary',{})) >= 5" 12 \
    && result storage-info-capacity PASS || result storage-info-capacity FAIL "$(q "['systemState']")"
shot storage-depth 0.3

# ---- Firewall: jails and banned addresses, as a read ------------------------
ipc settingsCategory firewall; sleep 2
waitfor "d.get('systemState',{}).get('fail2ban',{}).get('available') is True" 10 \
    && result fail2ban-read PASS || result fail2ban-read FAIL "$(q "['systemState']")"
waitfor "len(d.get('systemState',{}).get('fail2ban',{}).get('jails',[])) >= 1" 10 \
    && result fail2ban-jails PASS || result fail2ban-jails FAIL "$(q "['systemState']")"
waitfor "any(len(j.get('banned',[])) >= 1 for j in d.get('systemState',{}).get('fail2ban',{}).get('per_jail',[]))" 10 \
    && result fail2ban-banned-addresses PASS || result fail2ban-banned-addresses FAIL "$(q "['systemState']")"
shot firewall-depth 0.3

# ---- UPS: the seven-key shutdown policy -------------------------------------
ipc settingsAt power ups; sleep 1.4
waitfor "d.get('upsPolicy',{}).get('present') is True" 10 \
    && result ups-policy-read PASS || result ups-policy-read FAIL "$(q "['upsPolicy']")"
waitfor "len(d.get('upsPolicy',{}).get('keys',{})) == 7" 10 \
    && result ups-policy-seven-keys PASS || result ups-policy-seven-keys FAIL "$(q "['upsPolicy']")"
shot ups-depth 0.3

# ---- Security: auditd state, never an empty "nothing to report" -------------
ipc settingsCategory security; sleep 2
waitfor "d.get('systemState',{}).get('securityAudit',{}).get('verdict') in ('genuine','not-running','no-log','empty-log','unresolved')" 12 \
    && result audit-state-read PASS || result audit-state-read FAIL "$(q "['systemState']")"
waitfor "d.get('systemState',{}).get('securityAudit',{}).get('active') != ''" 12 \
    && result auditd-state PASS || result auditd-state FAIL "$(q "['systemState']")"
shot security-depth 0.3

# ---- Updates: null is "the check did not finish", never "no update" ---------
cat > /usr/local/bin/shani-deploy <<'SH'
#!/bin/sh
printf '%s' '{"ok":true,"update_available":null,"current_slot":"green","version":"20261121","remote":{"stable":"20261121","latest":"20261122"}}'
SH
chmod +x /usr/local/bin/shani-deploy
ipc settingsCategory updates; sleep 1.8
waitfor "d.get('updatesAvailability') == 'unknown'" 10 \
    && result updates-null-not-no-update PASS || result updates-null-not-no-update FAIL "$(q "['updatesAvailability'], ['updatesSummary']")"
cat > /usr/local/bin/shani-deploy <<'SH'
#!/bin/sh
case "$*" in
    *--check*--json*) printf '%s' '{"ok":true,"update_available":true,"boot_markers":{"reboot_needed":false},"current_slot":"green","version":"20261121","remote":{"stable":"20261121","latest":"20261122"}}' ;;
    *) exit 2 ;;
esac
SH
chmod +x /usr/local/bin/shani-deploy
ipc closeAll
