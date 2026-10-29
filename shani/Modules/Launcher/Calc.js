// The launcher's calculator and unit converter (from Launcher.qml): plain
// functions of the query, nothing of the window.
.pragma library

function calc(expr) {
    const src = expr.replace(/\s+/g, "").replace(/\^/g, "**").replace(/×/g, "*").replace(/÷/g, "/");
    if (!/^[0-9+\-*/%.()a-z,]+$/i.test(src) || !/[0-9]/.test(src) || /^[0-9.]+$/.test(src))
        return null;
    const names = src.match(/[a-z]+/gi) || [];
    const allowed = ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "exp", "abs", "round", "floor", "ceil", "pow", "min", "max", "pi", "e"];
    if (names.some(n => allowed.indexOf(n.toLowerCase()) < 0))
        return null;
    const js = src.replace(/\bln\(/gi, "log(").replace(/\bpi\b/gi, "PI").replace(/\be\b/g, "E")
        .replace(/\b(sqrt|sin|cos|tan|asin|acos|atan|log|exp|abs|round|floor|ceil|pow|min|max|PI|E)\b/g, "Math.$1");
    try {
        const v = Function('"use strict"; return (' + js + ");")();
        return typeof v === "number" && isFinite(v) ? Number(v.toPrecision(12)) : null;
    } catch (e) {
        return null;
    }
}
// units: name -> [dimension, factor to the base unit]; temperatures are special
var units = ({
    mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], inch: ["len", 0.0254],
    ft: ["len", 0.3048], feet: ["len", 0.3048], foot: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344], miles: ["len", 1609.344],
    mg: ["mass", 1e-6], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.0283495], lb: ["mass", 0.453592], lbs: ["mass", 0.453592],
    ml: ["vol", 0.001], l: ["vol", 1], litre: ["vol", 1], liter: ["vol", 1], gal: ["vol", 3.78541], cup: ["vol", 0.24], tsp: ["vol", 0.00492892], tbsp: ["vol", 0.0147868],
    b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12], kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
    ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], day: ["time", 86400], days: ["time", 86400], week: ["time", 604800], weeks: ["time", 604800],
    kmh: ["speed", 1 / 3.6], "km/h": ["speed", 1 / 3.6], mph: ["speed", 0.44704], "m/s": ["speed", 1], knot: ["speed", 0.514444], knots: ["speed", 0.514444],
    m2: ["area", 1], km2: ["area", 1e6], ha: ["area", 1e4], acre: ["area", 4046.86], acres: ["area", 4046.86], sqft: ["area", 0.092903],
    c: ["temp"], f: ["temp"], k: ["temp"]
})
function convert(q) {
    const m = q.trim().toLowerCase().match(/^(-?[\d.]+)\s*([a-z\/0-9°]+)\s+(?:in|to|as)\s+([a-z\/0-9°]+)$/);
    if (!m)
        return null;
    const v = parseFloat(m[1]), a = m[2].replace("°", ""), b = m[3].replace("°", "");
    const ua = units[a], ub = units[b];
    if (!ua || !ub || ua[0] !== ub[0] || isNaN(v))
        return null;
    let out;
    if (ua[0] === "temp") {
        const kel = a === "c" ? v + 273.15 : a === "f" ? (v - 32) * 5 / 9 + 273.15 : v;
        out = b === "c" ? kel - 273.15 : b === "f" ? (kel - 273.15) * 9 / 5 + 32 : kel;
    } else {
        out = v * ua[1] / ub[1];
    }
    return { text: Number(out.toPrecision(8)) + " " + m[3], value: out };
}
// three-letter codes followed by "in/to": currency, which needs live rates —
// Chronoa's convert_currency skill has them; the shell sends no query anywhere
function isCurrency(q) {
    return /^-?[\d.]+\s*[a-z]{3}\s+(in|to)\s+[a-z]{3}$/i.test(q.trim()) && convert(q) === null;
}
