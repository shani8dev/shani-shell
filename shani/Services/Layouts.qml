pragma Singleton

// The desktop layouts (Screen and layout): what each sets, which kind of screen
// each is made for or suits, and the settings a layout owns. One list for the
// switcher (Modules/LayoutSwitcher), the memory of the layout each situation
// had (Services/Docking) and the tests (tests/test_left_rail_fixes.py).
//
//   Layouts.presets          [{ id, made?, familiar?, suits, name, icon, desc, set }]
//   Layouts.keys             the settings a layout owns
//   Layouts.madeFor(kind)    the one made for that kind of screen (FormFactor.js PROFILES)
//   Layouts.snapshot() / put(set) / same(set, cur) / matching()
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    readonly property var corners: ["hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight"]
    function cornersAll(tl) { return { hotCornerTopLeft: tl, hotCornerTopRight: "none", hotCornerBottomLeft: "none", hotCornerBottomRight: "none" } }
    readonly property var presets: [
        // ---- one made for each kind of screen (FormFactor.js PROFILES) ----
        { id: "default", made: "computer", suits: ["computer", "laptop"], name: Tr.t("Shani"), icon: "start-here", desc: Tr.t("The bar along the top with the assistant in its middle, your workspaces down the left, and a dock that steps aside only when a window is moved over it. A clock on a clear desktop; windows open side by side."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "smart", barVisibility: "always", dockIconSize: 48, desktopWidgets: ["clock"], desktopIcons: false, deskStacks: false, winGaps: 12, winFocusRing: 2, winDefaultWidth: 0.5, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: true }, cornersAll("overview")) },
        { id: "laptop", made: "laptop", suits: ["laptop"], name: Tr.t("Laptop"), icon: "computer-laptop", desc: Tr.t("Made for a laptop's own screen: a slimmer dock that steps aside for windows, with your workspaces in it; the time and battery on a clear desktop; new windows two-thirds wide, so one fits with room beside it; tight gaps."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "smart", barVisibility: "always", dockIconSize: 44, desktopWidgets: ["clock", "battery"], desktopIcons: false, deskStacks: false, winGaps: 8, winFocusRing: 2, winDefaultWidth: 0.67, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("overview")) },
        { id: "tablet", made: "tablet", suits: ["tablet", "phone"], name: Tr.t("Touch"), icon: "input-tablet", desc: Tr.t("Made for a tablet, good on any touch screen: big dock icons and your workspaces down the left, under your thumbs; each app full screen; the time, weather and music on the desktop; Back and the keyboard in the dock, edge swipes for the rest."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 64, desktopWidgets: ["clock", "weather", "media"], desktopIcons: false, deskStacks: false, winGaps: 12, winFocusRing: 0, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: true }, cornersAll("none")) },
        { id: "phone", made: "phone", suits: ["phone"], name: Tr.t("Phone"), icon: "phone", desc: Tr.t("Made for a phone: every app full screen, edge to edge; a dock of favourites at the bottom; the time on the home screen; Quick Settings come down from the top."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 56, desktopWidgets: ["clock"], desktopIcons: false, deskStacks: false, winGaps: 0, winFocusRing: 0, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "handheld", made: "handheld", suits: ["handheld"], name: Tr.t("Handheld"), icon: "input-gaming", desc: Tr.t("Made for a handheld gaming PC's desktop: a big dock always there, each window full width, a strong focus ring to follow with the pad, the Smart Touch button for the touchscreen, nothing else on a small screen."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 56, desktopWidgets: [], desktopIcons: false, deskStacks: false, winGaps: 8, winFocusRing: 3, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: true, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "tv", made: "tv", suits: ["tv"], name: Tr.t("TV"), icon: "video-display", desc: Tr.t("Made for a TV's desktop, seen from the sofa: huge dock icons, a thick focus ring to follow with the remote, each app full screen inside a wide margin (a TV may cut its edges off), the time, the weather and what is playing."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 72, desktopWidgets: ["clock", "weather", "media"], desktopIcons: false, deskStacks: false, winGaps: 24, winFocusRing: 4, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "classroom", made: "board", suits: ["board"], name: Tr.t("Classroom"), icon: "x-office-presentation", desc: Tr.t("Made for a classroom board: the bar and a big dock within reach at the bottom, the tools coming in from whichever side you stand at, lesson files, the time and the day's agenda on the desktop, each window full width. Nothing up at the top, out of reach."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 64, desktopWidgets: ["clock", "agenda"], desktopIcons: true, deskStacks: false, winGaps: 12, winFocusRing: 2, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: true, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "focus", made: "projector", suits: ["projector", "laptop"], name: Tr.t("Focus"), icon: "view-fullscreen", desc: Tr.t("Made for a projector, and for clearing a laptop to work: what is on screen fills it, the dock and the bar out of sight until you reach for them, no focus ring to distract, an empty desktop."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "hide", barVisibility: "smart", dockIconSize: 56, desktopWidgets: [], desktopIcons: false, deskStacks: false, winGaps: 4, winFocusRing: 0, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("none")) },
        // ---- for any screen ----
        { id: "classic", suits: ["computer", "tv"], name: Tr.t("Classic"), icon: "user-desktop", desc: Tr.t("The bar along the top, a dock along the bottom that is always there, your files and drives on the desktop with the time, your agenda and the weather; each window full width."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 48, desktopWidgets: ["clock", "agenda", "weather"], desktopIcons: true, deskStacks: false, winGaps: 8, winFocusRing: 2, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "minimal", suits: ["computer", "laptop"], name: Tr.t("Minimal"), icon: "focus-windows", desc: Tr.t("Just the bar along the top, your workspaces in it, CPU and memory beside the clock; no dock - the top-left corner or Super opens the overview, where your apps are. A strong focus ring and tight gaps, for the keyboard."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: false, dockVisibility: "hide", barVisibility: "always", dockIconSize: 48, desktopWidgets: [], desktopIcons: false, deskStacks: false, winGaps: 6, winFocusRing: 3, winDefaultWidth: 0.5, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: true, leftRail: false }, cornersAll("overview")) },
        { id: "dashboard", suits: ["computer"], name: Tr.t("Dashboard"), icon: "view-list", desc: Tr.t("Everything at a glance: agenda, weather, music, a note and system use on the desktop, your files grouped into stacks, your workspaces down the left."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "workspaces", dock: true, dockVisibility: "always", barVisibility: "always", dockIconSize: 44, desktopWidgets: ["clock", "agenda", "weather", "media", "stats", "note"], desktopIcons: true, deskStacks: true, winGaps: 12, winFocusRing: 2, winDefaultWidth: 0.5, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: true, leftRail: true }, cornersAll("overview")) },
        // ---- familiar arrangements, for people used to another computer ----
        { id: "taskbar", familiar: true, suits: [], name: Tr.t("Taskbar"), icon: "user-desktop", desc: Tr.t("One bar along the bottom: the apps button at its left, a box to ask or search, then your apps; the tray and the clock at its right; files on the desktop; each window full width."),
          set: Object.assign({ barEdge: "bottom", barApps: "start", barSearch: true, railContent: "workspaces", dock: false, dockVisibility: "hide", barVisibility: "always", dockIconSize: 48, desktopWidgets: [], desktopIcons: true, deskStacks: false, winGaps: 4, winFocusRing: 1, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "centred", familiar: true, suits: [], name: Tr.t("Centred taskbar"), icon: "start-here", desc: Tr.t("One bar along the bottom with the apps button, a search box and your apps in its middle, the tray and the clock at its right; the weather and your files on the desktop; each window full width."),
          set: Object.assign({ barEdge: "bottom", barApps: "center", barSearch: true, railContent: "workspaces", dock: false, dockVisibility: "hide", barVisibility: "always", dockIconSize: 48, desktopWidgets: ["weather"], desktopIcons: true, deskStacks: false, winGaps: 8, winFocusRing: 2, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: false }, cornersAll("none")) },
        { id: "launcher", familiar: true, suits: [], name: Tr.t("Side launcher"), icon: "view-app-grid", desc: Tr.t("The bar along the top, and a launcher down the left: the apps button, then your apps, a mark beside the running ones; each window full width."),
          set: Object.assign({ barEdge: "auto", barApps: "off", barSearch: false, railContent: "apps", dock: false, dockVisibility: "hide", barVisibility: "always", dockIconSize: 48, desktopWidgets: [], desktopIcons: false, deskStacks: false, winGaps: 6, winFocusRing: 2, winDefaultWidth: 1.0, winFocusFollowsMouse: false, assistiveTouch: false, showSysStats: false, leftRail: true }, cornersAll("none")) }
    ]
    readonly property var keys: Object.keys(presets[0].set)

    function byId(id) { return presets.find(x => x.id === id) || null; }
    function madeFor(kind) { return presets.find(x => x.made === kind) || null; }
    function snapshot() {
        const o = {};
        for (const k of keys) {
            const v = Settings.data[k];
            o[k] = Array.isArray(v) || (v && typeof v === "object" && v.length !== undefined) ? Array.from(v) : v;
        }
        return o;
    }
    function put(set) { for (const k in set) Settings.data[k] = Array.isArray(set[k]) ? set[k].slice() : set[k]; }
    function same(set, cur) { for (const k in set) { if (JSON.stringify(set[k]) !== JSON.stringify(cur[k])) return false; } return true; }
    function matching() { const cur = snapshot(); return presets.findIndex(x => same(x.set, cur)); }
}
