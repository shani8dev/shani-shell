# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=document-papers)
# ---- Papers parity: night mode, the page's text copied, the document's properties ----
P=/tmp/document-papers; rm -rf $P; mkdir -p $P
python3 -c 'import pymupdf,sys; d=pymupdf.open(); d.new_page().insert_text((72,72),"hello night reader"); d.set_metadata({"title":"Night Test","author":"Shani"}); d.save(sys.argv[1])' $P/doc.pdf
ipc openPdf "$P/doc.pdf"
waitfor "not d['pdfLoading'] and d['pdfPages'] == 1" 15
ipc pdfNight true
waitfor "d['pdfNightShown']" 10 && result document-night-mode PASS || result document-night-mode FAIL "$(q "['pdfNightShown'], d['pdfPages']")"
shot document-night 0.3
ipc pdfNight false
printf '' | wl-copy; sleep 0.3
waitfor "True" 1; ipc pdfCopyText; sleep 0.8
wl-paste -n 2>/dev/null | grep -q 'hello night reader' && result document-copy-page-text PASS || result document-copy-page-text FAIL "$(wl-paste -n 2>&1 | head -c 100)"
ipc pdfInfo
waitfor "'Title=Night Test' in d['pdfInfo'] and 'Author=Shani' in d['pdfInfo']" 8 && result document-properties PASS || result document-properties FAIL "$(q "['pdfInfo']")"
rm -rf $P; ipc closeAll
