// The nine shell "tools" apps, declared once. LauncherActions is the reference;
// WindowMenu, Dock, SidebarTiles, SettingsIndex and QuickPanel must read this so
// label, icon, order and the flag they open cannot drift apart.
// An entry with `settings` is a Settings page, not a window of its own (the
// Startup manager and Scheduled tasks windows were merged into Settings).
// Frozen array literal (QSML JS cannot build objects from calls at load time).
var list = [
    { label: "Dictionary", icon: "accessories-dictionary", flag: "dictionary", op: "dictionaryOpen", words: "tool dictionary thesaurus define word office utility lookup" },
    { label: "Podcasts", icon: "audio-headphones", flag: "podcasts", op: "podcastsOpen", words: "tool podcasts podcast audio video audiobook subscribe audiovideo" },
    { label: "Teleprompter", icon: "view-list-text", flag: "teleprompter", op: "teleprompterOpen", words: "tool teleprompter script prompt office presentation scroll" },
    { label: "Network Tools", icon: "network-workgroup", flag: "netTools", op: "netToolsOpen", words: "tool network tools ping dns whois scan system" },
    { label: "Database browser", icon: "database", flag: "databaseBrowser", op: "databaseBrowserOpen", words: "tool database browser sqlite query office development" },
    { label: "Startup apps", icon: "system-run", flag: "startupManager", op: "startupManagerOpen", settings: "apps", words: "tool startup manager autostart login system utility" },
    { label: "Nearby Share", icon: "network-wireless", flag: "nearby", op: "nearbyOpen", words: "tool nearby share send peers qr handle address localsend gateway network utility" },
    { label: "Paste history", icon: "edit-paste", flag: "pasteHistory", op: "pasteHistoryOpen", words: "tool paste history clipboard slots favourite utility" },
    { label: "Automations", icon: "x-office-calendar", flag: "scheduled", op: "scheduledOpen", settings: "automations", words: "tool scheduled tasks schedule automation cron timer utility" }
];
