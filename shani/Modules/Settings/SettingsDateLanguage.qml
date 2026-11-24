// Settings > Date & language. The time zone and network time are systemd's
// (timedated, asked over timedatectl; changing them is an admin action, so the
// shell's polkit agent asks once). Language and formats are this person's:
// ~/.config/locale.conf, which the login shell reads (niri-session starts
// through it), so they apply from the next sign-in.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    readonly property var d: Settings.data

    property string zone: ""
    property bool ntp: false
    property bool canNtp: false
    property var zones: []
    property string zoneError: ""
    property var locales: []
    property string lang: ""              // LANG in locale.conf ("" = the system's)
    // the language this session started with: a different choice needs a new sign-in.
    // locale.conf may hold "en_IN.utf8" while LANG at login is "en_IN.UTF-8": compare
    // language/region only, so an encoding spelling alone is not a false log-out prompt
    readonly property string langAtLogin: (Quickshell.env("LANG") || "").replace(/\..*$/, "")
    property string formats: ""           // LC_TIME and the other formats; "" = as the language
    property string preview: ""
    readonly property string localeConf: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/locale.conf"
    readonly property var adminCmd: (Quickshell.env("SHANI_ADMIN_TOOL") || "pkexec /usr/lib/shani-shell/shani-admin.py").split(" ")
    property string ntpServers: ""
    property string ntpFallback: ""
    property string ntpNote: ""
    property bool ntpBusy: false

    function niceLocale(name) {
        if (!name)
            return "System default";
        const l = Qt.locale(name.replace(/\..*$/, ""));
        const lang = l.nativeLanguageName || name;
        return lang.charAt(0).toUpperCase() + lang.slice(1) + (l.nativeTerritoryName ? " · " + l.nativeTerritoryName : "") + "  (" + name + ")";
    }
    function refresh() {
        info.running = true;
        zoneList.running = true;
        localeList.running = true;
        conf.reload();
        refreshPreview();
        ntpGet.running = false; ntpGet.running = true;
    }
    onActiveChanged: if (active) refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) refresh()

    // ---- time --------------------------------------------------------------
    Process {
        id: info
        command: ["sh", "-c", 'timedatectl show -p Timezone -p NTP -p CanNTP 2>/dev/null || echo "Timezone=$(readlink /etc/localtime | sed "s,.*/zoneinfo/,,")"']
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                text.trim().split("\n").forEach(l => { const i = l.indexOf("="); if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1); });
                page.zone = kv.Timezone || "";
                page.ntp = kv.NTP === "yes";
                page.canNtp = kv.CanNTP === "yes";
            }
        }
    }
    Process {
        id: zoneList
        command: ["sh", "-c", 'timedatectl list-timezones 2>/dev/null || (cd /usr/share/zoneinfo && find . -type f | sed "s|^\\./||" | grep -E "^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/" | sort)']
        stdout: StdioCollector { onStreamFinished: page.zones = text.trim().split("\n").filter(x => x) }
    }
    Process {
        id: setTime
        stderr: StdioCollector { id: setErr }
        onExited: code => {
            page.zoneError = code === 0 ? "" : (setErr.text.trim().split("\n").pop() || "not changed");
            info.running = true;
        }
    }
    function timedatectl(args) {
        setTime.command = ["timedatectl"].concat(args);
        setTime.running = true;
    }
    Process { id: ntpGet; command: ["sh","-c","f=/etc/systemd/timesyncd.conf.d/50-shani-shell.conf; [ -r \"$f\" ] && grep -E '^(NTP|FallbackNTP)=' \"$f\" || true"]; stdout: StdioCollector { onStreamFinished: { let n="", fb=""; for (const l of text.split("\n")) { if (l.startsWith("NTP=")) n=l.slice(4).trim(); if (l.startsWith("FallbackNTP=")) fb=l.slice(12).trim(); } page.ntpServers=n; page.ntpFallback=fb; ntpServersField.text=n; ntpFallbackField.text=fb; } } }
    Process { id: ntpSet; stdinEnabled: true; property string payload: ""; stderr: StdioCollector { id: ntpErr } onStarted: { write(payload + "\n"); stdinEnabled = false; } onExited: code => { stdinEnabled = true; page.ntpBusy = false; page.ntpNote = code === 0 ? Tr.t("NTP servers saved") : (ntpErr.text.trim().split("\n").pop() || Tr.t("Could not save")); if (code === 0) { ntpGet.running = false; ntpGet.running = true; } } }
    function saveNtp() { page.ntpBusy = true; page.ntpNote = ""; ntpSet.payload = JSON.stringify({ settings: { NTP: ntpServersField.text.trim(), FallbackNTP: ntpFallbackField.text.trim() } }); ntpSet.command = page.adminCmd.concat(["timesyncd-set"]); ntpSet.running = true; }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Date & time") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Set the time automatically")
        hint: page.canNtp ? "from the network (systemd-timesyncd)" : "no network time service on this system"
        checked: page.ntp
        enabled: page.canNtp
        onToggled: on => page.timedatectl(["set-ntp", String(on)])
    }
    ColumnLayout {
        Layout.fillWidth: true; spacing: Theme.px(4)
        Text { text: Tr.t("NTP servers (space separated)"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: ntpServersField; Layout.fillWidth: true; placeholder: "time.cloudflare.com 0.pool.ntp.org" }
        Text { text: Tr.t("Fallback NTP servers"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
        TextField { id: ntpFallbackField; Layout.fillWidth: true; placeholder: "1.pool.ntp.org" }
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: page.ntpNote; color: page.ntpNote.indexOf("saved") >= 0 ? Theme.accent : Theme.danger; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; visible: page.ntpNote !== "" }
            Item { Layout.fillWidth: true; visible: page.ntpNote === "" }
            Button { text: Tr.t("Save NTP servers"); enabled: !page.ntpBusy; onClicked: page.saveNtp() }
        }
    }
    // automatic time off: set it here (timedated; the polkit agent asks)
    ColumnLayout {
        visible: !page.ntp
        Layout.fillWidth: true
        spacing: Theme.px(12)
        DatePicker {
            id: setDate
            label: Tr.t("Date")
        }
        TimePicker {
            id: setClock
            label: Tr.t("Time")
            value: Qt.formatTime(new Date(), "HH:mm")
        }
        Button {
            text: Tr.t("Set the time")
            Layout.fillWidth: true
            onClicked: {
                page.timedatectl(["set-time", setDate.value + " " + setClock.value + ":00"]);
            }
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        visible: Tr.lang !== "en"
        text: Tr.t("Translate the rest with Chronoa")
        hint: Tr.t("Words the shell has no translation for are translated on this computer by Chronoa's model. Machine translations can be wrong.")
        checked: page.d.machineTranslate
        onToggled: on => page.d.machineTranslate = on
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("24-hour clock"); checked: page.d.use24h; onToggled: on => page.d.use24h = on }
    Text {
        text: Tr.t("Time zone: %1").arg(page.zone || Tr.t("unknown"))
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: Theme.fontBody * Theme.fontScale
    }
    // click where you are; the search below is for those who would rather type
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: width / 2
        WorldMap {
            anchors.fill: parent
            zone: page.zone
            onZonePicked: z => page.timedatectl(["set-timezone", z])
        }
    }
    TextField {
        id: zoneSearch
        Layout.fillWidth: true
        placeholder: Tr.t("Search a city or region — Kolkata, Berlin, New_York…")
    }
    Repeater {
        model: zoneSearch.text.trim().length < 2 ? [] : page.zones.filter(z => z.toLowerCase().indexOf(zoneSearch.text.trim().toLowerCase().replace(/ /g, "_")) >= 0).slice(0, 8)
        ListRow {
            required property string modelData
            Layout.fillWidth: true
            icon: "preferences-system-time"
            title: modelData.replace(/_/g, " ")
            selected: modelData === page.zone
            onClicked: {
                page.timedatectl(["set-timezone", modelData]);
                zoneSearch.text = "";
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.zoneError !== ""
        text: page.zoneError
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }

    // ---- world clocks: more cities on the control centre's calendar ---------
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("The first city's time in the bar")
        checked: page.d.barWorldClock
        defaultValue: false
        onToggled: on => { page.d.barWorldClock = on; Settings.touch("barWorldClock"); }
        onReset: page.d.barWorldClock = false
    }
    // picked zones, remove one at a time
    Repeater {
        model: Array.from(page.d.worldClocks || [])
        ListRow {
            required property string modelData
            required property int index
            Layout.fillWidth: true
            icon: "preferences-system-time"
            title: modelData.split("/").pop().replace(/_/g, " ")
            subtitle: (WorldClock.clocks.find(c => c.zone === modelData) || {}).time || ""
            onClicked: {
                const z = Array.from(page.d.worldClocks || []);
                z.splice(index, 1);
                page.d.worldClocks = z;
            }
        }
    }
    TextField {
        id: worldSearch
        Layout.fillWidth: true
        placeholder: Tr.t("Add a world clock — Tokyo, Berlin, New_York…")
    }
    Repeater {
        model: worldSearch.text.trim().length < 2 ? [] : page.zones.filter(z => z.toLowerCase().indexOf(worldSearch.text.trim().toLowerCase().replace(/ /g, "_")) >= 0).slice(0, 6)
        ListRow {
            required property string modelData
            Layout.fillWidth: true
            icon: "list-add"
            title: modelData.replace(/_/g, " ")
            selected: Array.from(page.d.worldClocks || []).indexOf(modelData) >= 0
            onClicked: {
                if (Array.from(page.d.worldClocks || []).indexOf(modelData) >= 0)
                    return;
                page.d.worldClocks = Array.from(page.d.worldClocks || []).concat([modelData]);
                worldSearch.text = "";
            }
        }
    }

    // ---- language and formats ----------------------------------------------
    Process {
        id: localeList
        command: ["sh", "-c", 'localectl list-locales 2>/dev/null || locale -a | grep -i utf']
        stdout: StdioCollector { onStreamFinished: page.locales = text.trim().split("\n").filter(x => x && !/^(C|POSIX)(\.|$)/i.test(x)) }
    }
    FileView {
        id: conf
        path: page.localeConf
        printErrors: false
        onLoaded: {
            const kv = {};
            text().split("\n").forEach(l => { const m = l.match(/^\s*([A-Z_]+)=["']?([^"']*)["']?\s*$/); if (m) kv[m[1]] = m[2]; });
            page.lang = kv.LANG || "";
            page.formats = kv.LC_TIME && kv.LC_TIME !== kv.LANG ? kv.LC_TIME : "";
            page.refreshPreview();
        }
        onLoadFailed: { page.lang = ""; page.formats = ""; page.refreshPreview(); }
    }
    function writeConf(lang, formats) {
        const lines = ["# written by shani-shell: Settings > Date & language; read at sign-in"];
        if (lang)
            lines.push("LANG=" + lang);
        if (formats)
            for (const k of ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER"])
                lines.push(k + "=" + formats);
        saveConf.command = ["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s\\n" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", page.localeConf, lines.join("\n")];
        saveConf.running = true;
    }
    Process { id: saveConf; onExited: conf.reload() }
    // how dates and numbers look in the chosen formats. Proc.run restarts on
    // every call, so the sample follows a new language/formats choice at once
    // (a Process whose command changes while running would stay on the old one)
    function refreshPreview() {
        if (!page.active)
            return;
        Proc.run("date-language-preview",
            ["sh", "-c", 'export LC_ALL="$1"; date "+%A, %x  %X"; printf "%\'.2f\\n" 1234567.89', "sh", page.formats || page.lang || "C.UTF-8"],
            out => { page.preview = out.trim().split("\n").join("   ·   "); }, 0);
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Language & region") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Language: %1\nFormats: %2\n%3").arg(page.niceLocale(page.lang)).arg(page.formats ? page.niceLocale(page.formats) : Tr.t("as the language")).arg(page.preview)
        color: Theme.text
        wrapMode: Text.Wrap
        lineHeight: 1.2
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    property string choosing: ""            // "lang" | "formats" | ""
    RowLayout {
        spacing: Theme.px(6)
        Choice { text: Tr.t("Change language"); selected: page.choosing === "lang"; onClicked: page.choosing = page.choosing === "lang" ? "" : "lang" }
        Choice { text: Tr.t("Change formats"); selected: page.choosing === "formats"; onClicked: page.choosing = page.choosing === "formats" ? "" : "formats" }
    }
    TextField {
        id: localeSearch
        Layout.fillWidth: true
        visible: page.choosing !== ""
        placeholder: Tr.t("Search — मराठी, Deutsch, en_IN…")
    }
    Repeater {
        // the empty entry lets someone undo a choice and go back to the system's
        // language (or formats), instead of being stuck with the last one picked
        model: page.choosing === "" ? [] : [""].concat(page.locales.filter(l => {
            const q = localeSearch.text.trim().toLowerCase();
            return q === "" || l.toLowerCase().indexOf(q) >= 0 || page.niceLocale(l).toLowerCase().indexOf(q) >= 0;
        }).slice(0, 10))
        ListRow {
            required property string modelData
            Layout.fillWidth: true
            icon: "preferences-desktop-locale"
            title: page.niceLocale(modelData)
            selected: modelData === (page.choosing === "lang" ? page.lang : page.formats)
            onClicked: {
                if (page.choosing === "lang")
                    page.writeConf(modelData, page.formats);
                else
                    page.writeConf(page.lang, modelData === page.lang ? "" : modelData);
                page.choosing = "";
                localeSearch.text = "";
            }
        }
    }
    // the system's own: the login screen, the console, and anyone without their own
    property string systemLocaleNote: ""
    property bool systemLocaleOk: false
    // affects every account and the login screen, not just this one
    property bool confirmingSystemLocale: false
    Timer { id: systemLocaleConfirmTimer; interval: 4000; onTriggered: page.confirmingSystemLocale = false }
    Process {
        id: systemLocale
        stderr: StdioCollector { id: sysLocErr }
        onExited: code => {
            page.systemLocaleNote = code === 0 ? "Set for the whole system." : (sysLocErr.text.trim().split("\n").pop() || "not changed")
            page.systemLocaleOk = code === 0;
        }
    }
    Button {
        visible: page.lang !== ""
        text: page.confirmingSystemLocale ? Tr.t("Tap again for everyone") : Tr.t("Use for everyone and the login screen")
        kind: page.confirmingSystemLocale ? "danger" : "plain"
        onClicked: {
            if (!page.confirmingSystemLocale) {
                page.confirmingSystemLocale = true;
                systemLocaleConfirmTimer.restart();
                return;
            }
            page.confirmingSystemLocale = false;
            const args = ["localectl", "set-locale", "LANG=" + page.lang];
            if (page.formats)
                for (const k of ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER"])
                    args.push(k + "=" + page.formats);
            systemLocale.command = args;
            systemLocale.running = true;
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.systemLocaleNote !== ""
        text: page.systemLocaleNote
        color: page.systemLocaleOk ? Theme.accent : Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("The shell changes at once; apps use the new language from your next sign-in. Every language is installed (glibc-locales), so any can be chosen.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }    Button {
        visible: page.lang !== "" && page.lang.replace(/\..*$/, "") !== page.langAtLogin
        text: Tr.t("Log out now, to finish")
        onClicked: Power.logout()
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Calendar") }
    Text {
        text: Tr.t("The week starts on")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(12) * Theme.fontScale
    }
    Flow {
        Layout.fillWidth: true
        spacing: Theme.px(6)
        Repeater {
            model: [{ id: "monday", label: Tr.t("Monday") }, { id: "sunday", label: Tr.t("Sunday") }]
            Choice {
                required property var modelData
                text: modelData.label
                selected: page.d.weekStartsOn === modelData.id
                onClicked: page.d.weekStartsOn = modelData.id
            }
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Week numbers")
        hint: Tr.t("down the side of the calendar (ISO weeks)")
        checked: page.d.weekNumbers
        onToggled: on => page.d.weekNumbers = on
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Show events in the sidebar calendar")
        hint: Tr.t("from the calendars Evolution Data Server knows about")
        checked: page.d.showCalendarEvents
        onToggled: on => page.d.showCalendarEvents = on
    }
}
