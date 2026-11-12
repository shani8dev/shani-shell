.pragma library
// The shell's own apps, by the title their window carries (Common/AppWindow):
// name -> desktop entry id. Every Quickshell window reaches niri with the app
// id "org.quickshell"; Services/Niri uses this to give each its own id, so the
// dock, the switcher and the bar find the app's entry, icon and name.
// The same names and ids as bin/shani's APPS (tests/test_apps.py keeps them equal).
var ids = {
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
    "Password Generator": "dev.shani.Passwords",
    "PDF Signer": "dev.shani.SignPdf",
    "Video Trimmer": "dev.shani.VideoTrimmer",
    "Kundali": "dev.shani.Kundali",
    "Settings": "dev.shani.Settings"
};

// "notes.txt — Text Editor" and "Text Editor" are both the Text Editor
function idFor(title) {
    var t = String(title || "");
    if (ids[t])
        return ids[t];
    var at = t.lastIndexOf(" \u2014 ");
    return at >= 0 ? (ids[t.substring(at + 3)] || "") : "";
}
