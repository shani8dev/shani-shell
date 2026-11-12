.pragma library

// Contrast (WCAG 2.1): the relative luminance of a colour, the contrast ratio
// between two, and the ink that reads on a background.
//
// The shell has one palette and every surface must read on it, so the
// question "which ink goes on this colour" is asked in one place: the
// accent's own text, the chips, the notifications. `readableOn` answers it
// by measurement, not by eye - a colour can be light and still be a poor
// background for black.
//
// A colour is {r, g, b, a} with 0..1 channels (what Qt.color gives).

function relativeLuminance(c) {
    if (!c || c.r === undefined)
        return 0;
    const linear = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
}

// the ratio between two colours: 1 is the same colour, 21 is black on white
function ratio(a, b) {
    const la = relativeLuminance(a);
    const lb = relativeLuminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function mix(c1, c2, amount) {
    return Qt.rgba(c1.r * (1 - amount) + c2.r * amount, c1.g * (1 - amount) + c2.g * amount, c1.b * (1 - amount) + c2.b * amount, c1.a * (1 - amount) + c2.a * amount);
}

// does this ink read on that background?
function isTonal(container, onSurface, target = 4.5) {
    return ratio(container, onSurface) >= target;
}

// the first candidate that reads on the background, or the best of them
function readableOn(background, candidates, target = 4.5) {
    let best = candidates[0];
    for (const candidate of candidates) {
        const current = ratio(candidate, background);
        if (current >= target)
            return candidate;
        if (current > ratio(best, background))
            best = candidate;
    }
    return best;
}

function worstRatio(color, backgrounds) {
    return Math.min(...backgrounds.map(background => ratio(color, background)));
}

// the candidate that reads on every one of the backgrounds (a chip that sits
// on both the card and the page)
function readableOnAll(backgrounds, candidates, target = 4.5) {
    let best = candidates[0];
    let bestRatio = -1;
    for (const candidate of candidates) {
        const worst = worstRatio(candidate, backgrounds);
        if (worst >= target)
            return candidate;
        if (worst <= bestRatio)
            continue;
        best = candidate;
        bestRatio = worst;
    }
    return best;
}

// the tint, as far as it may go before the text on it stops reading
function subtleTint(base, tint, onColor, amount, target = 4.5) {
    if (ratio(base, onColor) < target)
        return base;
    if (ratio(mix(base, tint, amount), onColor) >= target)
        return mix(base, tint, amount);
    let low = 0;
    let high = amount;
    for (let i = 0; i < 6; i++) {
        const mid = (low + high) / 2;
        if (ratio(mix(base, tint, mid), onColor) >= target)
            low = mid;
        else
            high = mid;
    }
    return mix(base, tint, low);
}

function tintedContainer(base, tint, onColor, target = 4.5) {
    let low = 0.12;
    let high = 0.36;
    if (ratio(mix(base, tint, high), onColor) >= target)
        return mix(base, tint, high);
    for (let i = 0; i < 6; i++) {
        const mid = (low + high) / 2;
        if (ratio(mix(base, tint, mid), onColor) >= target)
            low = mid;
        else
            high = mid;
    }
    return mix(base, tint, low);
}
