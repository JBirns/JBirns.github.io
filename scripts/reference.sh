#!/usr/bin/env bash
# Turn BibTeX into reference trees (pages with \taxon{Reference}).
#
#   make reference                  paste BibTeX into the terminal, press Ctrl+D -> one new tree per entry
#   make reference FILE=refs.bib    read the BibTeX from a file instead
#   make reference DIR=trees        put the new trees in another folder
#                                   (default: references/ if it exists, otherwise trees/)
#
# Addresses are chosen by scripts/new.sh, exactly as for `make new`.
# The parsing is written in Python (embedded below); it needs only python3.
set -euo pipefail

FOREST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOREST_ROOT

command -v python3 >/dev/null || { echo "reference.sh needs python3 (sudo apt install python3)" >&2; exit 1; }

CONVERTER=$(cat <<'PY'
import os
import re
import subprocess
import sys
import unicodedata
from urllib.parse import unquote

ROOT = os.environ["FOREST_ROOT"]

# ---------------------------------------------------------------------------
# BibTeX parsing

def match_brace(s, i):
    depth = 0
    j = i
    while j < len(s):
        if s[j] == "\\":
            j += 2
            continue
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def parse_bibtex(text):
    """Return a list of (entry_type, key, fields, raw_text)."""
    entries = []
    strings = {}
    for m in re.finditer(r"@\s*([A-Za-z]+)\s*([{(])", text):
        kind = m.group(1).lower()
        start = m.end() - 1
        if m.group(2) == "{":
            end = match_brace(text, start)
        else:
            end = text.find(")", start)
        if end == -1:
            continue
        body = text[start + 1:end]
        raw = text[m.start():end + 1]
        if kind in ("comment", "preamble"):
            continue
        if kind == "string":
            f = parse_fields(body, strings)
            strings.update({k: v for k, v in f.items()})
            continue
        key, _, rest = body.partition(",")
        entries.append((kind, key.strip(), parse_fields(rest, strings), raw.strip()))
    # Skip entries nested inside another entry's span (finditer would see them twice).
    seen = []
    out = []
    for e in entries:
        if e[3] not in seen:
            seen.append(e[3])
            out.append(e)
    return out


def parse_fields(body, strings):
    fields = {}
    i = 0
    n = len(body)
    while i < n:
        m = re.compile(r"\s*,?\s*([A-Za-z][\w:-]*)\s*=\s*").match(body, i)
        if not m:
            break
        name = m.group(1).lower()
        i = m.end()
        parts = []
        while i < n:
            c = body[i]
            if c == "{":
                k = match_brace(body, i)
                if k == -1:
                    k = n - 1
                parts.append(body[i + 1:k])
                i = k + 1
            elif c == '"':
                k = i + 1
                depth = 0
                while k < n and not (body[k] == '"' and depth == 0):
                    if body[k] == "{":
                        depth += 1
                    elif body[k] == "}":
                        depth -= 1
                    k += 1
                parts.append(body[i + 1:k])
                i = k + 1
            else:
                m2 = re.compile(r"[\w:.-]+").match(body, i)
                if not m2:
                    break
                word = m2.group(0)
                parts.append(strings.get(word.lower(), word))
                i = m2.end()
            m3 = re.compile(r"\s*#\s*").match(body, i)  # string concatenation
            if m3:
                i = m3.end()
                continue
            break
        fields[name] = "".join(parts).strip()
        m4 = re.compile(r"\s*,").match(body, i)
        if m4:
            i = m4.end()
    return fields


# ---------------------------------------------------------------------------
# LaTeX text -> plain Unicode (for titles, names, venues)

ACCENTS = {"'": "\u0301", "`": "\u0300", "^": "\u0302", '"': "\u0308", "~": "\u0303",
           "=": "\u0304", ".": "\u0307", "u": "\u0306", "v": "\u030C", "H": "\u030B",
           "c": "\u0327", "k": "\u0328", "r": "\u030A", "d": "\u0323", "b": "\u0331"}
SYMBOLS = {"ss": "ß", "o": "ø", "O": "Ø", "ae": "æ", "AE": "Æ", "oe": "œ", "OE": "Œ", "aa": "å",
           "AA": "Å", "l": "ł", "L": "Ł", "i": "ı", "j": "ȷ", "dh": "ð", "th": "þ", "DH": "Ð",
           "TH": "Þ", "&": "&", "%": "%", "$": "$", "#": "#", "_": "_", "{": "{", "}": "}",
           "textendash": "–", "textemdash": "—", "ldots": "…", "dots": "…", "S": "§"}


def delatex(s):
    """Turn BibTeX/LaTeX text into readable Unicode; maths $...$ becomes Forester #{...}."""
    out = []
    maths = []

    def keep_math(m):
        maths.append(m.group(1))
        return "\x00%d\x00" % (len(maths) - 1)
    s = re.sub(r"\$([^$]+)\$", keep_math, s)
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            nxt = s[i + 1]
            if nxt in ACCENTS and not nxt.isalpha() or (nxt in "uvHckrdb" and i + 2 < n and not s[i + 2].isalpha()):
                m = re.compile(r"\\" + re.escape(nxt) + r"\s*(?:\{\s*\\?([A-Za-z])\s*\}|\\?([A-Za-z]))").match(s, i)
                if m:
                    letter = m.group(1) or m.group(2)
                    if letter == "i":
                        letter = "i"
                    out.append(unicodedata.normalize("NFC", letter + ACCENTS[nxt]))
                    i = m.end()
                    continue
            m = re.compile(r"\\([A-Za-z]+)\s*").match(s, i)
            if m:
                name = m.group(1)
                if name in SYMBOLS:
                    out.append(SYMBOLS[name])
                    i = m.end()
                    if s.startswith("{}", i):
                        i += 2
                    continue
                # \emph{x}, \textit{x}, \mathcal{x} ...: keep the argument only
                i = m.end()
                continue
            if nxt in SYMBOLS:
                out.append(SYMBOLS[nxt])
                i += 2
                continue
            i += 2
            continue
        if c in "{}":
            i += 1
            continue
        if c == "~":
            out.append(" ")
            i += 1
            continue
        if s.startswith("---", i):
            out.append("—")
            i += 3
            continue
        if s.startswith("--", i):
            out.append("–")
            i += 2
            continue
        out.append(c)
        i += 1
    text = re.sub(r"\s+", " ", "".join(out)).strip()
    text = re.sub(r"\x00(\d+)\x00", lambda m: "#{" + maths[int(m.group(1))] + "}", text)
    return text


def forester_text(s):
    """Make plain text safe inside a Forester argument: % starts a comment, so escape it."""
    return s.replace("%", "\\%")


def split_authors(s):
    names = []
    depth = 0
    last = 0
    for m in re.finditer(r"[{}]|\s+and\s+", s):
        tok = m.group(0)
        if tok == "{":
            depth += 1
        elif tok == "}":
            depth -= 1
        elif depth == 0:
            names.append(s[last:m.start()])
            last = m.end()
    names.append(s[last:])
    return [x.strip() for x in names if x.strip()]


def person(name):
    """'Bollob{\\'a}s, B{\\'e}la' -> 'Béla Bollobás';  'van der Waerden, B. L.' -> 'B. L. van der Waerden'."""
    if name.lower() == "others":
        return "et al."
    parts = []
    depth = 0
    last = 0
    for i, c in enumerate(name):
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(name[last:i])
            last = i + 1
    parts.append(name[last:])
    parts = [delatex(p) for p in parts]
    if len(parts) == 2:
        return (parts[1] + " " + parts[0]).strip()
    if len(parts) == 3:  # Last, Jr, First
        return (parts[2] + " " + parts[0] + " " + parts[1]).strip()
    return parts[0]


# ---------------------------------------------------------------------------
# Output

def tree_folders():
    text = open(os.path.join(ROOT, "forest.toml"), encoding="utf-8").read()
    m = re.search(r"^\s*trees\s*=\s*\[(.*?)\]", text, re.S | re.M)
    return re.findall(r'"([^"]*)"', m.group(1)) if m else ["trees"]


def target_dir():
    d = (os.environ.get("DIR") or "").strip().strip("/")
    if d:
        if d not in tree_folders():
            print("Note: %s is not listed under trees = [...] in forest.toml, so Forester won't see it "
                  "until you add it there." % d, file=sys.stderr)
        return d
    if os.path.isdir(os.path.join(ROOT, "references")):
        return "references"
    return "trees"


def new_address(title):
    """Let scripts/new.sh pick the address (same rules as `make new`), then take over the file."""
    res = subprocess.run(["bash", os.path.join(ROOT, "scripts", "new.sh"), title],
                         cwd=ROOT, capture_output=True, text=True)
    m = re.search(r"Created (\S+\.tree)", res.stdout)
    if res.returncode != 0 or not m:
        sys.exit("scripts/new.sh could not create a tree:\n" + res.stdout + res.stderr)
    return os.path.join(ROOT, m.group(1))


def build(kind, key, f, raw, warnings):
    title = forester_text(delatex(f.get("title", ""))) or key
    lines = ["\\title{%s}" % title, "\\taxon{Reference}"]
    year = re.sub(r"\D", "", f.get("year", ""))[:4] or re.sub(r"\D", "", f.get("date", ""))[:4]
    if year:
        lines.append("\\date{%s}" % year)
    for a in split_authors(f.get("author", "")) or split_authors(f.get("editor", "")):
        lines.append("\\author/literal{%s}" % forester_text(person(a)))

    def meta(name, value):
        if value:
            lines.append("\\meta{%s}{%s}" % (name, forester_text(value)))

    if kind in ("incollection", "inproceedings", "conference", "inbook"):
        meta("in", delatex(f.get("booktitle", "")))
    meta("journal", delatex(f.get("journal", "") or f.get("journaltitle", "")))
    venue = delatex(f.get("publisher", ""))
    address = delatex(f.get("address", "") or f.get("location", ""))
    meta("publisher", ", ".join(x for x in (venue, address) if x))
    meta("series", delatex(f.get("series", "")))
    meta("volume", f.get("volume", ""))
    meta("number", f.get("number", ""))
    meta("pages", delatex(f.get("pages", "")))
    meta("edition", delatex(f.get("edition", "")))
    meta("isbn", f.get("isbn", ""))
    doi = re.sub(r"^https?://(dx\.)?doi\.org/", "", f.get("doi", "").strip())
    meta("doi", doi)
    arxiv = f.get("eprint", "") if f.get("archiveprefix", f.get("eprinttype", "")).lower() == "arxiv" \
        else f.get("arxiv", "")
    meta("arxiv", arxiv)
    url = f.get("url", "") or (("https://doi.org/" + doi) if doi else "") or \
        (("https://arxiv.org/abs/" + arxiv) if arxiv else "")
    url = unquote(url)  # %C3%A9 -> é, so no % is left to start a Forester comment
    if "%" in url:
        warnings.append("%s: the link contains %% and was left out; add it by hand." % key)
    elif url:
        lines.append("\\meta{external}{%s}" % url)
    if "\\stopverb" in raw:
        raw = raw.replace("\\stopverb", "\\ stopverb")
    lines.append("")
    lines.append("\\meta{bibtex}{\\startverb\n%s\n\\stopverb}" % raw)
    return "\n".join(lines) + "\n", title, split_authors(f.get("author", ""))


def main():
    path = (os.environ.get("FILE") or "").strip() or (sys.argv[1] if len(sys.argv) > 1 else "")
    if path:
        text = open(path, encoding="utf-8").read()
    else:
        if sys.stdin.isatty():
            print("Paste your BibTeX (Ctrl+Shift+V), then press Ctrl+D on an empty line:", file=sys.stderr)
        text = sys.stdin.read()
    entries = parse_bibtex(text)
    if not entries:
        sys.exit("No BibTeX entries found (an entry starts with something like @book{key, ...}).")

    folder = target_dir()
    os.makedirs(os.path.join(ROOT, folder), exist_ok=True)
    warnings = []
    for kind, key, fields, raw in entries:
        content, title, authors = build(kind, key, fields, raw, warnings)
        created = new_address(title)
        addr = os.path.basename(created)[:-5]
        dest = os.path.join(ROOT, folder, addr + ".tree")
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(content)
        if os.path.abspath(created) != os.path.abspath(dest):
            os.remove(created)
        surname = delatex(authors[0].split(",")[0]).split()[-1] if authors else key
        print("Created %s/%s.tree  (%s)" % (folder, addr, title[:70]), file=sys.stderr)
        print("   cite it with  [%s](%s)  or  [[%s]]" % (surname, addr, addr), file=sys.stderr)
    for w in warnings:
        print("Check by hand: " + w, file=sys.stderr)


main()
PY
)

exec python3 -c "$CONVERTER" "$@"
