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
    implicitWidth: Theme.px(620)
    implicitHeight: Theme.px(600)

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
    // killing the worker fires its onExited, which marks the current job "Stopped"
    function stop() { if (running >= 0) worker.running = false; }
    function startNext() {
        const i = jobs.findIndex(j => j.state === "ready" && j.format !== "");
        if (i < 0) { running = -1; return; }
        running = i;
        set(i, { state: "working", progress: 0 });
        const flags = [];
        const add = (name, field) => { const v = field.text.trim(); if (v) flags.push("--" + name, v); };
        add("start", fromField); add("end", toField); add("volume", volField);
        add("title", titleField); add("artist", artistField); add("fade", fadeField);
        add("speed", speedField);
        worker.command = ["python3", win.tool, "run", jobs[i].path, jobs[i].format, win.quality].concat(flags);
        worker.running = true;
    }
    Process {
        id: worker
        stdout: SplitParser {
            onRead: line => {
                let e = null;
                try { e = JSON.parse(line); } catch (err) { return; }
                // a worker that outlives its job (cancel, retry) must not write into jobs[-1]
                if (win.running < 0) return;
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
            spacing: Theme.px(10)

            RowLayout {
                Layout.fillWidth: true
                Button { kind: win.jobs.length ? "plain" : "primary"; text: Tr.t("Add files…"); onClicked: win.pick() }
                Item { Layout.fillWidth: true }
                Text { text: Tr.t("Quality"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                Repeater {
                    model: [["small", Tr.t("Small")], ["balanced", Tr.t("Balanced")], ["best", Tr.t("Best")]]
                    Choice { required property var modelData; text: modelData[1]; selected: win.quality === modelData[0]; onClicked: win.quality = modelData[0] }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.jobs.length > 0
                spacing: Theme.px(6)
                Text { text: Tr.t("From"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: fromField; Layout.preferredWidth: Theme.px(64); placeholderText: "0"; Accessible.name: Tr.t("Start, in seconds") }
                Text { text: Tr.t("To"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: toField; Layout.preferredWidth: Theme.px(64); placeholderText: Tr.t("end"); Accessible.name: Tr.t("End, in seconds") }
                Text { text: Tr.t("Volume"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: volField; Layout.preferredWidth: Theme.px(56); placeholderText: "100"; Accessible.name: Tr.t("Volume, percent") }
                Text { text: Tr.t("Title"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: titleField; Layout.fillWidth: true; placeholderText: Tr.t("What the file says about itself"); Accessible.name: Tr.t("Title") }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: win.jobs.length > 0
                spacing: Theme.px(6)
                Text { text: Tr.t("Artist"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: artistField; Layout.preferredWidth: Theme.px(110); placeholderText: Tr.t("Performer"); Accessible.name: Tr.t("Artist") }
                Text { text: Tr.t("Fade"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: fadeField; Layout.preferredWidth: Theme.px(70); placeholderText: "0:0"; Accessible.name: Tr.t("Fade in and out, seconds") }
                Text { text: Tr.t("Speed"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale }
                TextField { id: speedField; Layout.preferredWidth: Theme.px(60); placeholderText: "1.0"; Accessible.name: Tr.t("Playback speed") }
            }

            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(6)
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
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.px(10) }
                        spacing: Theme.px(6)
                        RowLayout {
                            Layout.fillWidth: true
                            Icon { name: row.modelData.kind === "video" ? "video-x-generic" : row.modelData.kind === "audio" ? "audio-x-generic" : "image-x-generic"; size: Theme.px(18); color: Theme.dim }
                            Text { Layout.fillWidth: true; text: row.modelData.path.split("/").pop(); color: Theme.text; elide: Text.ElideMiddle; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale }
                            IconButton { size: Theme.px(26); visible: row.modelData.state !== "working"; icon: "window-close"; tip: Tr.t("Remove from the list"); onClicked: { if (row.index < win.running) win.running--; const l = win.jobs.slice(); l.splice(row.index, 1); win.jobs = l; } }
                            Button { flat: true; visible: row.modelData.state === "working"; text: Tr.t("Cancel"); onClicked: win.stop() }
                        }
                        // into what: a pick of what makes sense for this file
                        Flow {
                            Layout.fillWidth: true
                            visible: row.modelData.state === "ready"
                            spacing: Theme.px(4)
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
                            Layout.preferredHeight: Theme.px(5)
                            visible: row.modelData.state === "working"
                            radius: Theme.px(3)
                            color: Theme.surface3
                            Rectangle { width: parent.width * row.modelData.progress; height: parent.height; radius: Theme.px(3); color: Theme.accent }
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
                                font.pixelSize: Theme.px(12) * Theme.fontScale
                            }
                            Button {
                                visible: row.modelData.state === "failed"
                                flat: true
                                text: Tr.t("Retry")
                                onClicked: win.set(row.index, { state: "ready", progress: 0, error: "", out: "" })
                            }
                            Button { visible: row.modelData.state === "done"; flat: true; text: Tr.t("Open"); onClicked: Quickshell.execDetached(["gio", "open", row.modelData.out]) }
                            Button { visible: row.modelData.state === "done"; flat: true; text: Tr.t("Show in Files"); onClicked: Files.show(row.modelData.out.replace(/\/[^/]*$/, "")) }
                        }
                    }
                }
                DropZone {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(40), Theme.px(420))
                    visible: list.count === 0
                    iconName: "document-save-as"
                    title: Tr.t("Nothing to convert yet")
                    text: Tr.t("Add or drop videos, songs or pictures")
                    onFileDropped: url => win.add([decodeURIComponent(String(url).replace(/^file:\/\//, ""))])
                    Button { flat: true; text: Tr.t("Add files…"); onClicked: win.pick() }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("New files go beside the originals; nothing is written over.")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.px(11) * Theme.fontScale
                }
                Button {
                    kind: "primary"
                    text: win.running >= 0 ? Tr.t("Converting…") : Tr.t("Convert")
                    busy: win.running >= 0
                    enabled: win.running < 0 && win.jobs.some(j => j.state === "ready" && j.format !== "")
                    onClicked: win.convertAll()
                }
            }
        }
    }
}
