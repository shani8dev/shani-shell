// A touchscreen's or a pen's calibration: libinput's matrix [a, b, c, d, e, f],
// which takes where the device says it was touched (x, y, as fractions of the
// screen, with no calibration in force) to where it should land:
//     x' = a·x + b·y + c,   y' = d·x + e·y + f
// solved by least squares from the targets touched (four, any three not in a
// line). Pure functions: Services/Calibrate runs them, the suite checks them.
.pragma library

// points: [{ seen: [x, y], target: [x, y] }] in fractions of the screen
function solve(points) {
    if (!points || points.length < 3)
        return null;
    // normal equations of [x y 1] · [a b c]ᵀ = x' (and the same for y')
    const A = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], bx = [0, 0, 0], by = [0, 0, 0];
    for (const p of points) {
        const r = [p.seen[0], p.seen[1], 1];
        for (let i = 0; i < 3; i++) {
            for (let j = 0; j < 3; j++)
                A[i][j] += r[i] * r[j];
            bx[i] += r[i] * p.target[0];
            by[i] += r[i] * p.target[1];
        }
    }
    const row1 = solve3(A, bx), row2 = solve3(A, by);
    if (!row1 || !row2)
        return null;
    return row1.concat(row2).map(v => Math.round(v * 1e6) / 1e6);
}

// Gaussian elimination with partial pivoting; null when the targets were in a line
function solve3(A, b) {
    const m = A.map((r, i) => r.concat([b[i]]));
    for (let c = 0; c < 3; c++) {
        let p = c;
        for (let r = c + 1; r < 3; r++)
            if (Math.abs(m[r][c]) > Math.abs(m[p][c])) p = r;
        if (Math.abs(m[p][c]) < 1e-9)
            return null;
        const t = m[c]; m[c] = m[p]; m[p] = t;
        for (let r = 0; r < 3; r++) {
            if (r === c) continue;
            const f = m[r][c] / m[c][c];
            for (let k = c; k < 4; k++)
                m[r][k] -= f * m[c][k];
        }
    }
    return [m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]];
}

// the four targets, in fractions of the screen: near the corners, not at them
var targets = [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]];
