.pragma library
// Syntax colours for the Text Editor: text in, the same text out as HTML with
// its comments, strings, numbers and keywords in <span>s. One pass with one
// regular expression per language family - enough to read code by, not a
// parser. Every character of the input is in the output, in order (the editor
// draws this under the text being typed, so the two must line up).

var families = {
    hash: { line: "#", strings: "'\"" },                     // python, shell, yaml, toml, ini, makefile, ruby, perl
    c: { line: "//", block: true, strings: "'\"`" },          // js, ts, qml, c, c++, java, rust, go, css, kdl
    markup: { markup: true },                                 // html, xml, svg
    plain: {}
};

var langs = {
    python: ["hash", "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield self"],
    shell: ["hash", "if then else elif fi for while until do done case esac function return break continue export local readonly source in select time exit echo printf cd test set unset shift trap"],
    yaml: ["hash", "true false yes no on off null"],
    toml: ["hash", "true false"],
    ini: ["hash", "true false yes no on off"],
    makefile: ["hash", "ifeq ifneq ifdef ifndef else endif include define endef export override"],
    ruby: ["hash", "def end class module if elsif else unless while until for in do return yield begin rescue ensure nil true false self require and or not then case when"],
    javascript: ["c", "async await break case catch class const continue debugger default delete do else export extends false finally for from function if import in instanceof let new null of return static super switch this throw true try typeof undefined var void while yield interface type enum implements readonly"],
    qml: ["c", "import property readonly required signal function default alias var let const if else for while return true false null undefined int real bool string color url list pragma component on"],
    json: ["c", "true false null"],
    c: ["c", "auto bool break case char class const constexpr continue default delete do double else enum extern false float for goto if inline int long namespace new nullptr private protected public return short signed sizeof static struct switch template this throw true try typedef union unsigned using virtual void volatile while include define ifdef ifndef endif"],
    java: ["c", "abstract boolean break byte case catch char class const continue default do double else enum extends false final finally float for if implements import instanceof int interface long native new null package private protected public return short static super switch synchronized this throw throws true try void volatile while var record"],
    rust: ["c", "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"],
    go: ["c", "break case chan const continue default defer else fallthrough false for func go goto if import interface map nil package range return select struct switch true type var"],
    css: ["c", "important inherit initial unset none auto"],
    kdl: ["c", "true false null"],
    html: ["markup", ""],
    markdown: ["plain", ""],
    diff: ["plain", ""],
    text: ["plain", ""]
};

var byExt = {
    py: "python", pyw: "python", sh: "shell", bash: "shell", zsh: "shell", fish: "shell", profile: "shell", bashrc: "shell", zshrc: "shell",
    yaml: "yaml", yml: "yaml", toml: "toml", ini: "ini", conf: "ini", cfg: "ini", desktop: "ini", service: "ini", timer: "ini", socket: "ini", mount: "ini", target: "ini", list: "ini", properties: "ini",
    mk: "makefile", rb: "ruby", js: "javascript", mjs: "javascript", cjs: "javascript", ts: "javascript", jsx: "javascript", tsx: "javascript",
    qml: "qml", json: "json", jsonc: "json", c: "c", h: "c", cc: "c", cpp: "c", cxx: "c", hpp: "c", hh: "c", cs: "c", java: "java", kt: "java", scala: "java",
    rs: "rust", go: "go", css: "css", scss: "css", kdl: "kdl", html: "html", htm: "html", xml: "html", svg: "html", ui: "html",
    md: "markdown", markdown: "markdown", diff: "diff", patch: "diff"
};

function langFor(path, firstLine) {
    var name = String(path || "").split("/").pop().toLowerCase();
    if (name === "makefile" || name === "gnumakefile")
        return "makefile";
    if (name === "pkgbuild" || name === ".bashrc" || name === ".profile" || name === ".zshrc")
        return "shell";
    var dot = name.lastIndexOf(".");
    var ext = dot >= 0 ? name.substring(dot + 1) : "";
    if (byExt[ext])
        return byExt[ext];
    // no extension to go by: the "#!" line says
    var m = /^#!.*?\b(python|bash|sh|zsh|node|ruby|perl)\d*\b/.exec(String(firstLine || ""));
    if (m)
        return { python: "python", bash: "shell", sh: "shell", zsh: "shell", node: "javascript", ruby: "ruby", perl: "shell" }[m[1]];
    return "text";
}

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

