.pragma library
// One mark on a markup layer (Viewer's image markup, PdfReader's page notes):
// pen, highlight, line, arrow, box, blur or text, drawn on a Canvas 2D context
// the way imgedit.py burns it in. Points are 0..1 fractions of the layer, so a
// mark keeps its place when the layer is resized. Pure, tested in node
// (tests/test_markup.py).
//
// The shape follows the MARK's kind, never the tool picked now: PdfReader's own
// copy once used the current tool, and every pen stroke on the page turned into
// a straight line as soon as the line tool was chosen.

/// Kinds drawn from their first to their last point only.
function isTwoPoint(kind) {
    return kind === "line" || kind === "arrow" || kind === "box" || kind === "blur";
}

/// The points a stroked kind passes through after its first, in pixels.
function strokePath(kind, P) {
    return kind === "line" || kind === "arrow" ? [P[P.length - 1]] : P.slice(1);
}

/// Draw one mark: `pts` are [x, y] fractions, `size` a fraction of the shorter side.
function draw(ctx, width, height, kind, color, size, pts, words) {
    if (!pts || !pts.length) return;
    const m = Math.min(width, height), w = Math.max(1, size * m);
    const P = pts.map(p => [p[0] * width, p[1] * height]);
    const a = P[0], b = P[P.length - 1];
    ctx.save();
    ctx.strokeStyle = color; ctx.fillStyle = color;
    ctx.lineWidth = w; ctx.lineCap = "round"; ctx.lineJoin = "round";
    if (kind === "blur") {
        ctx.fillStyle = "rgba(128, 128, 128, 0.75)";
        ctx.fillRect(Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]));
    } else if (kind === "box") {
        ctx.strokeRect(Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]));
    } else if (kind === "text") {
        ctx.font = Math.max(12, w * 5) + "px sans-serif";
        ctx.fillText(words || "", a[0], a[1]);
    } else {
        if (kind === "highlight") { ctx.globalAlpha = 0.4; ctx.lineWidth = w * 4; }
        ctx.beginPath();
        ctx.moveTo(a[0], a[1]);
        for (const p of strokePath(kind, P)) ctx.lineTo(p[0], p[1]);
        if (P.length === 1) ctx.lineTo(a[0] + 0.1, a[1]);   // a tap is a dot
        ctx.stroke();
        if (kind === "arrow") {
            const ang = Math.atan2(b[1] - a[1], b[0] - a[0]), L = Math.max(10, w * 5);
            ctx.beginPath(); ctx.moveTo(b[0], b[1]);
            ctx.lineTo(b[0] - L * Math.cos(ang - 0.45), b[1] - L * Math.sin(ang - 0.45));
            ctx.lineTo(b[0] - L * Math.cos(ang + 0.45), b[1] - L * Math.sin(ang + 0.45));
            ctx.closePath(); ctx.fill();
        }
    }
    ctx.restore();
}
