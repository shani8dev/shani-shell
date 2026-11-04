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
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data

    property string zone: ""
    property bool ntp: false
    property bool canNtp: false
    property var zones: []
    property string zoneError: ""
    property var locales: []
    property string lang: ""              // LANG in locale.conf ("" = the system's)
    // the language this session started with: a different choice needs a new sign-in
    readonly property string langAtLogin: Quickshell.env("LANG") || ""
    property string formats: ""           // LC_TIME and the other formats; "" = as the language
    property string preview: ""
    readonly property string localeConf: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/locale.conf"

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

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Date & time") }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Set the time automatically")
        hint: page.canNtp ? "from the network (systemd-timesyncd)" : "no network time service on this system"
        checked: page.ntp
        enabled: page.canNtp
        onToggled: on => page.timedatectl(["set-ntp", String(on)])
    }
    // automatic time off: set it here (timedated; the polkit agent asks)
    ColumnLayout {
        visible: !page.ntp
        Layout.fillWidth: true
        spacing: 12
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
        text: "Time zone: " + (page.zone || "unknown")
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
        font.pixelSize: 11 * Theme.fontScale
    }

    // ---- world clocks: more cities on the control centre's calendar ---------
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
        }
        onLoadFailed: { page.lang = ""; page.formats = ""; }
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
    // how dates and numbers look in the chosen formats
    Process {
        id: sample
        running: page.active
        command: ["sh", "-c", 'export LC_ALL="$1"; date "+%A, %x  %X"; printf "%\'.2f\\n" 1234567.89', "sh", page.formats || page.lang || "C.UTF-8"]
        stdout: StdioCollector { onStreamFinished: page.preview = text.trim().split("\n").join("   ·   ") }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Language & region") }
    Text {
        Layout.fillWidth: true
        text: "Language: " + page.niceLocale(page.lang) + "\nFormats: " + (page.formats ? page.niceLocale(page.formats) : "as the language") + "\n" + page.preview
        color: Theme.text
        wrapMode: Text.Wrap
        lineHeight: 1.2
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    property string choosing: ""            // "lang" | "formats" | ""
    RowLayout {
        spacing: 6
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
        model: page.choosing === "" ? [] : page.locales.filter(l => {
            const q = localeSearch.text.trim().toLowerCase();
            return q === "" || l.toLowerCase().indexOf(q) >= 0 || page.niceLocale(l).toLowerCase().indexOf(q) >= 0;
        }).slice(0, 10)
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
    Process {
        id: systemLocale
        stderr: StdioCollector { id: sysLocErr }
        onExited: code => page.systemLocaleNote = code === 0 ? "Set for the whole system." : (sysLocErr.text.trim().split("\n").pop() || "not changed")
    }
    Button {
        visible: page.lang !== ""
        text: Tr.t("Use for everyone and the login screen")
        onClicked: {
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
        color: page.systemLocaleNote.startsWith("Set") ? Theme.dim : Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("The shell changes at once; apps use the new language from your next sign-in. Every language is installed (glibc-locales), so any can be chosen.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }    Button {
        visible: page.lang !== "" && page.lang !== page.langAtLogin
        text: Tr.t("Log out now, to finish")
        onClicked: Power.logout()
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Calendar") }
    Text {
        text: Tr.t("The week starts on")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
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
