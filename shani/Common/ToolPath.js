.pragma library
// Single source of the bridge-tool install prefix. .pragma library JS cannot
// see QML globals like Quickshell, so callers pass the env value they read:
//   readonly property string tool: ToolPath.of(envOverride, "x.py")
// One edit here moves every tool; one env override at the call site keeps tests
// and alternate installs working.
var DEFAULT_DIR = "/usr/lib/shani-shell"

// envValue: the value of the service's SHANI_*_TOOL env override (or ""/null).
// fallback: the default file name under DEFAULT_DIR (e.g. "feeds.py").
function of(envValue, fallback) {
    return envValue || DEFAULT_DIR + "/" + fallback
}