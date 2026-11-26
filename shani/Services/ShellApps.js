.pragma library
// The shell's own apps, by the title their window carries (Common/AppWindow):
// name -> desktop entry id. Every Quickshell window reaches niri with the app
// id "org.quickshell"; Services/Niri uses this to give each its own id, so the
// dock, the switcher and the bar find the app's entry, icon and name.
// The same names and ids as bin/shani's APPS (tests/test_apps.py keeps them equal).
var ids = {
    "Dictionary": "dev.shani.Dictionary",
    "Podcasts": "dev.shani.Podcasts",
    "Teleprompter": "dev.shani.Teleprompter",
    "Network Tools": "dev.shani.NetTools",
    "Database browser": "dev.shani.DatabaseBrowser",
    "Paste history": "dev.shani.PasteHistory",
    "Services": "dev.shani.Services",
    "Background": "dev.shani.Background",
    "Calls": "dev.shani.Calls",
    "Devices": "dev.shani.Devices",
    "Messages": "dev.shani.Messages",
    "Text Editor": "dev.shani.TextEditor",
    "Files": "dev.shani.Files",
    "Image Viewer": "dev.shani.ImageViewer",
    "Document Viewer": "dev.shani.DocumentViewer",
    "Media Player": "dev.shani.MediaPlayer",
    "Clocks": "dev.shani.Clocks",
    "Archive Manager": "dev.shani.Archives",
    "Weather": "dev.shani.Weather",
    "Screenshot": "dev.shani.Screenshot",
    "Screen Recorder": "dev.shani.ScreenRecorder",
    "Color Picker": "dev.shani.ColorPicker",
    "Lens": "dev.shani.Lens",
    "Magnifier": "dev.shani.Magnifier",
    "Live Captions": "dev.shani.LiveCaptions",
    "Tour": "dev.shani.Tour",
    "Tasks": "dev.shani.Tasks",
    "Photos": "dev.shani.Photos",
    "Translate": "dev.shani.Translate",
    "Screen Ruler": "dev.shani.ScreenRuler",
    "Converter": "dev.shani.Converter",
    "Nearby Share": "dev.shani.Nearby",
    "Authenticator": "dev.shani.Authenticator",
    "Passwords and Keys": "dev.shani.Passwords",
    "Software": "dev.shani.Software",
    "Containers": "dev.shani.Containers",
    "Calculator": "dev.shani.Calculator",
    "Calendar": "dev.shani.Calendar",
    "Notes": "dev.shani.Notes",
    "Camera": "dev.shani.Camera",
    "Voice Recorder": "dev.shani.VoiceRecorder",
    "Characters": "dev.shani.Characters",
    "Fonts": "dev.shani.Fonts",
    "Maps": "dev.shani.Maps",
    "Disk Usage": "dev.shani.DiskUsage",
    "Document Scanner": "dev.shani.Scanner",
    "System Monitor": "dev.shani.SystemMonitor",
    "Logs": "dev.shani.Logs",
    "PDF Signer": "dev.shani.SignPdf",
    "Video Trimmer": "dev.shani.VideoTrimmer",
    "Kundali": "dev.shani.Kundali",
    "Settings": "dev.shani.Settings",
    "Contacts": "dev.shani.Contacts",
    "Health": "dev.shani.Health",
    "Models": "dev.shani.Models",
    "Studio": "dev.shani.Studio",
    "Disks": "dev.shani.Disks",
    "Remote Hosts": "dev.shani.TerminalApp",
    "Shani Backup": "dev.shani.Backup",
    "Feeds": "dev.shani.Feeds",
    "Mail": "dev.shani.Mail",
    "IRC": "dev.shani.Irc",
    "Cloud sync": "dev.shani.CloudSync"
};

// "notes.txt — Text Editor" and "Text Editor" are both the Text Editor
function idFor(title) {
    var t = String(title || "");
    if (ids[t])
        return ids[t];
    var at = t.lastIndexOf(" \u2014 ");
    return at >= 0 ? (ids[t.substring(at + 3)] || "") : "";
}
