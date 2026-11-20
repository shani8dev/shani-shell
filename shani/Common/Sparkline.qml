// A small history line: give it an array of 0..1 numbers. Uses Canvas, so it
// draws only when the values change (no animation, no idle frames).
import QtQuick
import qs.Common

Canvas {
    id: line
    property var values: []
    property color color: Theme.accent
    property real maximum: 1
    implicitHeight: Theme.px(30)

    onValuesChanged: requestPaint()
    onColorChanged: requestPaint()
    Connections { target: Theme; function onAccentChanged() { line.requestPaint(); } }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height, n = values.length;
        if (w <= 0 || h <= 0 || n === 0)
            return;
        const ceil = Math.max(maximum, ...values);
        const y = v => h - 2 - (h - 4) * Math.min(1, Math.max(0, v / ceil));
        const x = i => (w - 2) * (n === 1 ? 0 : i / (n - 1)) + 1;

        ctx.beginPath();
        ctx.moveTo(x(0), y(values[0]));
        for (let i = 1; i < n; i++)
            ctx.lineTo(x(i), y(values[i]));
        ctx.strokeStyle = color;
        ctx.lineWidth = Math.max(1, Theme.px(1.5));
        ctx.lineJoin = "round";
        ctx.stroke();

        ctx.lineTo(x(n - 1), h);
        ctx.lineTo(x(0), h);
        ctx.closePath();
        ctx.fillStyle = Theme.alpha(color, 0.16);
        ctx.fill();
    }
}
