# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=document-ps)
# ---- the Document Viewer reads PostScript (Papers parity): Ghostscript makes the PDF ----
P=/tmp/document-ps; rm -rf $P; mkdir -p $P
printf '%%!PS-Adobe-3.0\n/Helvetica findfont 24 scalefont setfont\n72 700 moveto (page one) show showpage\n72 700 moveto (page two) show showpage\n' > $P/two.ps
printf '%%!PS-Adobe-3.0 EPSF-3.0\n%%%%BoundingBox: 0 0 200 100\n/Helvetica findfont 20 scalefont setfont 10 40 moveto (eps) show\n' > $P/fig.eps
if command -v gs >/dev/null; then
    ipc openPdf "$P/two.ps"
    waitfor "not d['pdfLoading'] and d['pdfPages'] == 2" 15 && result document-postscript-opens PASS || result document-postscript-opens FAIL "$(q "['pdfPages'], d['pdfLoading']")"
    ipc openPdf "$P/fig.eps"
    waitfor "not d['pdfLoading'] and d['pdfPages'] == 1" 15 && result document-eps-opens PASS || result document-eps-opens FAIL "$(q "['pdfPages'], d['pdfLoading']")"
else
    result document-postscript-opens SKIP "no ghostscript in this image"
fi
rm -rf $P; ipc closeAll
