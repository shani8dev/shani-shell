// The launcher's calculator and unit converter (from Launcher.qml): plain
// functions of the query, nothing of the window.
.pragma library

// 5! and (…)! as factorial calls, including nested parentheses.
function rewriteFact(s) {
    const out = [];
    let i = 0;
    while (i < s.length) {
        const ch = s.charAt(i);
        if (ch === "(") {
            let depth = 0, j = i;
            for (; j < s.length; j++) {
                if (s.charAt(j) === "(") depth++;
                else if (s.charAt(j) === ")") { depth--; if (depth === 0) break; }
            }
            if (j < s.length && depth === 0 && s.charAt(j + 1) === "!") {
                out.push("fact(" + s.slice(i + 1, j) + ")");
                i = j + 2;
                continue;
            }
        }
        const m = s.slice(i).match(/^(\d+(?:\.\d*)?)!/);
        if (m) { out.push("fact(" + m[1] + ")"); i += m[0].length; continue; }
        out.push(ch);
        i++;
    }
    return out.join("");
}
function calc(expr) {
    let src = expr.replace(/\s+/g, "").replace(/\^/g, "**").replace(/×/g, "*").replace(/÷/g, "/")
        .replace(/−/g, "-").replace(/√/g, "sqrt").replace(/π/g, "pi");
    src = src.replace(/\|([^|]+)\|/g, "abs($1)");            // |x| → abs(x)
    src = rewriteFact(src);                                 // 5! / (3+2)! → fact(…)
    if (!/^[0-9+\-*/%.()a-z,]+$/i.test(src) || !/[0-9]/.test(src) || /^[0-9.]+$/.test(src))
        return null;
    const names = src.match(/[a-z]+/gi) || [];
    const allowed = ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "exp", "abs", "round", "floor", "ceil", "pow", "min", "max", "fact", "npr", "ncr", "pi", "e"];
    if (names.some(n => allowed.indexOf(n.toLowerCase()) < 0))
        return null;
    // names are case-insensitive, JS is not (nPr → npr, PI → Math.PI)
    const js = src.replace(/\bln\(/gi, "log(").replace(/\bpi\b/gi, "PI").replace(/\be\b/g, "E")
        .replace(/\b(sqrt|sin|cos|tan|asin|acos|atan|log|exp|abs|round|floor|ceil|pow|min|max)\b/gi, m => "Math." + m.toLowerCase())
        .replace(/\bPI\b/g, "Math.PI").replace(/\bE\b/g, "Math.E")
        .replace(/\bnpr\b/gi, "npr").replace(/\bncr\b/gi, "ncr").replace(/\bfact\b/gi, "fact");
    try {
        const fact = function (n) {
            n = Math.floor(n);
            if (n < 0 || n > 170) throw new Error("fact");
            let r = 1; for (let i = 2; i <= n; i++) r *= i; return r;
        };
        const npr = function (n, k) { return fact(n) / fact(n - k); };
        const ncr = function (n, k) { return fact(n) / (fact(k) * fact(n - k)); };
        const v = Function("fact", "npr", "ncr", '"use strict"; return (' + js + ");")(fact, npr, ncr);
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
