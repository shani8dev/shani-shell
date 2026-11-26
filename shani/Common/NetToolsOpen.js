.pragma library
// Hand a host to Network Tools. The clipboard marker is the hand-off flag;
// the Ui singleton owns the window state. Nothing here chooses a host.
function open(host, shell, ui) {
    const h = String(host || "").trim();
    if (!h) return false;
    shell.clipboardText = "shani-nettools:" + h;
    ui.closeAll();
    ui.netTools = true;
    return true;
}
