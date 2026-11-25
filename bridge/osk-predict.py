#!/usr/bin/env python3
"""The screen keyboard's word engine, on this machine: completion, next-word
prediction, autocorrect, swipe decoding and learning (Services/Osk).

One process for the keyboard's life, a JSON object per line each way:

  {"op": "suggest", "lang": "en", "prev": "see you", "word": "tom"}
      -> {"op": "suggest", "word": "tom", "words": ["tomorrow", "tom", "tomato"],
          "correction": null}
  {"op": "suggest", "lang": "en", "prev": "see you", "word": ""}      next word
  {"op": "swipe", "lang": "en", "keys": "hgfdewrtyuiolkmnbvfgbnmjhgfd"}
      -> {"op": "swipe", "words": ["hello", ...]}
  {"op": "learn", "lang": "en", "text": "see you tomorrow"}             -> {"op": "learn"}
  {"op": "forget"}                                                   -> wipes what was learned

Where the words come from, best first: what this person typed (word pairs,
then words), the keyboard's common words, then the system dictionary
(hunspell's <lang>.dic, or /usr/share/dict/words for English). Nothing is
downloaded and nothing leaves the machine; what is learned is a JSON file
under XDG_DATA_HOME/shani-shell, and the keyboard does not send password
fields here at all.

Autocorrect is conservative: only a word the dictionary does not know, at
least three letters, corrected to a known word one edit away (two for long
words), preferring keys that are neighbours on a QWERTY board.
"""
import json
import os
import re
import sys
from collections import defaultdict

COMMON_EN = (
    "the of and to a in is it you that he was for on are with as i his they be at one have this from or "
    "had by not word but what some we can out other were all there when up use your how said an each she "
    "which do their time if will way about many then them write would like so these her long make thing see "
    "him two has look more day could go come did number sound no most people my over know water than call "
    "first who may down side been now find any new work part take get place made live where after back little "
    "only round man year came show every good me give our under name very through just form sentence great "
    "think say help low line differ turn cause much mean before move right boy old too same tell does set three "
    "want air well also play small end put home read hand port large spell add even land here must big high such "
    "follow act why ask men change went light kind off need house picture try us again animal point mother world "
    "near build self earth father head stand own page should country found answer school grow study still learn "
    "plant cover food sun four between state keep eye never last let thought city tree cross farm hard start might "
    "story saw far sea draw left late run don't while press close night real life few north open seem together next "
    "white children begin got walk example ease paper group always music those both mark often letter until mile "
    "river car feet care second book carry took science eat room friend began idea fish mountain stop once base "
    "hear horse cut sure watch color face wood main enough plain girl usual young ready above ever red list though "
    "feel talk bird soon body dog family direct pose leave song measure door product black short numeral class wind "
    "question happen complete ship area half rock order fire south problem piece told knew pass since top whole king "
    "space heard best hour better true during hundred five remember step early hold west ground interest reach fast "
    "verb sing listen six table travel less morning ten simple several vowel toward war lay against pattern slow "
    "center love person money serve appear road map rain rule govern pull cold notice voice unit power town fine "
    "certain fly fall lead cry dark machine note wait plan figure star box noun field rest correct able pound done "
    "beauty drive stood contain front teach week final gave green oh quick develop ocean warm free minute strong "
    "special mind behind clear tail produce fact street inch multiply nothing course stay wheel full force blue "
    "object decide surface deep moon island foot system busy test record boat common gold possible plane stead dry "
    "wonder laugh thousand ago ran check game shape equate hot miss brought heat snow tire bring yes distant fill "
    "east paint language among hello thanks thank please sorry okay tomorrow today yesterday meeting email message "
    "call later soon tonight weekend morning evening lunch dinner love miss happy birthday congratulations"
).split()

LETTERS = "qwertyuiop asdfghjkl zxcvbnm"
ROWS = [r for r in LETTERS.split()]
POS = {c: (ri, ci + (0.5 * ri)) for ri, row in enumerate(ROWS) for ci, c in enumerate(row)}


def near(a, b):
    """True for two letters that touch on a QWERTY board (a likely slip)."""
    if a not in POS or b not in POS:
        return False
    (r1, c1), (r2, c2) = POS[a], POS[b]
    return abs(r1 - r2) <= 1 and abs(c1 - c2) <= 1.0


