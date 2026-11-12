// Converter: videos, songs and pictures into another format - a video to MP4
// for a phone, its sound to MP3, a photo to WebP or PDF. bridge/convert.py
// does it with ffmpeg and ImageMagick. The new file goes beside the old one;
// nothing is written over, and the original stays as it was.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Converter"
    visible: Ui.converter
    onGone: Ui.converter = false
    implicitWidth: 620
    implicitHeight: 600

    readonly property string tool: Quickshell.env("SHANI_CONVERT_TOOL") || "/usr/lib/shani-shell/convert.py"
    // [{ path, kind, formats, format, state: "ready"|"working"|"done"|"failed", progress, out, error }]
    property var jobs: []
    property string quality: "balanced"
    property int running: -1

    readonly property var labels: ({ mp4: Tr.t("MP4 · plays everywhere"), webm: "WebM", mkv: "MKV", gif: Tr.t("GIF · moving picture"),
        mp3: Tr.t("MP3 · sound only"), m4a: "M4A", ogg: "OGG", opus: "Opus", flac: Tr.t("FLAC · lossless"), wav: "WAV",
        jpg: "JPEG", png: "PNG", webp: "WebP", avif: "AVIF", pdf: "PDF" })

    function add(paths) {
        for (const p of paths) {
            if (jobs.some(j => j.path === p))
                continue;
            jobs = jobs.concat([{ path: p, kind: "", formats: [], format: "", state: "ready", progress: 0, out: "", error: "" }]);
            probe.queue.push(p);
        }
        probe.next();
    }
    // the files handed over (the Media Player's Convert…, Files), taken once
    function take() { if (Ui.converterFiles.length) { add(Ui.converterFiles); Ui.converterFiles = []; } }
    Connections { target: Ui; function onConverterFilesChanged() { win.take(); } }
    Component.onCompleted: take()

    function set(i, patch) { const l = jobs.slice(); l[i] = Object.assign({}, l[i], patch); jobs = l; }
    Process {
        id: probe
        property var queue: []
        property string current: ""
        function next() {
            if (running || queue.length === 0) return;
            current = queue.shift();
            command = ["python3", win.tool, "formats", current];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const i = win.jobs.findIndex(j => j.path === probe.current);
                let r = { kind: "", formats: [] };
                try { r = JSON.parse(text); } catch (e) {}
                if (i >= 0) win.set(i, r.kind ? { kind: r.kind, formats: r.formats, format: r.formats[0] }
                                               : { state: "failed", error: Tr.t("Not a video, a song or a picture") });
            }
        }
        onExited: next()
    }
    function convertAll() { if (running < 0) startNext(); }
    function startNext() {
        const i = jobs.findIndex(j => j.state === "ready" && j.format !== "");
        if (i < 0) { running = -1; return; }
        running = i;
        set(i, { state: "working", progress: 0 });
        worker.command = ["python3", win.tool, "run", jobs[i].path, jobs[i].format, win.quality];
        worker.running = true;
    }
    Process {
        id: worker
        stdout: SplitParser {
            onRead: line => {
                let e = null;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.progress !== undefined) win.set(win.running, { progress: e.progress });
                else if (e.done) win.set(win.running, { state: "done", out: e.done, progress: 1 });
                else if (e.error) win.set(win.running, { state: "failed", error: e.error });
            }
        }
        onExited: code => {
            if (win.running >= 0 && win.jobs[win.running] && win.jobs[win.running].state === "working")
                win.set(win.running, { state: "failed", error: Tr.t("Stopped") });
            win.startNext();
        }
    }
    function pick() {
        FilePicker.open({ mode: "open", multiple: true, title: Tr.t("Files to convert"),
                          onPicked: paths => win.add(paths) });
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.converter = false
        DropArea {
            anchors.fill: parent
            onDropped: drop => { if (drop.hasUrls) win.add(drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, "")))); }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Button { kind: win.jobs.length ? "plain" : "primary"; text: Tr.t("Add files…"); onClicked: win.pick() }
                Item { Layout.fillWidth: true }
                Text { text: Tr.t("Quality"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                Repeater {
                    model: [["small", Tr.t("Small")], ["balanced", Tr.t("Balanced")], ["best", Tr.t("Best")]]
                    Choice { required property var modelData; text: modelData[1]; selected: win.quality === modelData[0]; onClicked: win.quality = modelData[0] }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: win.jobs
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: col.implicitHeight + 20
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    ColumnLayout {
                        id: col
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Icon { name: row.modelData.kind === "video" ? "video-x-generic" : row.modelData.kind === "audio" ? "audio-x-generic" : "image-x-generic"; size: 18; color: Theme.dim }
                            Text { Layout.fillWidth: true; text: row.modelData.path.split("/").pop(); color: Theme.text; elide: Text.ElideMiddle; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
                            IconButton { size: 26; visible: row.modelData.state !== "working"; icon: "window-close"; tip: Tr.t("Remove from the list"); onClicked: { const l = win.jobs.slice(); l.splice(row.index, 1); win.jobs = l; } }
                        }
                        // into what: a pick of what makes sense for this file
                        Flow {
                            Layout.fillWidth: true
                            visible: row.modelData.state === "ready"
                            spacing: 4
                            Repeater {
                                model: row.modelData.formats
                                Choice {
                                    required property string modelData
                                    text: win.labels[modelData] || modelData.toUpperCase()
                                    selected: row.modelData.format === modelData
                                    onClicked: win.set(row.index, { format: modelData })
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            visible: row.modelData.state === "working"
                            radius: 3
                            color: Theme.surface3
                            Rectangle { width: parent.width * row.modelData.progress; height: parent.height; radius: 3; color: Theme.accent }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: row.modelData.state === "done" || row.modelData.state === "failed"
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.state === "done" ? Tr.t("Made: %1").arg(row.modelData.out.split("/").pop()) : row.modelData.error
                                color: row.modelData.state === "done" ? Theme.dim : Theme.danger
                                elide: Text.ElideMiddle
                                font.family: Theme.font
                                font.pixelSize: 12 * Theme.fontScale
                            }
                            Button { visible: row.modelData.state === "done"; flat: true; text: Tr.t("Open"); onClicked: Quickshell.execDetached(["gio", "open", row.modelData.out]) }
                            Button { visible: row.modelData.state === "done"; flat: true; text: Tr.t("Show in Files"); onClicked: Files.show(row.modelData.out.replace(/\/[^/]*$/, "")) }
                        }
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    icon: "document-save-as"
                    title: Tr.t("Nothing to convert yet")
                    subtitle: Tr.t("Add or drop videos, songs or pictures")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("New files go beside the originals; nothing is written over.")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                Button {
                    kind: "primary"
                    text: win.running >= 0 ? Tr.t("Converting…") : Tr.t("Convert")
                    enabled: win.running < 0 && win.jobs.some(j => j.state === "ready" && j.format !== "")
                    onClicked: win.convertAll()
                }
            }
        }
    }
}
