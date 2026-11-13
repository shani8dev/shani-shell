# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=documents)
# ---- Document Viewer: e-books, comics and DjVu, through a PDF copy (PyMuPDF, ddjvu) ----
D=/tmp/doc-test; rm -rf $D; mkdir -p $D/pages
# an EPUB: the smallest a reader accepts (mimetype first, stored; container; package; one chapter)
python3 - "$D/book.epub" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
z.writestr("OEBPS/book.opf", '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>The Test Book</dc:title><dc:identifier id="id">t1</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>')
z.writestr("OEBPS/c1.xhtml", '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head><body><h1>Chapter One</h1><p>The lighthouse keeper counted the ships.</p></body></html>')
z.close()
PY
for i in 1 2 3; do magick -size 400x600 "xc:hsl($((i*90)),60%,50%)" -fill white -pointsize 60 -annotate +120+300 "Page $i" $D/pages/p$i.png 2>/dev/null; done
( cd $D/pages && bsdtar -acf $D/comic.cbz p1.png p2.png p3.png && bsdtar --format 7zip -cf $D/comic.cb7 p1.png p2.png p3.png )
magick $D/pages/p1.png $D/p1.ppm 2>/dev/null && c44 $D/p1.ppm $D/page.djvu 2>/dev/null

for spec in book.epub:1 comic.cbz:3 comic.cb7:3 page.djvu:1; do
    f=${spec%%:*}; want=${spec#*:}
    [ -s "$D/$f" ] || { result "documents-open-${f##*.}" FAIL "the test file was not made"; continue; }
    ipc openPdf "$D/$f"
    if waitfor "d['pdfPages'] == $want and d['pdfFile'].endswith('$f')" 20; then
        sleep 0.6; shot "documents-${f##*.}" 0.2; result "documents-open-${f##*.}" PASS "$want pages"
    else
        result "documents-open-${f##*.}" FAIL "pages $(q "['pdfPages']"), error '$(q "['pdfError']")'"
    fi
done
# the e-book's words are searchable, as a PDF's are (its PDF copy has the text)
ipc openPdf "$D/book.epub"; waitfor "d['pdfPages'] == 1" 15
ipc pdfSearch "lighthouse"
waitfor "d['pdfSearchMatches'] >= 1" 8 && result documents-epub-searchable PASS || result documents-epub-searchable FAIL "$(q "['pdfSearchMatches']")"

# a PDF form: fields found, filled in, a filled copy saved beside it (the original untouched)
python3 - "$D/form.pdf" <<'PY'
import sys, pymupdf as fitz
doc = fitz.open(); page = doc.new_page()
for name, kind, rect, extra in (("full_name", fitz.PDF_WIDGET_TYPE_TEXT, (72, 72, 300, 92), None),
                                ("agree", fitz.PDF_WIDGET_TYPE_CHECKBOX, (72, 110, 90, 128), None),
                                ("city", fitz.PDF_WIDGET_TYPE_COMBOBOX, (72, 140, 300, 160), ["Pune", "Mumbai"])):
    w = fitz.Widget(); w.field_name = name; w.field_type = kind; w.rect = fitz.Rect(*rect)
    if extra: w.choice_values = extra
    page.add_widget(w)
doc.save(sys.argv[1])
PY
ipc openPdf "$D/form.pdf"
waitfor "d['pdfFormFields'] == 3" 15 && result documents-form-fields-found PASS || result documents-form-fields-found FAIL "$(q "['pdfFormFields']")"
ipc pdfFormShow; ipc pdfFormSet full_name "Asha Rao"; ipc pdfFormSet agree true; ipc pdfFormSet city Pune
sleep 0.8; shot documents-form 0.2
ipc pdfFormSave
waitfor "d['pdfFormSaved'].endswith('form (filled).pdf')" 10 \
    && python3 /work/bridge/pdfform.py fields "$D/form (filled).pdf" 2>/dev/null | python3 -c "import json,sys; f={x['name']: x['value'] for x in json.load(sys.stdin)}; sys.exit(0 if f == {'full_name': 'Asha Rao', 'agree': True, 'city': 'Pune'} else 1)" \
    && python3 /work/bridge/pdfform.py fields "$D/form.pdf" 2>/dev/null | grep -q '"value": ""' \
    && result documents-form-filled-copy PASS || result documents-form-filled-copy FAIL "saved '$(q "['pdfFormSaved']")' error '$(q "['pdfFormError']")'"
ipc closeAll