def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
    return os.path.join(base, "shani-shell")


def dic_paths(lang):
    """hunspell files for a keyboard language: "en", "mr", or an xkb id
    ("ru", "in+tam", "de+neo") - its language part, in any region."""
    import glob
    base = lang.split("+")[-1] if lang.startswith("in+") else lang.split("+")[0]
    base = {"us": "en", "gb": "en", "eng": "en", "tam": "ta", "tel": "te", "kan": "kn", "mal": "ml",
            "guj": "gu", "ben": "bn", "pan": "pa", "guru": "pa", "ori": "or", "deva": "hi"}.get(base, base)
    out = []
    for d in ("/usr/share/hunspell", "/usr/share/myspell/dicts"):
        out += sorted(glob.glob(f"{d}/{base}_*.dic")) + sorted(glob.glob(f"{d}/{base}.dic"))
    if base == "en":
        out.sort(key=lambda p: "en_US" not in p)
    return out[:1]


def dictionary_words(lang):
    """The system's words for a language: hunspell, or dict/words for English."""
    out = []
    for path in dic_paths(lang):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                next(f, None)                         # the first line is a count
                for line in f:
                    w = line.split("/", 1)[0].strip()
                    # a capitalised entry is a name (Tehran, Heloise): not offered
                    if w and not any(ch.isdigit() for ch in w) and not w[:1].isupper():
                        out.append(w)
            break
        except OSError:
            continue
    if not out and lang in ("en", "us", "gb"):
        try:
            with open("/usr/share/dict/words", encoding="utf-8", errors="replace") as f:
                out = [w.strip() for w in f if w.strip().isalpha() and not w[:1].isupper()]
        except OSError:
            pass
    return out


class Model:
    def __init__(self, lang):
        self.lang = lang
        self.path = os.path.join(data_dir(), f"osk-words-{lang}.json")
        self.uni = defaultdict(int)          # word -> times typed
        self.bi = defaultdict(lambda: defaultdict(int))   # prev -> word -> times
        self.load()
        common = COMMON_EN if lang == "en" else []
        self.rank = {w: i for i, w in enumerate(common)}
        words = dictionary_words(lang)
        self.known = {w.lower() for w in words} | set(common)
        # words by first letter, for completion and correction
        self.by_first = defaultdict(list)
        for w in sorted(self.known, key=lambda w: (self.rank.get(w, 10 ** 6), len(w), w)):
            self.by_first[w[:1]].append(w)

    def load(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                d = json.load(f)
            for w, n in d.get("uni", {}).items():
                self.uni[w] = int(n)
            for p, m in d.get("bi", {}).items():
                for w, n in m.items():
                    self.bi[p][w] = int(n)
        except (OSError, ValueError):
            pass

    def save(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"uni": self.uni, "bi": {p: dict(m) for p, m in self.bi.items()}}, f)
        os.replace(tmp, self.path)

    def score(self, w, prev):
        """Higher is better: the pair typed before, the word typed before, common, short."""
        s = 0.0
        if prev and w in self.bi.get(prev, {}):
            s += 1000 + 50 * self.bi[prev][w]
        s += 20 * self.uni.get(w, 0)
        if w in self.rank:
            s += 200 - self.rank[w] / 10
        return s - len(w) * 0.5

    def candidates(self, first):
        learned = [w for w in self.uni if w.startswith(first)]
        return learned + self.by_first.get(first, [])

    def complete(self, word, prev, n=3):
        w = word.lower()
        seen, out = set(), []
        pool = [c for c in self.candidates(w[:1]) if c.startswith(w)]
        for c in sorted(set(pool), key=lambda c: -self.score(c, prev)):
            if c not in seen:
                seen.add(c)
                out.append(c)
            if len(out) >= n:
                break
        return out

    def next_words(self, prev, n=3):
        if prev in self.bi:
            return [w for w, _ in sorted(self.bi[prev].items(), key=lambda x: -x[1])][:n]
        return []

    def correction(self, word, prev):
        w = word.lower()
        # QWERTY slips: Latin letters only (other scripts' keyboards differ)
        if len(w) < 3 or not w.isascii() or not w.isalpha() or w in self.known or w in self.uni:
            return None
        best, best_s = None, -1e9
        limit = 2 if len(w) >= 6 else 1
        # words starting with the first letter, or the second (the first two swapped: hte)
        for c in set(self.candidates(w[:1]) + self.candidates(w[1:2])):
            if abs(len(c) - len(w)) > limit:
                continue
            d = distance(w, c, limit)
            if d is None:
                continue
            s = self.score(c, prev) - d * 1000   # the closest word; frequency breaks ties
            if s > best_s:
                best, best_s = c, s
        return best

    def swipe(self, keys, prev, n=3):
        k = "".join(ch for ch in keys.lower() if ch in POS)
        if len(k) < 2:
            return []
        first, last = k[0], k[-1]
        out = []
        for c in set(self.candidates(first)):
            if len(c) < 2 or c[-1] != last or not subsequence(squeeze(c), k):
                continue
            out.append(c)
        out.sort(key=lambda c: -(self.score(c, prev) + 3 * len(c)))
        return out[:n]

    def learn(self, text):
        # a word in any script: everything between spaces and punctuation
        words = [w.lower() for w in re.findall(r"[^\s\d.,!?;:\"()\[\]{}<>/\\]+", text)]
        prev = ""
        for w in words:
            self.uni[w] += 1
            if prev:
                self.bi[prev][w] += 1
            prev = w
        self.save()


