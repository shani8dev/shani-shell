.pragma library
// What icon a file gets: its kind, not its name. Folders, pictures,
// documents, sound, video, archives - and a plain file for anything else.

const DOCS = [".txt", ".md", ".log", ".json", ".yaml", ".yml", ".toml", ".ini", ".csv", ".xml",
    ".html", ".css", ".js", ".ts", ".py", ".sh", ".c", ".h", ".cpp", ".rs", ".go"];
const SOUND = [".mp3", ".flac", ".ogg", ".opus", ".wav", ".m4a", ".aac"];
const VIDEO = [".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v"];
const ARCHIVE = [".zip", ".tar", ".gz", ".xz", ".zst", ".bz2", ".7z", ".rar"];

function iconFor(entry) {
    if (!entry)
        return "text-x-generic";
    if (entry.isDir)
        return "folder";
    const ext = String(entry.ext || "").toLowerCase();
    if (entry.image)
        return "image-x-generic";
    if (ext === ".pdf")
        return "x-office-document";
    if (SOUND.indexOf(ext) >= 0)
        return "audio-x-generic";
    if (VIDEO.indexOf(ext) >= 0)
        return "video-x-generic";
    if (ARCHIVE.indexOf(ext) >= 0)
        return "package-x-generic";
    if (ext === ".desktop")
        return "application-x-executable";
    if (DOCS.indexOf(ext) >= 0)
        return "text-x-generic";
    return "text-x-generic";
}
