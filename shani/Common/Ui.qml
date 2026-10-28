pragma Singleton
// Which shell surface is open, and on which screen. One overlay at a time:
// opening one closes the others, so Escape and click-outside have one meaning.
import Quickshell
import QtQuick

Singleton {
    id: root
    property bool launcher: false
    property string launcherQuery: ""
    property bool controlCenter: false
    property bool ring: false
    property int ringDepth: 0           // how many rings deep (for `state`)
    signal askRequested()               // the Island opens its question field
    property bool switcher: false
    property bool windowMenu: false
    property bool processes: false
    property bool magnifier: false
    property string settingsCat: ""
    property int faceRev: 0                        // bumped when ~/.face changes                // the settings category open, "" = the grid
    property int flashes: 0                        // flash alerts shown, for the tests
    property point ringAt: Qt.point(-1, -1)        // where the Ring opens; -1: at the pointer
    function openRingAt(x, y) {
        closeAll();
        ringAt = Qt.point(x, y);
        ring = true;
    }
    property real windowMenuX: 0
    signal windowMenuActionRequested(string id)
    signal switcherRequested(bool back) // Alt+Tab / Alt+Shift+Tab
    property string expanded: ""        // control-center section: wifi | bluetooth | audio | vpn | power
    property var screen: Quickshell.screens[0]
    property string topResult: ""
    // read-outs for `state` (tests and scripts)
    property string islandActivity: ""
    property var launcherSections: []
    property var tilesShown: []       // the launcher's first answer (shown in `state`)

    function closeAll() {
        launcher = false;
        ring = false;
        switcher = false;
        windowMenu = false;
        processes = false;
        magnifier = false;
        controlCenter = false;
        expanded = "";
    }
    function toggleLauncher(query) {
        const was = launcher;
        closeAll();
        // the query first: opening the launcher reads it at once, and set
        // after, every launch showed the previous query's answers
        launcherQuery = query || "";
        launcher = !was;
    }
    function askIsland() {
        closeAll();
        askRequested();
    }
    function toggleRing() {
        const was = ring;
        closeAll();
        ring = !was;
    }
    function toggleControlCenter(section) {
        const was = controlCenter && (section === undefined || expanded === section);
        closeAll();
        controlCenter = !was;
        if (controlCenter && section)
            expanded = section;
    }
}
