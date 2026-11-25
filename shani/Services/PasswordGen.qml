pragma Singleton

// A password from the system's randomness (Python's `secrets`, never
// Math.random), for Passwords and Keys: its Generator tab and the form's
// Generate button. One script: the Password Generator app had a second copy
// before it was merged into Passwords and Keys.
//
//   PasswordGen.command(length, symbols, digits, words)   argv for a Process
//
// It prints the password, or "FALLBACK:<password>" when four words were asked
// for and no word list is installed (a character password is made instead).
// One of each kind asked for is always in it, so no site refuses it.
import Quickshell
import QtQuick

Singleton {
    readonly property string script: `import secrets, string, sys
n, sym, dig, words = int(sys.argv[1]), sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4] == "1"
fallback = False
if words:
    try:
        pool = [w.strip() for w in open("/usr/share/dict/words") if w.strip().isalpha() and w.strip().islower() and 4 <= len(w.strip()) <= 8]
    except OSError:
        pool = []
    if len(pool) > 2000:
        print("-".join(secrets.choice(pool) for _ in range(max(4, n // 5))))
        sys.exit(0)
    fallback = True
alphabet = string.ascii_letters + (string.digits if dig else "") + ("!@#$%^&*()-_=+[]{};:,.?" if sym else "")
while True:
    pw = "".join(secrets.choice(alphabet) for _ in range(n))
    if (not dig or any(c.isdigit() for c in pw)) and (not sym or any(not c.isalnum() for c in pw)) and any(c.islower() for c in pw) and any(c.isupper() for c in pw):
        print(("FALLBACK:" if fallback else "") + pw)
        break`

    function command(length, symbols, digits, words) {
        return ["python3", "-c", script, String(length), symbols ? "1" : "0", digits ? "1" : "0", words ? "1" : "0"];
    }
}
