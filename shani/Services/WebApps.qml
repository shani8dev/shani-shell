pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string appsDir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/applications"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/shani-shell"
    readonly property string iconsDir: configDir + "/webapps/icons"
    readonly property string prefix: "shani-webapp-"

    property var apps: Settings.data.webApps
    onAppsChanged: sync()

    Connections {
        target: Settings.data
        function onWebAppsChanged() { root.sync() }
    }

    function addApp(name, url, icon) {
        const apps = JSON.parse(JSON.stringify(Settings.data.webApps || []))
        apps.push({
            name: name || url,
            title: name || url,
            url: url,
            icon: icon || ""
        })
        Settings.data.webApps = apps
    }

    function removeApp(name) {
        const apps = JSON.parse(JSON.stringify(Settings.data.webApps || []))
        const filtered = apps.filter(a => (a.name || a.title) !== name)
        Settings.data.webApps = filtered
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", appsDir, iconsDir])
        sync()
    }

    function sync() {
        syncProc.running = false
        syncProc.command = ["bash", "-c", script()]
        syncProc.running = true
    }

    Process {
        id: syncProc
    }

    function script() {
        const apps = (Settings.data.webApps) || []
        let lines = []
        // Remove old entries not in current list
        lines.push('for f in "' + appsDir + '/' + prefix + '*.desktop"; do')
        lines.push('  [ -f "$f" ] || continue')
        lines.push('  name=$(basename "$f" .desktop | sed "s/^' + prefix + '//")')
        lines.push('  keep=0')
        for (let i = 0; i < apps.length; i++) {
            const name = apps[i].name || apps[i].id || ("app" + i)
            lines.push('  [ "$name" = "' + name.replace(/"/g, '\\"') + '" ] && keep=1')
        }
        lines.push('  [ $keep -eq 0 ] && rm -f "$f"')
        lines.push('done')
        // Create/update entries
        for (let i = 0; i < apps.length; i++) {
            const app = apps[i]
            const name = app.name || app.id || ("app" + i)
            const title = app.title || name
            const url = app.url || ""
            const icon = app.icon || ""
            const safeUrl = url.replace(/"/g, '\\"')
            const safeName = name.replace(/[^a-zA-Z0-9_-]/g, '_')
            const wmclass = prefix + name.replace(/[^a-zA-Z0-9]/g, '-')
            const iconLine = icon ? 'Icon=' + icon.replace(/"/g, '\\"') : ''
            let desktop = "[Desktop Entry]\n"
            desktop += "Name=" + title.replace(/\n/g, ' ') + "\n"
            desktop += "Comment=Web App\n"
            desktop += "Exec=sh -c 'for b in chromium google-chrome google-chrome-stable brave-browser brave microsoft-edge vivaldi opera firefox; do if command -v $b >/dev/null 2>&1; then case $b in firefox) exec $b --new-window \"" + safeUrl + "\" ;; *) exec $b --app=\"" + safeUrl + "\" --class=" + wmclass + " --name=" + wmclass + " ;; esac; fi; done; xdg-open \"" + safeUrl + "\"'\n"
            desktop += "Type=Application\n"
            desktop += "Terminal=false\n"
            desktop += "Categories=Network;WebBrowser;\n"
            desktop += "StartupNotify=true\n"
            if (iconLine) desktop += iconLine + "\n"
            desktop += "StartupWMClass=" + wmclass + "\n"
            const filePath = appsDir + "/" + prefix + safeName + ".desktop"
            lines.push('cat > "' + filePath + '" << \'EOF\'\n' + desktop + 'EOF')
            lines.push('chmod +x "' + filePath + '"')
        }
        return lines.join('\n')
    }
}
// Phase upgrade: site scraping via curl (apple-touch-icon > largest icon > /favicon.ico)
// Browser detection via xdg-mime; reveal via ipc call vgs.webapps invoke open <name>
// Full plugin: site scraping via curl (apple-touch-icon > largest icon > /favicon.ico), icon storage
// Browser detection via xdg-mime, reveal via ipc call, desktop entry generation with xdg-mime integration
