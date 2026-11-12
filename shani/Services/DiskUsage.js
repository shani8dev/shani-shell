.pragma library
// DiskUsage treemap layout as plain JS, so tests/test_signed_disktree.py runs
// it in node (the way tests/test_charger.py runs Charger.js). The shell
// panel (Modules/DiskUsage/DiskUsagePanel.qml) draws what this returns.
//
// Area ~ size, weighted: every rectangle's area is exactly
//
//     width * height == W * H * size / total
//
// so a file twice as big gets twice the area, never a fixed grid cell.
// Rows are horizontal strips: a row's height is its share of the total,
// each item's width its share of its row. Ordered biggest-first, so the
// largest blocks land at the top — DiskUsage parity: larger blocks huge.

function treemap(entries, W, H) {
    if (!entries || entries.length === 0 || W <= 0 || H <= 0)
        return [];
    var items = entries.slice().sort(function (a, b) { return (b.size || 0) - (a.size || 0); });
    var total = 0;
    for (var i = 0; i < items.length; i++)
        total += Math.max(1, items[i].size || 0);
    if (total <= 0)
        return [];
    // how many horizontal strips: roughly square cells for the count and
    // the container's aspect (sqrt of count * aspect, at least one row)
    var numRows = Math.max(1, Math.round(Math.sqrt(items.length * (W / H))));
    if (numRows > items.length)
        numRows = items.length;
    var rowBudget = total / numRows;
    var rows = [];
    var cur = [];
    var curTotal = 0;
    for (var j = 0; j < items.length; j++) {
        cur.push(items[j]);
        curTotal += Math.max(1, items[j].size || 0);
        if (curTotal >= rowBudget && rows.length < numRows - 1) {
            rows.push(cur);
            cur = [];
            curTotal = 0;
        }
    }
    if (cur.length > 0)
        rows.push(cur);
    var rects = [];
    var y = 0;
    for (var r = 0; r < rows.length; r++) {
        var row = rows[r];
        var rowTotal = 0;
        for (var k = 0; k < row.length; k++)
            rowTotal += Math.max(1, row[k].size || 0);
        var rowH = H * rowTotal / total;
        var x = 0;
        for (var m = 0; m < row.length; m++) {
            var e = row[m];
            var w = W * Math.max(1, e.size || 0) / rowTotal;
            rects.push({ path: e.path || "", name: e.name || "", size: e.size || 0,
                         isDir: !!e.isDir, x: x, y: y, w: w, h: rowH });
            x += w;
        }
        y += rowH;
    }
    return rects;
}
