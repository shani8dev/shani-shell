.pragma library
// Handwriting reads with Tesseract: the screen keyboard's language (a hand-made one,
// a short id, or an xkb layout id like "in+tam") -> the Tesseract data the image
// ships (eng deu fra spa, and hin mar tam tel ben guj kan mal pan ori urd san).
// Anything else reads as English. Plain JS: tests/test_write_lang.py runs it.

var SHORT = { en: "eng", de: "deu", fr: "fra", es: "spa", hi: "hin", mr: "mar", ta: "tam", te: "tel", bn: "ben",
              gu: "guj", kn: "kan", ml: "mal", pa: "pan", or: "ori", ur: "urd", sa: "san" };
// xkb's variants of India's layouts, by how their names begin (in+ben_probhat, in+tamilnet …)
var VARIANTS = [["marathi", "mar"], ["mar", "mar"], ["hin", "hin"], ["bolnagri", "hin"], ["tamilnet", "tam"],
                ["tam", "tam"], ["tel", "tel"], ["ben", "ben"], ["guj", "guj"], ["kan", "kan"], ["mal", "mal"],
                ["guru", "pan"], ["jhelum", "pan"], ["ori", "ori"], ["urd", "urd"], ["san", "san"]];

function tesseractLang(id) {
    id = String(id || "");
    if (SHORT[id])
        return SHORT[id];
    const parts = id.split("+"), layout = parts[0], variant = parts[1] || "";
    if (layout === "bd")
        return "ben";
    if (layout === "pk")
        return variant === "" || variant.indexOf("urd") === 0 || variant === "pak_urdu_phonetic" ? "urd" : "eng";
    if (layout === "in" && variant === "")
        return "hin";                     // xkb's plain "Indian" is Hindi's Devanagari InScript
    if (layout === "in" || layout === "lk")
        for (const v of VARIANTS)
            if (variant.indexOf(v[0]) === 0)
                return v[1];
    return "eng";
}
