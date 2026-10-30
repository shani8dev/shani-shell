pragma Singleton
// Color — pick a colour from the screen, convert between HEX/RGB/HSL,
// and score it against WCAG contrast.
//
// Logic ported from voltkit's color module (src/modules/color.rs):
//   parse #rgb / #rrggbb / rgb(r,g,b)
//   toHex / toRgbString / toHslString
//   luminance, contrastRatio, wcagRating
// Recent picks live in Settings.data.recentColors: capped at 32,
// deduplicated, newest first (the same shape as voltkit's color history).
//
// Picking: `niri msg pick-color` waits for a pixel click, then prints a line
// like "Hex: #3584e4". The result is emitted through `picked` and stored in
// `lastPicked`, copied to the clipboard, and added to the recents list.
//
// Exposed to QML as `qs.Services.Color` — used by the Sidebar's "Color picker"
// tile (SidebarTiles.qml).
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common

Singleton {
    id: root

    /// Emitted when a pick finishes: {hex, rgb, hsl, luminance, wcagLight,
    /// wcagDark}, or null when nothing was picked.
    signal picked(var color)
    property var lastPicked: null
    readonly property var recentColors: Settings.data.recentColors

    Component.onCompleted: {
        if (Settings.data.recentColors === undefined)
            Settings.data.recentColors = [];
    }

    // ---------- parse + convert (voltkit color.rs) ----------
    function parse(input) {
        if (typeof input !== "string")
            return null;
        var s = input.trim().toLowerCase();
        if (s.startsWith("rgb(") && s.endsWith(")")) {
            var inner = s.slice(4, -1);
            var parts = inner.split(",").map(function(p) { return parseInt(p.trim(), 10); });
            if (parts.length === 3 &&
                parts.every(function(v) { return !isNaN(v) && v >= 0 && v <= 255; }))
                return {r: parts[0], g: parts[1], b: parts[2]};
            return null;
        }
        var hex = s.replace(/^#/, "");
        if (hex.length === 3)
            hex = hex.split("").map(function(ch) { return ch + ch; }).join("");
        if (hex.length !== 6)
            return null;
        var v = parseInt(hex, 16);
        if (isNaN(v))
            return null;
        return {r: (v >> 16) & 0xff, g: (v >> 8) & 0xff, b: v & 0xff};
    }
    function pad2(n) {
        var s = n.toString(16);
        return s.length === 1 ? "0" + s : s;
    }
    function toHex(c) {
        return ("#" + pad2(c.r) + pad2(c.g) + pad2(c.b)).toUpperCase();
    }
    function toRgbString(c) {
        return "rgb(" + c.r + ", " + c.g + ", " + c.b + ")";
    }
    function toHsl(c) {
        var r = c.r / 255, g = c.g / 255, b = c.b / 255;
        var max = Math.max(r, g, b), min = Math.min(r, g, b);
        var l = (max + min) / 2;
        var h = 0, s = 0;
        if (max !== min) {
            var d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max === r)
                h = (g - b) / d + (g < b ? 6 : 0);
            else if (max === g)
                h = (b - r) / d + 2;
            else
                h = (r - g) / d + 4;
            h /= 6;
        }
        return {h: h * 360, s: s * 100, l: l * 100};
    }
    function toHslString(c) {
        var hs = toHsl(c);
        return "hsl(" + Math.round(hs.h) + ", " + Math.round(hs.s) + "%, " +
               Math.round(hs.l) + "%)";
    }
    function lin(channel) {
        channel = channel / 255;
        return channel <= 0.04045 ? channel / 12.92 :
               Math.pow((channel + 0.055) / 1.055, 2.4);
    }
    function luminance(c) {
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }
    function contrastRatio(a, b) {
        var la = luminance(a), lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    function wcagRating(ratio) {
        if (ratio >= 7.0) return "AAA";
        if (ratio >= 4.5) return "AA";
        if (ratio >= 3.0) return "AA Large";
        return "Fail";
    }

    // ---------- recent colours ----------
    function addRecent(hex) {
        var list = Array.from(Settings.data.recentColors || []);
        list = list.filter(function(h) { return h !== hex; });
        list.unshift(hex);
        if (list.length > 32)
            list.length = 32;
        Settings.data.recentColors = list;
    }
    function clearRecent() {
        Settings.data.recentColors = [];
    }

    // ---------- pick a colour from the screen ----------
    Process {
        id: pickProc
        command: ["sh", "-c", "niri msg pick-color 2>/dev/null || true"]
        stdout: StdioCollector {
            id: pickStdout
            onStreamFinished: root._pickText = text
        }
        onExited: root._onPickExited
    }
    property string _pickText: ""
    function _onPickExited(code) {
        root.lastPicked = null;
        if (code !== 0) {
            root.picked(null);
            return;
        }
        var c = root.parse(root._pickText);
        if (!c) {
            // fall back to any #rrggbb token in the output
            var m = root._pickText.match(/#[0-9a-fA-F]{6}/);
            c = m ? root.parse(m[0]) : null;
        }
        if (!c) {
            root.picked(null);
            return;
        }
        var color = {
            hex: root.toHex(c),
            rgb: root.toRgbString(c),
            hsl: root.toHslString(c),
            luminance: root.luminance(c),
            wcagLight: root.wcagRating(root.contrastRatio(c, {r: 255, g: 255, b: 255})),
            wcagDark: root.wcagRating(root.contrastRatio(c, {r: 0, g: 0, b: 0})),
        };
        root.addRecent(color.hex);
        root.lastPicked = color;
        root.picked(color);
    }
    function pick() {
        // don't restart a pick that is still waiting for a click
        if (pickProc.status === Process.Running)
            return;
        root._pickText = "";
        pickProc.start();
    }
}
