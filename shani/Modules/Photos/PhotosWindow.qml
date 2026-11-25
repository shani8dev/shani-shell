// Photos: every picture in Pictures (the camera's, the screenshots, the
// wallpapers…), newest first and by month - Photos, Gallery, Shotwell. A click
// opens it in the Image Viewer, with its folder around it. Small copies are
// what the grid draws (sourceSize), so a thousand photos stay light.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Photos"
    visible: Ui.photos
    onGone: Ui.photos = false
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(700)

    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
    property var photos: []           // [{ path, time (s), month "November 2026" }]
    property bool scanning: false
    // These three stay window-local on purpose: persisting them needs keys in
    // Common/Settings.qml's JsonAdapter (or slots in the Common Ui singleton), neither of
    // which this file owns. Assigning an undeclared Settings.data key throws at
    // runtime and can take the shell down, so they reset each time Photos opens.
    property string filter: "all"     // all | camera | screenshots
    property string groupBy: "month"  // day | month | year
    property string sortOrder: "newest"  // newest | oldest | name | size
    property string searchText: ""    // filename / path / tag substring
    property bool importBusy: false
    property string importNote: ""
    property var selected: []         // multi-select: batch trash / album add
    property string detailPath: ""    // the photo the details panel describes
    property bool detailsShown: false
    property var meta: ({})           // path -> { rating, tags, favorite }, kept in shani-photos/meta.json
    property string folderFilter: ""  // a folder (relative to Pictures) the view is scoped to
    property int minRating: 0         // 0 = any rating, else "this many stars and up"
    property var duplicatePaths: []   // extra copies of identical files; the first is kept
    property bool importDated: false  // import into YYYY/YYYY-MM subfolders
    property bool slidePaused: false
    property bool slideshow: false    // full-screen slideshow over `shown`, not just one folder
    property int slideIndex: -1
    readonly property real slideSeconds: 3.5
    property string scanError: ""
    property string focusPath: ""     // the tile the keyboard last reached
    property string focusAnchor: ""   // where a shift-click range starts

    // ---- Picasa-style additions -------------------------------------------------
    // Every new view is a filter over `shown`, so albums, ratings, search and
    // folder chips keep composing with it. New state is window-local except the
    // JSON files next to meta.json (prefs, smart albums) and meta.json itself.
    property string view: "photos"    // photos | people | places
    property string personFilter: ""  // a name tagged on photos
    property string placeFilter: ""   // a "lat, lon" key
    property string tagFilter: ""     // a keyword tag; "Family > Kids" is nested
    property string timelinePeriod: ""  // "YYYY-MM" the scrubber jumped to
    property int tileSize: 150        // thumbnail edge, persisted in prefs.json
    property bool filmstrip: false
    property string personName: ""
    property string tagName: ""
    property string renamePattern: ""
    property string smartName: ""
    property string activeSmart: ""
    property var smartAlbums: []      // saved search rules, in smart-albums.json
    property var placeData: ({})      // path -> [lat, lon]
    property var places: []           // [{ key, label, items }]
    property bool placesReady: false
    property bool placesTool: true    // false: neither exiv2 nor exiftool installed

    // The album controls call the local writer; QML ids cannot start uppercase.
    QtObject {
        id: photosApi
        function createAlbum(name, paths) { win.createAlbum(name, paths); }
    }

    readonly property var shown: photos.filter(p =>
        (filter === "all" || filter === "favorites" || filter === "duplicates" ||
         (filter === "camera" ? /\/Camera\/|\/DCIM\/|\/camera\//i.test(p.path) : /\/Screenshot/i.test(p.path))) &&
        (filter === "favorites" ? favoriteOf(p.path) : true) &&
        (filter === "duplicates" ? duplicatePaths.indexOf(p.path) >= 0 : true) &&
        (folderFilter === "" || folderOf(p.path) === folderFilter || folderOf(p.path).indexOf(folderFilter + "/") === 0) &&
        (minRating === 0 || ratingOf(p.path) >= minRating) &&
        (activeAlbum === "" || activeAlbum === "all" || albums.find(a => a.name === activeAlbum)?.members?.includes(p.path)) &&
        (searchText.trim() === "" || String(p.path).toLowerCase().indexOf(searchText.trim().toLowerCase()) >= 0 ||
         tagsOf(p.path).toLowerCase().indexOf(searchText.trim().toLowerCase()) >= 0) &&
        (view !== "people" || peopleOf(p.path).trim() !== "") &&
        (view !== "places" || !!placeData[p.path]) &&
        (personFilter === "" || splitTags(peopleOf(p.path)).indexOf(personFilter) >= 0) &&
        (tagFilter === "" || splitTags(tagsOf(p.path)).indexOf(tagFilter) >= 0) &&
        (timelinePeriod === "" || monthKey(p.time) === timelinePeriod) &&
        (placeFilter === "" || (placeData[p.path] && placeLabel(placeData[p.path]) === placeFilter)) &&
        (activeSmart === "" || smartMatches(p, activeSmart)))
    function comparePhotos(a, b) {
        if (win.sortOrder === "oldest") return a.time - b.time;
        if (win.sortOrder === "name") return a.path.split("/").pop().localeCompare(b.path.split("/").pop());
        // size comes from the same find line as time; missing size sorts last
        if (win.sortOrder === "size") return (b.size || 0) - (a.size || 0);
        return b.time - a.time;   // newest, the scan order
    }
    // [{ key, items: [...] }] — the key is a day, a month or a year. The sort
    // order is applied here (not in scan's `sort -rn`) so it works for every
    // grouping; same-key groups are merged so a name sort cannot split a month.
    readonly property var groups: {
        const fmt = win.groupBy === "day" ? "d MMM yyyy" : win.groupBy === "year" ? "yyyy" : "MMMM yyyy";
        let list = win.sortOrder === "newest" ? shown : shown.slice().sort((a, b) => win.comparePhotos(a, b));
        const out = [];
        for (const p of list) {
            // Places overrides the grouping so the grid reads as a map album;
            // the normal day/month/year/folder keys are otherwise untouched.
            const key = win.view === "places"
                ? (win.placeData[p.path] ? win.placeLabel(win.placeData[p.path]) : Tr.t("No location"))
                : (win.groupBy === "folder" ? (folderOf(p.path) || Tr.t("Pictures")) : Qt.formatDate(new Date(p.time * 1000), fmt));
            let group = out.find(g => g.key === key);
            if (!group) { group = { key: key, items: [] }; out.push(group); }
            group.items.push(p);
        }
        return out;
    }
    // folder chips: the directories under Pictures that hold photos, sorted so a
    // shallow folder like Camera comes before Camera/2026.
    readonly property var folders: {
        const out = [];
        for (const p of photos) {
            const f = folderOf(p.path);
            if (f && out.indexOf(f) < 0) out.push(f);
        }
        return out.sort((a, b) => a.localeCompare(b));
    }
    function folderOf(path) {
        const s = String(path || "");
        const dir = s.substring(0, s.lastIndexOf("/"));
        const root = win.pictures.replace(/\/$/, "");
        return dir === root ? "" : (dir.indexOf(root + "/") === 0 ? dir.substring(root.length + 1) : dir);
    }

    function monthKey(time) {
        const d = new Date(time * 1000);
        return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2);
    }
    // one chip per month present in the library, newest first — the strip is a
    // jump control; the month grouping below stays the detailed view.
    readonly property var timelinePeriods: {
        const out = [];
        for (const p of win.photos) {
            const k = win.monthKey(p.time);
            if (out.indexOf(k) < 0) out.push(k);
        }
        return out.sort().reverse();
    }
    function stepTimeline(dir) {
        const list = win.timelinePeriods;
        if (!list.length) return;
        const at = list.indexOf(win.timelinePeriod);
        const next = at < 0 ? (dir > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, at + dir));
        win.timelinePeriod = list[next];
    }
    function splitTags(str) { return String(str || "").split(",").map(s => s.trim()).filter(Boolean); }
    // People and keyword tags are derived from meta.json on every change: no
    // second store to keep in sync. A nested tag is just "Family > Kids".
    function peopleOf(path) { return (win.meta[path] && win.meta[path].people) || ""; }
    readonly property var people: {
        const out = {};
        for (const p of win.photos)
            for (const n of win.splitTags(win.peopleOf(p.path)))
                (out[n] = out[n] || []).push(p.path);
        return Object.keys(out).sort().map(n => ({ name: n, paths: out[n] }));
    }
    readonly property var allTags: {
        const out = {};
        for (const p of win.photos)
            for (const t of win.splitTags(win.tagsOf(p.path))) out[t] = true;
        return Object.keys(out).sort();
    }
    function placeLabel(c) { return Number(c[0]).toFixed(2) + ", " + Number(c[1]).toFixed(2); }
    function smartMatches(p, name) {
        const r = win.smartAlbums.find(a => a.name === name);
        if (!r) return true;
        if (r.minRating && win.ratingOf(p.path) < r.minRating) return false;
        if (r.favoriteOnly && !win.favoriteOf(p.path)) return false;
        if (r.fromYear && win.monthKey(p.time).substring(0, 4) !== String(r.fromYear)) return false;
        if (r.tag && win.splitTags(win.tagsOf(p.path)).indexOf(r.tag) < 0) return false;
        return true;
    }

    // ---- per-photo ratings and tags (path-keyed, beside the albums) --------------
    readonly property string metaFile: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/shani-photos/meta.json"
    readonly property string metaWriteCode: 'import json,sys,os\np=sys.argv[1]\nos.makedirs(os.path.dirname(p),exist_ok=True)\nopen(p,"w").write(json.dumps(json.loads(sys.argv[2])))'
    function loadMeta() { metaLister.running = true; }
    function saveMeta() {
        metaWrite.command = ["python3", "-c", win.metaWriteCode, win.metaFile, JSON.stringify(win.meta)];
        metaWrite.running = true;
    }
    function ratingOf(path) { return (win.meta[path] && win.meta[path].rating) || 0; }
    function tagsOf(path) { return (win.meta[path] && win.meta[path].tags) || ""; }
    function setRating(path, stars) {
        if (!path) return;
        const m = Object.assign({}, win.meta);
        m[path] = Object.assign({ tags: "" }, m[path], { rating: stars });
        win.meta = m;
        saveMeta();
    }
    function setTags(path, tags) {
        if (!path) return;
        const m = Object.assign({}, win.meta);
        m[path] = Object.assign({ rating: 0 }, m[path], { tags: tags });
        win.meta = m;
        saveMeta();
    }
    // favourites live in the same per-photo file as ratings and tags, so a
    // Favorites filter costs no extra persistence and survives a rescan.
    function favoriteOf(path) { return !!(win.meta[path] && win.meta[path].favorite); }
    function setFavorite(path, fav) {
        if (!path) return;
        const m = Object.assign({}, win.meta);
        m[path] = Object.assign({ rating: 0, tags: "" }, m[path], { favorite: !!fav });
        win.meta = m;
        saveMeta();
    }
    function toggleFavorite(path) { setFavorite(path, !favoriteOf(path)); }
    function favoriteSelected() {
        const paths = win.selected.length ? win.selected.slice() : (win.detailPath ? [win.detailPath] : []);
        if (!paths.length) return;
        const m = Object.assign({}, win.meta);
        for (const p of paths) m[p] = Object.assign({ rating: 0, tags: "" }, m[p], { favorite: true });
        win.meta = m;
        saveMeta();
        win.clearSelect();
    }
    function rateSelected(stars) {
        const paths = win.selected.length ? win.selected.slice() : (win.detailPath ? [win.detailPath] : []);
        if (!paths.length) return;
        const m = Object.assign({}, win.meta);
        for (const p of paths) m[p] = Object.assign({ tags: "", favorite: false }, m[p], { rating: stars });
        win.meta = m;
        saveMeta();
        win.clearSelect();
    }
    Process {
        id: metaLister
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || echo "{}"', "sh", win.metaFile]
        stdout: StdioCollector {
            onStreamFinished: { try { win.meta = JSON.parse(text) || {}; } catch (e) { win.meta = {}; } }
        }
    }
    Process { id: metaWrite }

    // ---- Picasa-style persistence: same shani-photos dir, values via argv --------
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/shani-photos"
    readonly property string prefsFile: win.dataDir + "/prefs.json"
    readonly property string smartFile: win.dataDir + "/smart-albums.json"
    function writeJson(file, obj) {
        jsonWrite.command = ["python3", "-c", win.metaWriteCode, file, JSON.stringify(obj)];
        jsonWrite.running = true;
    }
    Process { id: jsonWrite }
    function savePrefs() { win.writeJson(win.prefsFile, { tileSize: win.tileSize, filmstrip: win.filmstrip }); }
    function loadPrefs() { prefsLister.running = true; }
    Process {
        id: prefsLister
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || echo "{}"', "sh", win.prefsFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(text) || {}; } catch (e) {}
                const size = Number(d.tileSize);
                win.tileSize = size >= 96 && size <= 280 ? size : 150;
                win.filmstrip = !!d.filmstrip;
            }
        }
    }
    function saveSmart() { win.writeJson(win.smartFile, win.smartAlbums); }
    function loadSmart() { smartLister.running = true; }
    Process {
        id: smartLister
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || echo "[]"', "sh", win.smartFile]
        stdout: StdioCollector {
            onStreamFinished: { try { win.smartAlbums = JSON.parse(text) || []; } catch (e) { win.smartAlbums = []; } }
        }
    }
    function saveSmartAlbum(name) {
        name = (name || "").trim();
        if (!name) return;
        const rule = { name: name, minRating: win.minRating, favoriteOnly: win.filter === "favorites",
            fromYear: win.timelinePeriod ? win.timelinePeriod.substring(0, 4) : "", tag: win.tagFilter };
        win.smartAlbums = win.smartAlbums.filter(a => a.name !== name).concat([rule]);
        saveSmart();
        win.smartName = "";
        win.activeSmart = name;
        win.importNote = Tr.t("Saved smart album %1", name);
    }

    // ---- People and nested keyword tags (all in meta.json) -----------------------
    function taggedPaths() {
        return win.selected.length ? win.selected.slice() : (win.detailPath ? [win.detailPath] : []);
    }
    function tagPeopleSelected() {
        const name = win.personName.trim();
        const paths = win.taggedPaths();
        if (!name || !paths.length) return;
        const m = Object.assign({}, win.meta);
        for (const p of paths)
            m[p] = Object.assign({ rating: 0, tags: "" }, m[p], {
                people: win.splitTags(m[p] && m[p].people).concat([name]).filter((v, i, a) => a.indexOf(v) === i).join(", ")
            });
        win.meta = m;
        saveMeta();
        win.personName = "";
        win.clearSelect();
        win.importNote = Tr.t("Tagged %1 photo%2 as %3", paths.length, paths.length === 1 ? "" : "s", name);
    }
    function addTagSelected(tag) {
        tag = (tag || "").trim();
        const paths = win.taggedPaths();
        if (!tag || !paths.length) return;
        const m = Object.assign({}, win.meta);
        for (const p of paths) {
            const cur = win.splitTags(m[p] && m[p].tags);
            if (cur.indexOf(tag) < 0) cur.push(tag);
            m[p] = Object.assign({ rating: 0, favorite: false }, m[p], { tags: cur.join(", ") });
        }
        win.meta = m;
        saveMeta();
        win.tagName = "";
        win.importNote = Tr.t("Tagged %1 photo%2 with %3", paths.length, paths.length === 1 ? "" : "s", tag);
    }
    function removeTagSelected(tag) {
        tag = (tag || "").trim();
        const paths = win.taggedPaths();
        if (!tag || !paths.length) return;
        const m = Object.assign({}, win.meta);
        for (const p of paths)
            m[p] = Object.assign({ rating: 0, favorite: false }, m[p], { tags: win.splitTags(m[p] && m[p].tags).filter(t => t !== tag).join(", ") });
        win.meta = m;
        saveMeta();
        win.tagName = "";
        win.importNote = Tr.t("Removed tag %1", tag);
    }

    // Renames and Auto Organize both move files; keep meta.json's path keys in
    // step so ratings, tags and people survive the move.
    function applyPathMap(map, message) {
        const m = Object.assign({}, win.meta);
        for (const old of Object.keys(map)) {
            if (m[old]) { m[map[old]] = m[old]; delete m[old]; }
        }
        win.meta = m;
        saveMeta();
        win.clearSelect();
        win.importNote = message;
        win.scan();
    }
    // shortcut: collisions get a "-2" suffix and only our own meta keys are
    // remapped; upgrade to a transactional move if other stores key on path.
    readonly property string renameCode: 'import os,sys,json\npat=sys.argv[1]\npaths=json.loads(sys.argv[2])\nn=0\nfor ch in reversed(pat):\n    if ch=="#": n+=1\n    else: break\nout={}\nfor i,p in enumerate(paths,1):\n    d=os.path.dirname(p); b=os.path.basename(p)\n    stem,ext=os.path.splitext(b)\n    name=(pat[:-n]+str(i).zfill(n)) if n else (pat+str(i).zfill(3))\n    dest=os.path.join(d,name+ext)\n    if dest==p: continue\n    k=2\n    while os.path.exists(dest):\n        dest=os.path.join(d,name+"-"+str(k)+ext); k+=1\n    try:\n        os.rename(p,dest); out[p]=dest\n    except Exception: pass\nprint(json.dumps(out))'
    function renameSelected() {
        const paths = win.taggedPaths();
        const pat = win.renamePattern.trim();
        if (!paths.length || !pat) return;
        renameProc.command = ["python3", "-c", win.renameCode, pat, JSON.stringify(paths)];
        renameProc.running = true;
        win.importNote = Tr.t("Renaming…");
    }
    Process {
        id: renameProc
        stdout: StdioCollector { onStreamFinished: {
            let map = {}; try { map = JSON.parse(text) || {}; } catch (e) {}
            win.applyPathMap(map, Tr.t("Renamed %1 photo%2", Object.keys(map).length, Object.keys(map).length === 1 ? "" : "s"));
        } }
    }
    readonly property string organizeCode: 'import os,sys,json,time\nroot=sys.argv[1]\npaths=json.loads(sys.argv[2])\nout={}\nfor p in paths:\n    try:\n        rel=os.path.relpath(p,root)\n        parts=rel.split(os.sep)\n        if len(parts)>=3 and len(parts[-3])==4 and parts[-3].isdigit() and len(parts[-2])==2 and parts[-2].isdigit(): continue\n        sub=time.strftime("%Y/%m",time.localtime(os.path.getmtime(p)))\n        dd=os.path.join(root,sub); os.makedirs(dd,exist_ok=True)\n        b=os.path.basename(p); dest=os.path.join(dd,b); k=2\n        while os.path.exists(dest) and os.path.abspath(dest)!=os.path.abspath(p):\n            stem,ext=os.path.splitext(b); dest=os.path.join(dd,stem+"-"+str(k)+ext); k+=1\n        if os.path.abspath(dest)!=os.path.abspath(p):\n            os.rename(p,dest); out[p]=dest\n    except Exception: pass\nprint(json.dumps(out))'
    function autoOrganizeSelected() {
        const paths = win.taggedPaths().length ? win.taggedPaths() : win.shown.map(p => p.path);
        if (!paths.length) { win.importNote = Tr.t("Nothing to organize"); return; }
        organizeProc.command = ["python3", "-c", win.organizeCode, win.pictures, JSON.stringify(paths)];
        organizeProc.running = true;
        win.importNote = Tr.t("Organizing…");
    }
    Process {
        id: organizeProc
        stdout: StdioCollector { onStreamFinished: {
            let map = {}; try { map = JSON.parse(text) || {}; } catch (e) {}
            const n = Object.keys(map).length;
            win.applyPathMap(map, n ? Tr.t("Organized %1 photo%2 into year/month folders", n, n === 1 ? "" : "s") : Tr.t("Already organized"));
        } }
    }

    // ---- contact sheet via ImageMagick (montage / magick montage / convert) ------
    readonly property string collageCode: 'import os,sys,json,shutil,subprocess\npaths=json.loads(sys.argv[1])\nout=sys.argv[2]\ntool=shutil.which("montage") or shutil.which("magick") or shutil.which("convert")\nif not tool:\n    print(json.dumps({"ok":False,"error":"no tool"})); sys.exit(0)\nif not paths:\n    print(json.dumps({"ok":False,"error":"empty"})); sys.exit(0)\nargs=[tool,"montage"] if os.path.basename(tool)=="magick" else [tool]\nargs+=["-label","%f","-tile","5x","-geometry","200x200+4+4","-background","#202020"]+paths+[out]\ntry:\n    subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=180)\n    print(json.dumps({"ok":True,"path":out}))\nexcept Exception as e:\n    print(json.dumps({"ok":False,"error":str(e)[:120]}))'
    function makeCollage() {
        const paths = win.taggedPaths().length ? win.taggedPaths() : win.shown.map(p => p.path);
        if (!paths.length) { win.importNote = Tr.t("Nothing to put in a collage"); return; }
        const out = win.pictures + "/Collage-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss") + ".jpg";
        collageProc.command = ["python3", "-c", win.collageCode, JSON.stringify(paths.slice(0, 40)), out];
        collageProc.running = true;
        win.importNote = Tr.t("Building collage…");
    }
    Process {
        id: collageProc
        stdout: StdioCollector { onStreamFinished: {
            let r = {}; try { r = JSON.parse(text) || {}; } catch (e) {}
            if (r.ok) {
                win.importNote = Tr.t("Collage saved to %1", r.path);
                win.scan();
            } else if (r.error === "no tool") {
                win.importNote = Tr.t("Install ImageMagick (montage) to make collages");
            } else if (r.error === "empty") {
                win.importNote = Tr.t("Nothing to put in a collage");
            } else {
                win.importNote = Tr.t("Could not make a collage: %1", r.error);
            }
        } }
    }

    // ---- Places: GPS from exiv2 (the tool PhotoMeta already uses) or exiftool ---
    readonly property string gpsCode: 'import os,sys,json,shutil,subprocess\ntool=shutil.which("exiv2") or shutil.which("exiftool")\npaths=json.loads(sys.argv[1])\nif not tool:\n    print(json.dumps({"tool":False,"data":{}})); sys.exit(0)\ndef num(s):\n    s=s.strip()\n    if "/" in s:\n        a,b=s.split("/",1); b=float(b); return float(a)/b if b else 0.0\n    try: return float(s)\n    except Exception: return 0.0\ndef dms(v,ref):\n    parts=v.split()\n    if not parts: return None\n    dec=num(parts[0])\n    if len(parts)>1: dec+=num(parts[1])/60.0\n    if len(parts)>2: dec+=num(parts[2])/3600.0\n    return -dec if ref.strip().upper() in ("S","W") else dec\ndata={}\nfor p in paths:\n    try:\n        if os.path.basename(tool).startswith("exiftool"):\n            out=subprocess.run([tool,"-GPSLatitude#","-GPSLongitude#","-GPSLatitudeRef","-GPSLongitudeRef",p],capture_output=True,text=True,timeout=8).stdout\n            vals={}\n            for line in out.splitlines():\n                if ":" in line:\n                    k,v=line.split(":",1); vals[k.strip().lower()]=v.strip()\n            lat=dms(vals.get("gps latitude",""),vals.get("gps latitude ref","")); lon=dms(vals.get("gps longitude",""),vals.get("gps longitude ref",""))\n        else:\n            out=subprocess.run([tool,"-g","Exif.GPSInfo.GPSLatitude","-g","Exif.GPSInfo.GPSLatitudeRef","-g","Exif.GPSInfo.GPSLongitude","-g","Exif.GPSInfo.GPSLongitudeRef","-pv",p],capture_output=True,text=True,timeout=8).stdout\n            vals={}\n            for line in out.splitlines():\n                bits=line.strip().split(None,1)\n                if len(bits)==2: vals[bits[0]]=bits[1].strip()\n            lat=dms(vals.get("Exif.GPSInfo.GPSLatitude",""),vals.get("Exif.GPSInfo.GPSLatitudeRef",""))\n            lon=dms(vals.get("Exif.GPSInfo.GPSLongitude",""),vals.get("Exif.GPSInfo.GPSLongitudeRef",""))\n        if lat is not None and lon is not None: data[p]=[round(lat,5),round(lon,5)]\n    except Exception: pass\nprint(json.dumps({"tool":True,"data":data}))'
    function scanPlaces() {
        if (gpsProc.running) return;
        win.placesReady = false;
        gpsProc.command = ["python3", "-c", win.gpsCode, JSON.stringify(win.shown.slice(0, 400).map(p => p.path))];
        gpsProc.running = true;
    }
    Process {
        id: gpsProc
        stdout: StdioCollector { onStreamFinished: {
            let d = { tool: false, data: {} };
            try { d = JSON.parse(text) || d; } catch (e) {}
            win.placesTool = !!d.tool;
            win.placeData = d.data || {};
            win.placesReady = true;
            const groups = {};
            for (const p of win.shown) {
                const c = win.placeData[p.path];
                if (!c) continue;
                const k = win.placeLabel(c);
                (groups[k] = groups[k] || []).push(p);
            }
            win.places = Object.keys(groups).sort().map(k => ({ key: k, label: k, items: groups[k] }));
        } }
    }
    function openSelectedPlace() {
        const c = win.placeData[win.detailPath || (win.selected[0] || "")];
        if (!c) return;
        const url = "https://www.openstreetmap.org/?mlat=" + c[0] + "&mlon=" + c[1] + "#map=14/" + c[0] + "/" + c[1];
        Quickshell.execDetached(["gio", "open", url]);
    }

    // ---- exact duplicates (identical bytes) — Digikam / Apple Photos ------------
    // One python pass over Pictures, same extension set and depth as scan(). The
    // first copy of each hash is kept; only the extras are listed, so "remove
    // duplicates" can never delete the only copy of a picture.
    readonly property string duplicatesCode: 'import os,sys,json,hashlib\nroot=sys.argv[1]\nexts=(".jpg",".jpeg",".png",".webp",".gif",".avif",".bmp")\nseen={}\ndup=[]\nfor dp,dn,fn in os.walk(root):\n    dn[:]=[d for d in dn if not d.startswith(".")]\n    for n in sorted(fn):\n        if not n.lower().endswith(exts): continue\n        p=os.path.join(dp,n)\n        rel=os.path.relpath(p,root)\n        if rel.startswith("..") or rel.count(os.sep)>=4: continue\n        try:\n            if os.path.getsize(p)>104857600: continue\n            h=hashlib.sha256()\n            with open(p,"rb") as f:\n                for chunk in iter(lambda:f.read(65536),b""): h.update(chunk)\n            d=h.hexdigest()\n        except Exception:\n            continue\n        if d in seen: dup.append(p)\n        else: seen[d]=p\nprint(json.dumps(dup))'
    function findDuplicates() {
        dupProc.command = ["python3", "-c", win.duplicatesCode, win.pictures];
        dupProc.running = true;
    }
    function trashDuplicates() {
        const doomed = win.duplicatePaths.slice();
        if (!doomed.length) return;
        Files.trash(doomed, r => {
            if (r && r.error) win.importNote = Tr.t("Could not remove duplicates: %1", r.error);
            else win.importNote = Tr.t("Moved %1 duplicate%2 to trash", doomed.length, doomed.length === 1 ? "" : "s");
            win.duplicatePaths = [];
            win.findDuplicates();
            win.scan();
        });
    }
    Process {
        id: dupProc
        stdout: StdioCollector {
            onStreamFinished: { try { win.duplicatePaths = JSON.parse(text) || []; } catch (e) { win.duplicatePaths = []; } }
        }
    }

    // ---- multi-select ------------------------------------------------------------
    function toggleSelect(path) {
        win.selected = win.selected.indexOf(path) < 0 ? win.selected.concat([path]) : win.selected.filter(p => p !== path);
    }
    function clearSelect() { win.selected = []; }
    // Ctrl+A: every photo in the current view, not just the loaded tiles
    function selectAll() { win.selected = win.shown.map(p => p.path); }
    function trashSelected() {
        // with no batch selection, Delete acts on the photo whose details are shown
        const paths = win.selected.length ? win.selected.slice() : (win.detailPath ? [win.detailPath] : []);
        if (!paths.length) return;
        Files.trash(paths, r => {
            if (r && r.error) win.importNote = Tr.t("Could not move to trash: %1", r.error);
            win.selected = [];
            if (paths.indexOf(win.detailPath) >= 0) win.detailPath = "";
            win.scan();
        });
    }
    function albumSelected() {
        if (!win.selected.length) return;
        const Photos = photosApi;   // a JS local: QML ids cannot start uppercase
        const name = (win.newAlbumName || "").trim() || Tr.t("Selection");
        Photos.createAlbum(name, win.selected.slice());
        win.newAlbumName = "";
        win.selected = [];
        win.albumLister.running = true;
    }
    onDetailPathChanged: if (win.detailPath) PhotoMeta.read(win.detailPath)

    function scan() {
        scanning = true;
        scanError = "";
        dirCheck.command = ["test", "-d", win.pictures];
        dirCheck.running = true;
        lister.command = ["sh", "-c", 'find "$1" -maxdepth 4 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.avif" -o -iname "*.bmp" \\) -not -path "*/.*" -printf "%T@ %s %p\\n" 2>/dev/null | sort -rn | head -5000', "sh", pictures];
        lister.running = true;
    }
    Process {
        id: dirCheck
        onExited: code => { win.scanError = code === 0 ? "" : Tr.t("Pictures folder not found: %1", win.pictures); }
    }
    Component.onCompleted: { scan(); loadMeta(); loadPrefs(); loadSmart(); findDuplicates(); }
    onVisibleChanged: if (visible) { scan(); albumLister.running = true; loadMeta(); loadPrefs(); loadSmart(); findDuplicates(); }

    // the Viewer's edit mode is its crop / rotate / markup mode
    function adjust(path) {
        if (!path) return;
        Viewer.open(path);
        Viewer.startEdit();
    }

    // ---- metadata actions (Finder / Nautilus / Digikam) --------------------------
    function copyPath(path) { if (path) Files.copyPath(path); }
    function reveal(path) {
        if (!path) return;
        Files.show(path.substring(0, path.lastIndexOf("/")) || win.pictures);
    }
    function openWith(path) {
        if (path) Quickshell.execDetached(["gio", "open", "--", path]);
    }

    // ---- full-screen slideshow over the filtered library -------------------------
    function startSlideshow(path) {
        const list = win.shown;
        if (!list.length) return;
        const at = path ? list.findIndex(p => p.path === path) : 0;
        win.slideIndex = at < 0 ? 0 : at;
        win.slidePaused = false;
        win.slideshow = true;
        slideOverlay.forceActiveFocus();
    }
    function stopSlideshow() { win.slideshow = false; }
    function slideNext() { const n = win.shown.length; if (n) win.slideIndex = (win.slideIndex + 1) % n; }
    function slidePrev() { const n = win.shown.length; if (n) win.slideIndex = (win.slideIndex - 1 + n) % n; }
    readonly property string slidePath: win.slideIndex >= 0 && win.slideIndex < win.shown.length ? win.shown[win.slideIndex].path : ""
    Timer {
        interval: win.slideSeconds * 1000
        running: win.slideshow && win.shown.length > 1 && !win.slidePaused
        repeat: true
        onTriggered: win.slideNext()
    }

    // ---- import from a mounted phone / camera / USB -------------------------------
    function importPhotos(paths) {
        if (!paths || !paths.length || importer.running) return;
        importer.count = paths.length;
        const script = win.importDated
            ? 'd=$1; shift; mkdir -p -- "$d"; for f in "$@"; do t=$(date -r "$f" +%Y/%Y-%m 2>/dev/null || echo misc); mkdir -p -- "$d/$t"; cp -n -- "$f" "$d/$t/"; done'
            : 'd=$1; shift; mkdir -p -- "$d" && cp -n -- "$@" "$d"';
        importer.command = ["sh", "-c", script, "sh", win.pictures].concat(paths);
        win.importBusy = true;
        win.importNote = Tr.t("Copying %1 photo%2…", paths.length, paths.length === 1 ? "" : "s");
        importer.running = true;
    }
    Process {
        id: importer
        property int count: 0
        property string err: ""
        stderr: StdioCollector { onStreamFinished: importer.err = text.trim().split("\n").pop() || "" }
        onExited: code => {
            win.importBusy = false;
            if (code === 0) {
                win.importNote = Tr.t("Imported %1 photo%2", importer.count, importer.count === 1 ? "" : "s");
                win.scan();
            } else {
                win.importNote = Tr.t("Import failed: %1", importer.err || Tr.t("copy error"));
            }
        }
    }

    // ---- albums ------------------------------------------------------------------
    property var albums: []              // [{ name, members: [paths] }] — user albums
    property string activeAlbum: ""      // the selected album name, "" for All
    property string newAlbumName: ""

    function refresh() { if (lister.running) lister.running = true; if (albumLister.running) albumLister.running = true; }

    Process {
        id: albumLister
        command: ["sh", "-c", 'd="${XDG_DATA_HOME:-$HOME/.local/share}/shani-photos/albums.json"; [ -f "$d" ] && cat "$d" || echo "[]"']
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.albums = JSON.parse(text); } catch (e) { win.albums = []; }
            }
        }
    }

    function createAlbum(name, photoPaths) {
        Quickshell.execDetached(["sh", "-c",
            'd="$1/albums.json"; mkdir -p "$2"; ex=$(cat "$d" 2>/dev/null || echo "[]");'
            + 'echo "$ex" | python3 -c "import json,sys; a=json.loads(sys.stdin.read() or \"[]\"); a.append({\\\"name\\\":$3, \\\"members\\\":$4}); print(json.dumps(a))" > "$d.tmp" 2>/dev/null && mv "$d.tmp" "$d" || true'
        , "sh", Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share") + "/shani-photos", Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share") + "/shani-photos", JSON.stringify(String(name)), JSON.stringify(photoPaths)]);
    }
    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const at = line.indexOf(" ");
                    if (at <= 0)
                        continue;
                    const t = parseFloat(line.substring(0, at));
                    const rest = line.substring(at + 1);
                    const sp = rest.indexOf(" ");
                    if (sp < 0)
                        continue;
                    const size = parseFloat(rest.substring(0, sp));
                    out.push({ path: rest.substring(sp + 1), time: t, size: size, month: Qt.formatDate(new Date(t * 1000), "MMMM yyyy") });
                }
                win.photos = out;
                win.scanning = false;
                if (win.activeAlbum !== "")
                    win.activeAlbum = win.activeAlbum; // re-evaluate shown filter
            }
        }
    }

    // keep albums refreshed on scan
    onShownChanged: {}
    function _refreshAlbums() { if (albumLister.running) albumLister.running = true; }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.photos = false
        Keys.onPressed: event => {
            // a text field keeps Ctrl+A and Delete for its own text
            if (photoSearch.activeFocus || albumField.activeFocus || tagsField.activeFocus || personField.activeFocus || tagNameField.activeFocus || renameField.activeFocus || smartField.activeFocus)
                return;
            if (win.slideshow)   // the overlay owns the keys while it is up
                return;
            const control = (event.modifiers & Qt.ControlModifier) !== 0;
            // Ctrl+A selects everything on screen (Finder / Nautilus / Dolphin)
            if (control && event.key === Qt.Key_A) {
                win.selectAll();
                event.accepted = true;
                return;
            }
            // Delete moves the selection - or the detailed photo - to the trash
            if (event.key === Qt.Key_Delete && (win.selected.length > 0 || win.detailPath !== "")) {
                win.trashSelected();
                event.accepted = true;
                return;
            }
            const at = win.detailPath || win.focusPath || (win.shown[0] ? win.shown[0].path : "");
            if (!control && event.key === Qt.Key_S) { win.startSlideshow(at); event.accepted = true; return; }
            if (!control && event.key === Qt.Key_F) { win.toggleFavorite(at); event.accepted = true; return; }
            if (!control && event.key === Qt.Key_C) { win.copyPath(at); event.accepted = true; return; }
            if (!control && event.key === Qt.Key_R) { win.reveal(at); event.accepted = true; return; }
            if (!control && event.key === Qt.Key_O) { win.openWith(at); event.accepted = true; return; }
            if (control && event.key === Qt.Key_D) {
                win.filter = win.filter === "duplicates" ? "all" : "duplicates";
                win.findDuplicates();
                event.accepted = true;
                return;
            }
            // Picasa-style shortcuts: views, tags, timeline, batch actions.
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            if (control && !shift && event.key === Qt.Key_P) { win.view = win.view === "people" ? "photos" : "people"; if (win.view === "people") personField.forceActiveFocus(); event.accepted = true; return; }
            if (control && !shift && event.key === Qt.Key_L) { win.view = win.view === "places" ? "photos" : "places"; if (win.view === "places") win.scanPlaces(); event.accepted = true; return; }
            if (control && !shift && event.key === Qt.Key_T) { tagNameField.forceActiveFocus(); event.accepted = true; return; }
            if (control && shift && event.key === Qt.Key_R) { renameField.forceActiveFocus(); event.accepted = true; return; }
            if (control && shift && event.key === Qt.Key_O) { win.autoOrganizeSelected(); event.accepted = true; return; }
            if (control && shift && event.key === Qt.Key_C) { win.makeCollage(); event.accepted = true; return; }
            if (!control && !shift && event.key === Qt.Key_G) { win.filmstrip = !win.filmstrip; savePrefs(); event.accepted = true; return; }
            if (!control && !shift && event.key === Qt.Key_BracketLeft) { win.stepTimeline(-1); event.accepted = true; return; }
            if (!control && !shift && event.key === Qt.Key_BracketRight) { win.stepTimeline(1); event.accepted = true; return; }
            if (!control && !shift && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) { win.tileSize = Math.min(280, win.tileSize + 12); savePrefs(); event.accepted = true; return; }
            if (!control && !shift && event.key === Qt.Key_Minus) { win.tileSize = Math.max(96, win.tileSize - 12); savePrefs(); event.accepted = true; return; }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)
                Repeater {
                    model: [["all", Tr.t("All")], ["camera", Tr.t("Camera")], ["screenshots", Tr.t("Screenshots")], ["favorites", Tr.t("Favorites")], ["duplicates", Tr.t("Duplicates")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.filter === modelData[0]
                        onClicked: {
                            win.filter = modelData[0];
                            if (modelData[0] === "duplicates") win.findDuplicates();
                        }
                    }
                }
                // Picasa's library / People / Places entry points
                Repeater {
                    model: [["photos", Tr.t("Photos")], ["people", Tr.t("People")], ["places", Tr.t("Places")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.view === modelData[0]
                        onClicked: {
                            win.view = modelData[0];
                            if (modelData[0] === "places") win.scanPlaces();
                        }
                    }
                }
                Repeater {
                    model: [["day", Tr.t("Day")], ["month", Tr.t("Month")], ["year", Tr.t("Year")], ["folder", Tr.t("Folder")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.groupBy === modelData[0]
                        onClicked: win.groupBy = modelData[0]
                    }
                }
                // rating floor: Digikam's "4 stars and above" view, over the
                // ratings already stored in meta.json
                Repeater {
                    model: [1, 2, 3, 4, 5]
                    Choice {
                        required property int modelData
                        text: modelData + "★+"
                        selected: win.minRating === modelData
                        onClicked: win.minRating = win.minRating === modelData ? 0 : modelData
                    }
                }
                TextField {
                    id: photoSearch
                    Layout.preferredWidth: Theme.px(180)
                    placeholder: Tr.t("Search photos…")
                    text: win.searchText
                    onTextChanged: win.searchText = text
                }
                Item { Layout.fillWidth: true }
                // ---- albums ----
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    visible: win.albums.length > 0
                    Repeater {
                        model: win.albums
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: Math.min(label.implicitWidth + 30, 120)
                            height: Theme.px(26)
                            radius: Theme.px(13)
                            color: win.activeAlbum === modelData.name ? Theme.accent : (area.containsMouse ? Theme.hover : Theme.surface1)
                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: modelData.name + " (" + (modelData.members ? modelData.members.length : 0) + ")"
                                color: win.activeAlbum === modelData.name ? "white" : Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(10) * Theme.fontScale
                                elide: Text.ElideMiddle
                            }
                            MouseArea { id: area; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { win.activeAlbum = win.activeAlbum === modelData.name ? "" : modelData.name; } }
                        }
                    }
                }
                // "New album" button
                Button {
                    visible: true
                    text: Tr.t("+ Album")
                    flat: true
                    onClicked: {
                        // Create an album from current filter
                        const Photos = photosApi;   // JS local; QML ids cannot start uppercase
                        const selected = win.shown.map(p => p.path);
                        if (selected.length > 0) {
                            const name = selected[0].split("/").slice(-2, -1)[0] + (selected.length > 1 ? " +" + (selected.length - 1) : "");
                            Photos.createAlbum(name, selected);
                        }
                    }
                }
                Button {
                    text: Tr.t("Slideshow")
                    flat: true
                    enabled: win.shown.length > 0
                    onClicked: win.startSlideshow()
                }
                Button {
                    text: Tr.t("Import…")
                    flat: true
                    enabled: !win.importBusy
                    onClicked: FilePicker.open({
                        mode: "open", multiple: true,
                        title: Tr.t("Photos to import (phone, camera, USB)"),
                        filters: ["jpg", "jpeg", "png", "webp", "gif", "avif", "bmp", "heic", "heif"],
                        onPicked: paths => win.importPhotos(paths)
                    })
                }
                Choice {
                    text: Tr.t("Dated folders")
                    selected: win.importDated
                    onClicked: win.importDated = !win.importDated
                }
                Text {
                    text: win.scanning ? Tr.t("Looking…") : win.shown.length + " " + Tr.t("photos")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                IconButton { size: Theme.px(30); icon: "view-refresh"; tip: Tr.t("Look again"); onClicked: win.scan() }
                IconButton { size: Theme.px(30); icon: "folder-pictures"; tip: Tr.t("Open Pictures in Files"); onClicked: Files.show(win.pictures) }
                IconButton { size: Theme.px(30); icon: "document-properties"; tip: Tr.t("Details"); on: win.detailsShown; onClicked: win.detailsShown = !win.detailsShown }
            }
            // sort order on its own row: the toolbar above is already full at
            // the default width, which used to push the last sort off-screen.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    text: Tr.t("Sort")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Repeater {
                    model: [["newest", Tr.t("Newest")], ["oldest", Tr.t("Oldest")], ["name", Tr.t("Name")], ["size", Tr.t("Size")]]
                    Choice {
                        required property var modelData
                        text: modelData[1]
                        selected: win.sortOrder === modelData[0]
                        onClicked: win.sortOrder = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
            }
            // folder navigation (Digikam's folder tree, flattened to chips): a
            // click scopes the view to one folder and all folders below it.
            RowLayout {
                Layout.fillWidth: true
                visible: win.folders.length > 0
                spacing: Theme.px(4)
                Choice {
                    text: Tr.t("All folders")
                    selected: win.folderFilter === ""
                    onClicked: win.folderFilter = ""
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.folders
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: win.folderFilter === modelData
                            onClicked: win.folderFilter = win.folderFilter === modelData ? "" : modelData
                        }
                    }
                }
            }
            // ---- timeline scrubber: one chip per month in the library -----------
            RowLayout {
                Layout.fillWidth: true
                visible: win.timelinePeriods.length > 0
                spacing: Theme.px(4)
                Text {
                    text: Tr.t("Timeline")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Choice {
                    text: Tr.t("All")
                    selected: win.timelinePeriod === ""
                    onClicked: win.timelinePeriod = ""
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(28)
                    implicitHeight: Theme.px(28)
                    contentWidth: scrubRow.implicitWidth
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: scrubRow
                        spacing: Theme.px(2)
                        Repeater {
                            model: win.timelinePeriods
                            Choice {
                                required property string modelData
                                text: modelData
                                selected: win.timelinePeriod === modelData
                                onClicked: win.timelinePeriod = win.timelinePeriod === modelData ? "" : modelData
                            }
                        }
                    }
                }
                Text {
                    text: Tr.t("[ / ] to step")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(10) * Theme.fontScale
                }
            }
            // ---- People: name chips + assign a name to the selection -------------
            RowLayout {
                Layout.fillWidth: true
                visible: win.view === "people"
                spacing: Theme.px(4)
                Text {
                    text: Tr.t("People")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Choice {
                    text: Tr.t("Everyone")
                    selected: win.personFilter === ""
                    onClicked: win.personFilter = ""
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.people
                        Choice {
                            required property var modelData
                            text: modelData.name + " (" + modelData.paths.length + ")"
                            selected: win.personFilter === modelData.name
                            onClicked: win.personFilter = win.personFilter === modelData.name ? "" : modelData.name
                        }
                    }
                }
                TextField {
                    id: personField
                    Layout.preferredWidth: Theme.px(130)
                    placeholderText: Tr.t("Name for selection")
                    label: Tr.t("Person name")
                    text: win.personName
                    onTextChanged: win.personName = text
                    onAccepted: win.tagPeopleSelected()
                }
                Button {
                    text: Tr.t("Tag people")
                    flat: true
                    enabled: win.selected.length > 0 || win.detailPath !== ""
                    onClicked: win.tagPeopleSelected()
                }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: win.view === "people" && win.people.length === 0
                icon: "user"
                title: Tr.t("No people tagged yet")
                subtitle: Tr.t("Select photos, enter a name and choose Tag people")
                actionText: Tr.t("Focus name field")
                onAction: personField.forceActiveFocus()
            }
            // ---- Places: group by GPS location, open the map ---------------------
            RowLayout {
                Layout.fillWidth: true
                visible: win.view === "places"
                spacing: Theme.px(4)
                Text {
                    text: win.placesReady ? Tr.t("%1 places", win.places.length) : Tr.t("Reading locations…")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Choice {
                    text: Tr.t("All places")
                    selected: win.placeFilter === ""
                    onClicked: win.placeFilter = ""
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.places
                        Choice {
                            required property var modelData
                            text: modelData.label + " (" + modelData.items.length + ")"
                            selected: win.placeFilter === modelData.key
                            onClicked: win.placeFilter = win.placeFilter === modelData.key ? "" : modelData.key
                        }
                    }
                }
                Button {
                    text: Tr.t("Open in Maps")
                    flat: true
                    enabled: !!win.placeData[win.detailPath || (win.selected[0] || "")]
                    onClicked: win.openSelectedPlace()
                }
                IconButton { size: Theme.px(28); icon: "view-refresh"; tip: Tr.t("Scan locations"); onClicked: win.scanPlaces() }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: win.view === "places" && win.placesReady && win.places.length === 0
                icon: "mark-location"
                title: win.placesTool ? Tr.t("No photos with location") : Tr.t("Location reader not installed")
                subtitle: win.placesTool ? Tr.t("Photos carrying GPS coordinates appear here")
                    : Tr.t("Install exiv2 or exiftool to read GPS coordinates")
                actionText: win.placesTool ? Tr.t("Scan again") : ""
                onAction: win.scanPlaces()
            }
            // ---- keyword tags and saved searches (smart albums) ------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    text: Tr.t("Tags")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Choice {
                    text: Tr.t("All tags")
                    selected: win.tagFilter === ""
                    onClicked: win.tagFilter = ""
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.allTags
                        Choice {
                            required property string modelData
                            text: modelData
                            selected: win.tagFilter === modelData
                            onClicked: win.tagFilter = win.tagFilter === modelData ? "" : modelData
                        }
                    }
                }
                TextField {
                    id: tagNameField
                    Layout.preferredWidth: Theme.px(150)
                    placeholderText: Tr.t("Tag, e.g. Family > Kids")
                    label: Tr.t("Keyword tag")
                    text: win.tagName
                    onTextChanged: win.tagName = text
                    onAccepted: win.addTagSelected(text)
                }
                Button { text: Tr.t("Add tag"); flat: true; onClicked: win.addTagSelected(tagNameField.text) }
                Button { text: Tr.t("Remove tag"); flat: true; onClicked: win.removeTagSelected(tagNameField.text) }
            }
            Text {
                Layout.fillWidth: true
                visible: win.allTags.length === 0
                text: Tr.t("No keyword tags yet — select photos and add one (use > to nest)")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(4)
                Text {
                    text: Tr.t("Smart albums")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                    Accessible.name: text
                }
                Choice {
                    text: Tr.t("All")
                    selected: win.activeSmart === ""
                    onClicked: win.activeSmart = ""
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Repeater {
                        model: win.smartAlbums
                        Choice {
                            required property var modelData
                            text: modelData.name
                            selected: win.activeSmart === modelData.name
                            onClicked: win.activeSmart = win.activeSmart === modelData.name ? "" : modelData.name
                        }
                    }
                }
                TextField {
                    id: smartField
                    Layout.preferredWidth: Theme.px(130)
                    placeholderText: Tr.t("Smart album name")
                    label: Tr.t("Smart album name")
                    text: win.smartName
                    onTextChanged: win.smartName = text
                    onAccepted: win.saveSmartAlbum(text)
                }
                Button { text: Tr.t("+ Smart album"); flat: true; onClicked: win.saveSmartAlbum(smartField.text) }
            }
            Text {
                Layout.fillWidth: true
                visible: win.smartAlbums.length === 0
                text: Tr.t("No smart albums yet — set a filter and save it")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
            }
            // batch operations on the multi-selection (Ctrl/Shift-click tiles)
            RowLayout {
                Layout.fillWidth: true
                visible: win.selected.length > 0
                spacing: Theme.px(6)
                Text {
                    text: Tr.t("%1 selected", win.selected.length)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
                }
                TextField {
                    id: albumField
                    Layout.preferredWidth: Theme.px(140)
                    placeholderText: Tr.t("Album name")
                    text: win.newAlbumName
                    onTextChanged: win.newAlbumName = text
                }
                Button { text: Tr.t("Add to album"); flat: true; onClicked: win.albumSelected() }
                Button { text: Tr.t("Favorite"); flat: true; onClicked: win.favoriteSelected() }
                TextField {
                    id: renameField
                    Layout.preferredWidth: Theme.px(170)
                    placeholderText: Tr.t("Pattern, e.g. Venice-2026-###")
                    label: Tr.t("Rename pattern")
                    text: win.renamePattern
                    onTextChanged: win.renamePattern = text
                    onAccepted: win.renameSelected()
                }
                Button { text: Tr.t("Rename"); flat: true; onClicked: win.renameSelected() }
                Button { text: Tr.t("Auto organize"); flat: true; onClicked: win.autoOrganizeSelected() }
                Button { text: Tr.t("Collage"); flat: true; onClicked: win.makeCollage() }
                Repeater {
                    model: 5
                    Choice {
                        required property int modelData
                        text: "★".repeat(modelData)
                        onClicked: win.rateSelected(modelData)
                    }
                }
                Button { text: Tr.t("Move to trash"); flat: true; onClicked: win.trashSelected() }
                Button {
                    text: Tr.t("Remove duplicates")
                    flat: true
                    kind: "danger"
                    visible: win.filter === "duplicates" && win.duplicatePaths.length > 0
                    onClicked: win.trashDuplicates()
                }
                Button { text: Tr.t("Clear"); flat: true; onClicked: win.clearSelect() }
                Item { Layout.fillWidth: true }
            }
            Text {
                visible: win.importNote !== "" || win.scanError !== ""
                Layout.fillWidth: true
                text: win.scanError !== "" ? win.scanError : win.importNote
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(11) * Theme.fontScale
                elide: Text.ElideRight
            }

            // ---- filmstrip + persisted thumbnail size ----------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                SliderRow {
                    Layout.fillWidth: true
                    icon: "zoom-fit-best"
                    label: Tr.t("Thumbnail size")
                    value: (win.tileSize - 96) / 184
                    onMoved: v => { win.tileSize = Math.round(96 + v * 184); savePrefs(); }
                }
                Choice {
                    text: Tr.t("Filmstrip")
                    selected: win.filmstrip
                    onClicked: { win.filmstrip = !win.filmstrip; savePrefs(); }
                }
                Text {
                    text: win.tileSize + " px"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: win.filmstrip && win.shown.length > 0
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(72)
                    implicitHeight: Theme.px(72)
                    orientation: ListView.Horizontal
                    model: win.shown
                    spacing: Theme.px(2)
                    clip: true
                    delegate: Rectangle {
                        required property var modelData
                        width: Theme.px(92)
                        height: Theme.px(66)
                        radius: Theme.radiusSmall
                        color: Theme.surface1
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(160, 160)
                            source: "file://" + modelData.path.split("/").map(encodeURIComponent).join("/")
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: modelData.path === win.detailPath ? 2 : 0
                            border.color: Theme.accent
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                win.detailPath = modelData.path;
                                win.focusPath = modelData.path;
                                Viewer.open(modelData.path);
                            }
                        }
                        Accessible.role: Accessible.Graphic
                        Accessible.name: Tr.t("Filmstrip photo %1", modelData.path.split("/").pop())
                        Accessible.onPressAction: Viewer.open(modelData.path)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.px(8)
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: monthList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(14)
                boundsBehavior: Flickable.StopAtBounds
                model: win.groups
                // one group: its name, then its photos as square tiles
                delegate: Column {
                    id: monthCol
                    required property var modelData
                    width: monthList.width
                    spacing: Theme.px(8)
                    readonly property int cols: Math.max(2, Math.floor(width / win.tileSize))
                    readonly property real cell: width / cols
                    Text {
                        text: monthCol.modelData.key + "  ·  " + monthCol.modelData.items.length
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(14) * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Grid {
                        columns: monthCol.cols
                        spacing: 0
                        Repeater {
                            model: monthCol.modelData.items
                            Item {
                                id: tile
                                required property var modelData
                                width: monthCol.cell
                                height: monthCol.cell
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(3)
                                    radius: Theme.radiusSmall
                                    color: Theme.surface1
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize: Qt.size(300, 300)
                                        source: "file://" + tile.modelData.path.split("/").map(encodeURIComponent).join("/")
                                    }
                                    Rectangle { anchors.fill: parent; color: "transparent"; radius: parent.radius; border.width: win.selected.indexOf(tile.modelData.path) >= 0 ? 3 : (tileArea.containsMouse ? 2 : 0); border.color: Theme.accent }
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(3)
                                        radius: Theme.radiusSmall
                                        color: "transparent"
                                        border.width: tile.modelData.path === win.focusPath ? 2 : 0
                                        border.color: Theme.accent
                                    }
                                    Text {
                                        anchors { top: parent.top; left: parent.left; margins: Theme.px(4) }
                                        visible: win.favoriteOf(tile.modelData.path)
                                        text: "★"
                                        color: "#ffd54a"
                                        font.pixelSize: Theme.px(16) * Theme.fontScale
                                    }
                                    Text {
                                        anchors { top: parent.top; right: parent.right; margins: Theme.px(4) }
                                        visible: win.duplicatePaths.indexOf(tile.modelData.path) >= 0
                                        text: "⧉"
                                        color: Theme.accent
                                        font.pixelSize: Theme.px(14) * Theme.fontScale
                                    }
                                }
                                Accessible.role: Accessible.Graphic
                                Accessible.name: tile.modelData.path.split("/").pop()
                                Accessible.onPressAction: Viewer.open(tile.modelData.path)
                                MouseArea {
                                    id: tileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const p = tile.modelData.path;
                                        if (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) {
                                            // Shift-click selects the whole range since the
                                            // last plain click (Finder / Nautilus behaviour)
                                            if ((mouse.modifiers & Qt.ShiftModifier) && !(mouse.modifiers & Qt.ControlModifier) && win.focusAnchor) {
                                                const list = win.shown.map(x => x.path);
                                                const a = list.indexOf(win.focusAnchor), b = list.indexOf(p);
                                                if (a >= 0 && b >= 0) {
                                                    const lo = Math.min(a, b), hi = Math.max(a, b);
                                                    let sel = win.selected.slice();
                                                    for (let i = lo; i <= hi; i++) if (sel.indexOf(list[i]) < 0) sel.push(list[i]);
                                                    win.selected = sel;
                                                    win.focusPath = p;
                                                    return;
                                                }
                                            }
                                            win.toggleSelect(p);
                                            win.focusAnchor = p;
                                            win.focusPath = p;
                                            return;
                                        }
                                        if (win.selected.length) { win.clearSelect(); return; }
                                        win.focusAnchor = p;
                                        win.focusPath = p;
                                        win.detailPath = p;
                                        Viewer.open(p);
                                    }
                                }
                                RowLayout {
                                    anchors { right: parent.right; bottom: parent.bottom; margins: Theme.px(4) }
                                    spacing: Theme.px(2)
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "media-playlist-play"
                                        tip: Tr.t("Slideshow from here")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: { Viewer.open(tile.modelData.path); Viewer.toggleSlideshow(); }
                                    }
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: win.favoriteOf(tile.modelData.path) ? "starred" : "non-starred"
                                        tip: Tr.t("Favorite")
                                        on: win.favoriteOf(tile.modelData.path)
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: win.toggleFavorite(tile.modelData.path)
                                    }
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "folder-open"
                                        tip: Tr.t("Reveal in Files")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: win.reveal(tile.modelData.path)
                                    }
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "user-trash"
                                        tip: Tr.t("Move to trash")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: { Viewer.trash(); win.scan(); }
                                    }
                                    IconButton {
                                        size: Theme.px(22)
                                        icon: "document-edit"
                                        tip: Tr.t("Adjust…")
                                        opacity: tileArea.containsMouse ? 1 : 0.7
                                        onClicked: win.adjust(tile.modelData.path)
                                    }
                                }
                                KeyFocus {
                                    name: tile.modelData.path.split("/").pop()
                                    columns: monthCol.cols   // Up / Down jump a row of the grid
                                    onActivated: {
                                        win.focusPath = tile.modelData.path;
                                        Viewer.open(tile.modelData.path);
                                    }
                                }
                            }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: !win.scanning && win.shown.length === 0
                    icon: win.scanError !== "" ? "dialog-warning" : "folder-pictures"
                    title: win.scanError !== "" ? win.scanError
                        : win.searchText.trim() !== "" ? Tr.t("No photos match that search")
                        : win.timelinePeriod !== "" ? Tr.t("No photos in %1", win.timelinePeriod)
                        : win.personFilter !== "" ? Tr.t("No photos of %1", win.personFilter)
                        : win.tagFilter !== "" ? Tr.t("No photos tagged %1", win.tagFilter)
                        : win.activeSmart !== "" ? Tr.t("No photos in this smart album")
                        : win.filter === "favorites" ? Tr.t("No favorites yet")
                        : win.filter === "duplicates" ? Tr.t("No duplicates found")
                        : Tr.t("No photos yet")
                    subtitle: win.scanError !== "" ? Tr.t("Import photos, or open Files to choose a folder")
                        : win.searchText.trim() !== "" || win.filter !== "all" || win.folderFilter !== "" || win.minRating > 0
                          || win.timelinePeriod !== "" || win.personFilter !== "" || win.tagFilter !== "" || win.placeFilter !== "" || win.activeSmart !== ""
                          ? Tr.t("Try clearing the filters or the search")
                          : Tr.t("Pictures in %1 show here — the camera's and the screenshots too").arg(win.pictures.replace(Quickshell.env("HOME"), "~"))
                    actionText: win.scanError !== "" ? Tr.t("Open Files") : Tr.t("Clear filters")
                    onAction: {
                        if (win.scanError !== "") {
                            Files.show(win.pictures);
                        } else {
                            win.searchText = "";
                            photoSearch.text = "";
                            win.filter = "all";
                            win.folderFilter = "";
                            win.minRating = 0;
                            win.timelinePeriod = "";
                            win.personFilter = "";
                            win.tagFilter = "";
                            win.placeFilter = "";
                            win.activeSmart = "";
                        }
                    }
                }
            }
            // ---- EXIF, rating and tags for the last-clicked photo ------------------
            Rectangle {
                visible: win.detailsShown
                Layout.preferredWidth: Theme.px(260)
                Layout.minimumWidth: Theme.px(200)
                Layout.fillHeight: true
                radius: Theme.radiusSmall
                color: Theme.surface1
                border.width: 1
                border.color: Theme.stroke
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(10)
                    spacing: Theme.px(8)
                    Text {
                        Layout.fillWidth: true
                        text: win.detailPath ? win.detailPath.split("/").pop() : Tr.t("No photo selected")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.px(13) * Theme.fontScale
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    Repeater {
                        model: PhotoMeta.details
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                text: modelData.label
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.value
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: Theme.px(11) * Theme.fontScale
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("Rating")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.px(11) * Theme.fontScale
                    }
                    Row {
                        spacing: Theme.px(2)
                        Repeater {
                            model: 5
                            Text {
                                required property int index
                                text: (index + 1) <= win.ratingOf(win.detailPath) ? "★" : "☆"
                                color: Theme.accent
                                font.pixelSize: Theme.px(18) * Theme.fontScale
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.setRating(win.detailPath, index + 1) }
                            }
                        }
                    }
                    Row {
                        spacing: Theme.px(2)
                        Text {
                            text: win.favoriteOf(win.detailPath) ? "★" : "☆"
                            color: win.favoriteOf(win.detailPath) ? "#ffd54a" : Theme.dim
                            font.pixelSize: Theme.px(18) * Theme.fontScale
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.toggleFavorite(win.detailPath) }
                        }
                        Text {
                            text: win.favoriteOf(win.detailPath) ? Tr.t("Favorite") : Tr.t("Not favorite")
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px(11) * Theme.fontScale
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    TextField {
                        id: tagsField
                        Layout.fillWidth: true
                        placeholderText: Tr.t("Tags (comma separated)")
                        text: win.tagsOf(win.detailPath)
                        onAccepted: win.setTags(win.detailPath, text)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(4)
                        IconButton { size: Theme.px(24); icon: "edit-copy"; tip: Tr.t("Copy path (C)"); onClicked: win.copyPath(win.detailPath) }
                        IconButton { size: Theme.px(24); icon: "folder-open"; tip: Tr.t("Reveal in Files (R)"); onClicked: win.reveal(win.detailPath) }
                        IconButton { size: Theme.px(24); icon: "system-run"; tip: Tr.t("Open with… (O)"); onClicked: win.openWith(win.detailPath) }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            }  // RowLayout
        }      // main ColumnLayout

        // ---- full-screen slideshow over the whole filtered library --------------
        // Viewer's own slideshow walks one folder; this one walks exactly what the
        // grid shows, so a search, a rating floor or an album carries through.
        Rectangle {
            id: slideOverlay
            anchors.fill: parent
            z: 10
            visible: win.slideshow
            color: "#000000"
            focus: true
            onVisibleChanged: if (visible) forceActiveFocus()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { win.stopSlideshow(); event.accepted = true; }
                else if (event.key === Qt.Key_Left) { win.slidePrev(); event.accepted = true; }
                else if (event.key === Qt.Key_Right) { win.slideNext(); event.accepted = true; }
                else if (event.key === Qt.Key_Space) { win.slidePaused = !win.slidePaused; event.accepted = true; }
                else if (event.key === Qt.Key_F) { win.toggleFavorite(win.slidePath); event.accepted = true; }
                else if (event.key === Qt.Key_Delete) {
                    const doomed = win.slidePath;
                    Viewer.open(doomed);
                    Viewer.trash();
                    win.photos = win.photos.filter(p => p.path !== doomed);
                    win.scan();
                    win.slideNext();
                    event.accepted = true;
                }
            }
            Image {
                anchors.fill: parent
                anchors.bottomMargin: Theme.px(64)
                source: win.slidePath !== "" ? "file://" + win.slidePath.split("/").map(encodeURIComponent).join("/") : ""
                fillMode: Image.PreserveAspectFit
                cache: true
                asynchronous: true
                sourceSize: Qt.size(1600, 1600)
            }
            MouseArea { anchors.fill: parent; onClicked: win.slideNext() }
            Text {
                anchors { top: parent.top; left: parent.left; margins: Theme.px(16) }
                text: (win.slideIndex + 1) + " / " + win.shown.length + "  ·  " + Tr.t("←/→ navigate") + "  ·  " + Tr.t("Space pause") + "  ·  " + Tr.t("Esc close")
                color: "#cccccc"
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
            }
            Text {
                anchors { bottom: parent.bottom; right: parent.right; margins: Theme.px(16) }
                text: win.slidePath.split("/").pop()
                color: "#cccccc"
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
                elide: Text.ElideMiddle
            }
            RowLayout {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.px(12) }
                spacing: Theme.px(8)
                IconButton { size: Theme.px(30); icon: "go-previous"; tip: Tr.t("Previous (←)"); onClicked: win.slidePrev() }
                IconButton {
                    size: Theme.px(30)
                    icon: win.slidePaused ? "media-playback-start" : "media-playback-pause"
                    tip: win.slidePaused ? Tr.t("Resume (Space)") : Tr.t("Pause (Space)")
                    onClicked: win.slidePaused = !win.slidePaused
                }
                IconButton { size: Theme.px(30); icon: "go-next"; tip: Tr.t("Next (→)"); onClicked: win.slideNext() }
                Button { text: Tr.t("Close (Esc)"); flat: true; onClicked: win.stopSlideshow() }
            }
        }
    }          // Item
}              // AppWindow