def squeeze(w):
    """'hello' -> 'helo': a swipe passes a doubled letter once."""
    out = []
    for ch in w:
        if not out or out[-1] != ch:
            out.append(ch)
    return "".join(out)


def subsequence(word, path):
    it = iter(path)
    return all(ch in it for ch in word)


def distance(a, b, limit):
    """Typing distance: an edit is 1, but the slips people make cost half -
    a neighbouring key, two letters swapped (teh/the), a doubled letter
    missed or added (helo/hello). None when over the limit."""
    n, m = len(a), len(b)
    d = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = float(i)
    for j in range(m + 1):
        d[0][j] = float(j)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            ca, cb = a[i - 1], b[j - 1]
            sub_cost = 0.0 if ca == cb else (0.5 if near(ca, cb) else 1.0)
            dele = 0.5 if i > 1 and a[i - 2] == ca else 1.0      # an extra doubled letter
            ins = 0.4 if j > 1 and b[j - 2] == cb else 1.0       # a doubled letter missed (the commonest slip)
            best = min(d[i - 1][j] + dele, d[i][j - 1] + ins, d[i - 1][j - 1] + sub_cost)
            if i > 1 and j > 1 and ca == b[j - 2] and a[i - 2] == cb:
                best = min(best, d[i - 2][j - 2] + 0.5)          # two letters swapped
            d[i][j] = best
        if min(d[i]) > limit:
            return None
    return d[n][m] if d[n][m] <= limit else None


def main():
    models = {}

    def model(lang):
        lang = lang or "en"
        if lang not in models:
            models[lang] = Model(lang)
        return models[lang]

    for line in sys.stdin:
        try:
            req = json.loads(line)
        except ValueError:
            continue
        op = req.get("op")
        try:
            if op == "suggest":
                m = model(req.get("lang"))
                prev = (req.get("prev") or "").lower().split()[-1:] or [""]
                prev = prev[0]
                word = req.get("word") or ""
                if word:
                    words = m.complete(word, prev)
                    fix = m.correction(word, prev)
                    resp = {"op": "suggest", "word": word, "words": words, "correction": fix}
                else:
                    resp = {"op": "suggest", "word": "", "words": m.next_words(prev), "correction": None}
            elif op == "swipe":
                m = model(req.get("lang"))
                prev = (req.get("prev") or "").lower().split()[-1:] or [""]
                resp = {"op": "swipe", "words": m.swipe(req.get("keys") or "", prev[0])}
            elif op == "learn":
                model(req.get("lang")).learn(req.get("text") or "")
                resp = {"op": "learn"}
            elif op == "forget":
                for f in os.listdir(data_dir()) if os.path.isdir(data_dir()) else []:
                    if f.startswith("osk-words-"):
                        os.remove(os.path.join(data_dir(), f))
                models.clear()
                resp = {"op": "forget"}
            else:
                resp = {"op": op, "error": "unknown op"}
        except (OSError, ValueError) as e:
            resp = {"op": op, "error": e.__class__.__name__}
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
