// A place files can be dropped on: a folder's tile or row, the folder on
// screen, a place in the sidebar, the other pane. What arrives is the drag's
// text/uri-list - from Files itself or from any other app (a browser's download,
// a mail's attachment). As Nautilus does, a drop moves within the same drive and
// copies from another; Ctrl makes it a copy (Qt hands that over as the drop's
// proposed action). The work is Files' copy job (progress, Stop, Undo).
import QtQuick
import qs.Services

DropArea {
    id: root
    property string dest: ""             // the folder a drop goes into
    readonly property bool hovering: containsDrag && dest !== ""
    keys: ["text/uri-list"]
    onEntered: drag => {
        if (dest === "" || !drag.hasUrls) { drag.accepted = false; return; }
        drag.accept(drag.proposedAction === Qt.CopyAction ? Qt.CopyAction : Qt.MoveAction);
    }
    onDropped: drop => {
        if (dest === "" || !drop.hasUrls) return;
        const copy = drop.proposedAction === Qt.CopyAction;
        const n = Files.dropUrls(dest, drop.urls, copy ? "copy" : "auto");
        if (n > 0) drop.accept(copy ? Qt.CopyAction : Qt.MoveAction);
    }
}