var cache = {};
function matcher(lang) {
    if (cache[lang])
        return cache[lang];
    var spec = langs[lang] || langs.text, fam = families[spec[0]], parts = [];
    if (fam.markup) {
        parts.push("(<!--[\\s\\S]*?(?:-->|$))");                            // 1 comment
        parts.push("(\"[^\"\\n]*\"|'[^'\\n]*')");                             // 2 string
        parts.push("(?!x)x()");                                              // 3 number (none)
        parts.push("(</?[A-Za-z][\\w:.-]*|/?>)");                            // 4 "keyword": the tag
    } else {
        var comment = [];
        if (fam.block) comment.push("/\\*[\\s\\S]*?(?:\\*/|$)");
        if (fam.line) comment.push((fam.line === "#" ? "#" : "//") + "[^\\n]*");
        parts.push(comment.length ? "(" + comment.join("|") + ")" : "(?!x)x()");
        var strings = [];
        var q = fam.strings || "";
        if (lang === "python") strings.push('"""[\\s\\S]*?(?:"""|$)', "'''[\\s\\S]*?(?:'''|$)");
        if (q.indexOf('"') >= 0) strings.push('"(?:[^"\\\\\\n]|\\\\.)*"?');
        if (q.indexOf("'") >= 0) strings.push("'(?:[^'\\\\\\n]|\\\\.)*'?");
        if (q.indexOf("`") >= 0) strings.push("`(?:[^`\\\\]|\\\\[\\s\\S])*`?");
        parts.push(strings.length ? "(" + strings.join("|") + ")" : "(?!x)x()");
        parts.push("(\\b(?:0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b)");
        parts.push("([A-Za-z_][A-Za-z0-9_]*)");
    }
    var words = {};
    spec[1].split(" ").forEach(function (w) { if (w) words[w] = true; });
    cache[lang] = { re: new RegExp(parts.join("|"), "g"), words: words, markup: !!fam.markup };
    return cache[lang];
}

// colors: { comment, string, number, keyword, heading, added, removed }
function html(text, lang, colors) {
    text = String(text);
    var out = "";
    if (lang === "markdown" || lang === "diff") {
        // by the line: headings and quotes; added and removed lines
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i], c = "";
            if (lang === "markdown")
                c = /^#{1,6} /.test(l) ? colors.heading : /^\s*(>|```|~~~)/.test(l) ? colors.comment : /^\s*([-*+]|\d+\.) /.test(l) ? colors.keyword : "";
            else
                c = /^(\+\+\+|---|@@|diff |index )/.test(l) ? colors.keyword : l.charAt(0) === "+" ? colors.added : l.charAt(0) === "-" ? colors.removed : "";
            out += (c ? '<span style="color:' + c + '">' + esc(l) + "</span>" : esc(l)) + (i < lines.length - 1 ? "\n" : "");
        }
        return out;
    }
    var m = matcher(lang);
    if (lang === "text" || !m)
        return esc(text);
    var re = m.re, last = 0, hit;
    re.lastIndex = 0;
    while ((hit = re.exec(text)) !== null) {
        if (hit[0] === "") { re.lastIndex++; continue; }
        var color = hit[1] !== undefined ? colors.comment : hit[2] !== undefined ? colors.string : hit[3] !== undefined ? colors.number
            : (m.markup || m.words[hit[0]]) ? colors.keyword : "";
        if (!color)
            continue;                      // an ordinary word: left in the plain run
        out += esc(text.substring(last, hit.index)) + '<span style="color:' + color + '">' + esc(hit[0]) + "</span>";
        last = hit.index + hit[0].length;
    }
    return out + esc(text.substring(last));
}
