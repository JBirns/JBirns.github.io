#!/usr/bin/env bash
# Convert pasted LaTeX into Forester markup and put it in a tree.
#
#   make paste                      paste LaTeX into the terminal, press Ctrl+D -> new tree with a fresh address
#   make paste TITLE="Compactness"  same, with that title (default: the first \section title, else "Untitled")
#   make paste INTO=K3P9            add the converted text to the end of trees/K3P9.tree instead
#   make paste FILE=notes.tex       read the LaTeX from a file instead of the terminal
#
# (Also runnable directly: ./scripts/paste.sh [file.tex], with INTO=... / TITLE=... in front.)
# The conversion itself is written in Python (embedded below), which handles nested braces and
# environments far more reliably than sed or awk could. It needs only python3, no extra packages.
set -euo pipefail

FOREST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FOREST_ROOT

command -v python3 >/dev/null || { echo "paste.sh needs python3 (sudo apt install python3)" >&2; exit 1; }

CONVERTER=$(cat <<'PY'
"""Convert a block of LaTeX into Forester markup and put it in a tree.

    make paste                      paste LaTeX into the terminal, press Ctrl+D -> new tree with a fresh address
    make paste TITLE="Compactness"  same, with that title (default: the first \\section title, else "Untitled")
    make paste INTO=K3P9            add the converted text to the end of trees/K3P9.tree instead
    make paste FILE=notes.tex       read the LaTeX from a file instead of the terminal

The converted text is also printed. Maths is copied unchanged; only the wrapping changes:
$...$ and \\(...\\) become #{...}; $$...$$, \\[...\\] and equation/align/gather become ##{...};
paragraphs become \\p{...}; \\emph/\\textbf become \\em/\\strong; itemize/enumerate become \\ul/\\ol;
theorem-like environments become subtrees with a taxon; proof becomes \\proof; \\section becomes a
titled subtree. Anything without a Forester equivalent (\\cite, \\ref, ...) is kept visible as code
and listed under "Check by hand".
"""
import os
import re
import subprocess
import sys
import unicodedata

WARNINGS = []


def warn(msg):
    if msg not in WARNINGS:
        WARNINGS.append(msg)


# ---------------------------------------------------------------------------
# Small scanning helpers

def match_brace(s, i, open_="{", close="}"):
    """s[i] == open_; return index of the matching close (handles backslash escapes)."""
    depth = 0
    j = i
    while j < len(s):
        c = s[j]
        if c == "\\":
            j += 2
            continue
        if c == open_:
            depth += 1
        elif c == close:
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def read_group(s, i, allow_space=True):
    """Read a {...} argument starting at or after i. Returns (content, end) or (None, i)."""
    j = i
    if allow_space:
        while j < len(s) and s[j] in " \t\n":
            j += 1
    if j < len(s) and s[j] == "{":
        k = match_brace(s, j)
        if k != -1:
            return s[j + 1:k], k + 1
    return None, i


def read_optional(s, i):
    """Read a [...] argument starting at or after i. Returns (content, end) or (None, i)."""
    j = i
    while j < len(s) and s[j] in " \t":
        j += 1
    if j < len(s) and s[j] == "[":
        k = match_brace(s, j, "[", "]")
        if k != -1:
            return s[j + 1:k], k + 1
    return None, i


def find_env_end(s, i, env):
    """i is just after \\begin{env}; return (start of \\end{env}, index after it)."""
    pat = re.compile(r"\\(begin|end)\s*\{" + re.escape(env) + r"\}")
    depth = 1
    for m in pat.finditer(s, i):
        depth += 1 if m.group(1) == "begin" else -1
        if depth == 0:
            return m.start(), m.end()
    return len(s), len(s)


def strip_comments(s):
    out = []
    for line in s.split("\n"):
        j = 0
        cut = len(line)
        while j < len(line):
            if line[j] == "\\":
                j += 2
                continue
            if line[j] == "%":
                cut = j
                break
            j += 1
        out.append(line[:cut])
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Pass 1: pull out all maths, replacing it with placeholders

MATHS = []  # list of (kind, content): kind is "inline", "display" or "tex"

DISPLAY_UNWRAP = {"equation", "equation*", "displaymath", "math"}
DISPLAY_RENAME = {
    "align": "align*", "align*": "align*", "flalign": "align*", "flalign*": "align*",
    "eqnarray": "align*", "eqnarray*": "align*",
    "gather": "gather*", "gather*": "gather*",
    "multline": "gather*", "multline*": "gather*",
    "alignat": "alignat*", "alignat*": "alignat*",
}
TIKZ = {"tikzcd": r"\usepackage{tikz-cd}", "tikzpicture": r"\usepackage{tikz}"}


def clean_math(m):
    """Make LaTeX maths safe for Forester + KaTeX without changing what it means."""
    if re.search(r"\\label\s*\{", m):
        warn(r"\label{...} inside maths was removed (equation labels and \ref don't carry over).")
    m = re.sub(r"\\label\s*\{[^{}]*\}", "", m)
    m = re.sub(r"\\(nonumber|notag)\b", "", m)
    out = []
    j = 0
    while j < len(m):
        if m.startswith("\\\\", j):
            out.append("\\\\")
            j += 2
        elif m.startswith("\\{", j):
            out.append("\\lbrace ")
            j += 2
        elif m.startswith("\\}", j):
            out.append("\\rbrace ")
            j += 2
        else:
            out.append(m[j])
            j += 1
    return "".join(out).strip()


def add_math(kind, content):
    MATHS.append((kind, content))
    marker = "\x00D" if kind in ("display", "tex") else "\x00M"
    return f"{marker}{len(MATHS) - 1}\x00"


def add_display(content):
    for env, pkg in TIKZ.items():
        if "\\begin{" + env + "}" in content:
            warn(f"A {env} diagram became a \\tex image: it needs LaTeX installed to preview.")
            return add_math("tex", (pkg, content.strip()))
    return add_math("display", clean_math(content))


def extract_maths(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        if s.startswith("\\\\", i):
            out.append("\\\\")
            i += 2
            continue
        if s.startswith("\\$", i):
            out.append("\\$")
            i += 2
            continue
        if s.startswith("\\[", i):
            k = s.find("\\]", i + 2)
            if k != -1:
                out.append(add_display(s[i + 2:k]))
                i = k + 2
                continue
        if s.startswith("\\(", i):
            k = s.find("\\)", i + 2)
            if k != -1:
                out.append(add_math("inline", clean_math(s[i + 2:k])))
                i = k + 2
                continue
        if s.startswith("$$", i):
            k = s.find("$$", i + 2)
            if k != -1:
                out.append(add_display(s[i + 2:k]))
                i = k + 2
                continue
        if s[i] == "$":
            k = i + 1
            while k < n and not (s[k] == "$" and s[k - 1] != "\\"):
                k += 1
            if k < n:
                out.append(add_math("inline", clean_math(s[i + 1:k])))
                i = k + 1
                continue
        m = re.match(r"\\begin\s*\{([A-Za-z*]+)\}", s[i:])
        if m:
            env = m.group(1)
            if env in DISPLAY_UNWRAP or env in DISPLAY_RENAME or env in TIKZ:
                start = i + m.end()
                end_start, end = find_env_end(s, start, env)
                body = s[start:end_start]
                if env in DISPLAY_UNWRAP:
                    out.append(add_display(body))
                elif env in TIKZ:
                    out.append(add_display(s[i:end]))
                else:
                    new = DISPLAY_RENAME[env]
                    if env.startswith("eqnarray"):
                        warn("eqnarray was turned into align*: check the alignment (& positions) by eye.")
                    if env.startswith("multline"):
                        warn("multline was turned into gather*: lines are centred rather than staggered.")
                    out.append(add_display("\\begin{%s}%s\\end{%s}" % (new, body, new)))
                i = end
                continue
        out.append(s[i])
        i += 1
    return "".join(out)


# ---------------------------------------------------------------------------
# Pass 2: inline text -> Forester

WRAP = {  # \cmd{x} -> \forester{x}
    "emph": "em", "textit": "em", "textsl": "em", "underline": "em",
    "textbf": "strong", "texttt": "code",
}
UNWRAP = {"textrm", "textsf", "textup", "textnormal", "textmd", "text", "mbox", "hbox", "textsc",
          "small", "large", "Large", "footnotesize"}
SWITCH = {  # {\em x} -> \em{x}
    "em": "em", "it": "em", "itshape": "em", "sl": "em", "slshape": "em",
    "bf": "strong", "bfseries": "strong", "tt": "code", "ttfamily": "code",
    "rm": None, "sf": None, "sc": None, "scshape": None, "normalfont": None,
    "small": None, "large": None, "Large": None, "footnotesize": None,
}
DROP_0 = {"noindent", "indent", "medskip", "smallskip", "bigskip", "par", "centering", "maketitle",
          "clearpage", "newpage", "pagebreak", "vfill", "hfill", "relax", "protect", "null",
          "raggedright", "raggedleft", "nobreak", "allowbreak", "linebreak", "displaystyle"}
DROP_1 = {"vspace", "hspace", "vspace*", "hspace*", "label", "index", "thispagestyle", "pagestyle"}
SPACE_0 = {"newline", "quad", "qquad", "enspace", "thinspace"}
SYMBOLS = {"ldots": "…", "dots": "…", "textellipsis": "…", "LaTeX": "LaTeX", "TeX": "TeX", "S": "§",
           "P": "¶", "copyright": "©", "textendash": "–", "textemdash": "—", "ss": "ß", "o": "ø",
           "O": "Ø", "ae": "æ", "AE": "Æ", "aa": "å", "AA": "Å", "l": "ł", "L": "Ł", "i": "ı",
           "textbackslash": "\\\\", "textasciitilde": "~", "textbullet": "•", "dag": "†",
           "textdegree": "°", "today": ""}
ACCENTS = {"'": "\u0301", "`": "\u0300", "^": "\u0302", '"': "\u0308", "~": "\u0303",
           "=": "\u0304", ".": "\u0307", "u": "\u0306", "v": "\u030C", "H": "\u030B",
           "c": "\u0327", "k": "\u0328", "r": "\u030A"}
FLAG = {"cite", "citep", "citet", "citealp", "citeauthor", "citeyear", "nocite", "ref", "eqref", "cref",
        "Cref", "autoref", "pageref", "nameref", "footnote", "footnotemark", "footnotetext",
        "includegraphics", "input", "include"}


def verbatim_code(raw):
    return "\\code{\\startverb" + raw + "\\stopverb}"


def inline(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\x00":
            k = s.index("\x00", i + 1)
            idx = int(s[i + 2:k])
            kind, content = MATHS[idx]
            out.append("#{" + content + "}" if kind == "inline" else render_display(idx))
            i = k + 1
            continue
        if c == "\\":
            m = re.match(r"\\([A-Za-z]+\*?)", s[i:])
            if not m:
                nxt = s[i + 1] if i + 1 < n else ""
                if nxt in ACCENTS:
                    m2 = re.match(r"\\" + re.escape(nxt) + r"\s*(?:\{\s*\\?([A-Za-z])\s*\}|([A-Za-z]))", s[i:])
                    if m2:
                        letter = m2.group(1) or m2.group(2)
                        out.append(unicodedata.normalize("NFC", letter + ACCENTS[nxt]))
                        i += m2.end()
                        continue
                simple = {"\\": " ", "&": "&", "_": "_", "$": "$", "%": "\\%", "#": "\\#",
                          "{": "\\{", "}": "\\}", " ": " ", ",": " ", ";": " ", ":": " ", "/": "",
                          "-": "", "@": "", "!": ""}
                if nxt in simple:
                    out.append(simple[nxt])
                    i += 2
                    if nxt == "\\":  # \\[2pt]
                        _, i = read_optional(s, i)
                    continue
                out.append(nxt)
                i += 2
                continue
            name = m.group(1)
            j = i + m.end()
            base = name.rstrip("*")
            if base in ACCENTS and len(base) == 1:  # \c{c}, \v{s}, \u{a} ...
                arg, j2 = read_group(s, j)
                if arg is not None and len(arg.strip()) == 1:
                    out.append(unicodedata.normalize("NFC", arg.strip() + ACCENTS[base]))
                    i = j2
                    continue
            if name in WRAP:
                arg, j2 = read_group(s, j)
                if arg is not None:
                    out.append("\\" + WRAP[name] + "{" + inline(arg) + "}")
                    i = j2
                    continue
            if name in UNWRAP:
                arg, j2 = read_group(s, j)
                if arg is not None:
                    out.append(inline(arg))
                    i = j2
                    continue
            if name == "url":
                arg, j2 = read_group(s, j)
                if arg is not None:
                    out.append("[" + arg + "](" + arg + ")")
                    i = j2
                    continue
            if name == "href":
                url, j2 = read_group(s, j)
                text, j3 = read_group(s, j2)
                if url is not None and text is not None:
                    out.append("[" + inline(text) + "](" + url + ")")
                    i = j3
                    continue
            if name in SYMBOLS:
                out.append(SYMBOLS[name])
                i = j
                if j < n and s[j] == "{" and j + 1 < n and s[j + 1] == "}":
                    i = j + 2
                continue
            if name in SPACE_0:
                out.append(" ")
                i = j
                continue
            if name in DROP_0:
                i = j
                continue
            if name in DROP_1:
                _, j = read_optional(s, j)
                _, j2 = read_group(s, j)
                if name == "label":
                    warn(r"\label{...} was removed (labels and \ref don't carry over).")
                i = j2
                continue
            # Unknown or untranslatable: keep it visible as code, with its arguments.
            k = j
            while True:
                opt, k2 = read_optional(s, k)
                if opt is not None:
                    k = k2
                    continue
                grp, k2 = read_group(s, k, allow_space=False)
                if grp is not None:
                    k = k2
                    continue
                break
            raw = s[i:k]
            out.append(verbatim_code(raw))
            if base in FLAG:
                warn("\\%s{...} has no Forester equivalent: kept as code; replace it with a link or text." % base)
            else:
                warn("\\%s is not a Forester command: kept as code; replace it or define it in macros.tree." % base)
            i = k
            continue
        if c == "{":
            k = match_brace(s, i)
            if k == -1:
                out.append(c)
                i += 1
                continue
            body = s[i + 1:k]
            m = re.match(r"\s*\\([A-Za-z]+)\b\s*", body)
            if m and m.group(1) in SWITCH:
                target = SWITCH[m.group(1)]
                rest = inline(body[m.end():])
                out.append("\\" + target + "{" + rest + "}" if target else rest)
            else:
                out.append(inline(body))  # bare LaTeX grouping braces print nothing
            i = k + 1
            continue
        if c == "~":
            out.append("\u00a0")
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
        if s.startswith("``", i):
            out.append("“")
            i += 2
            continue
        if s.startswith("''", i):
            out.append("”")
            i += 2
            continue
        if c == "`":
            out.append("‘")
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tidy(text):
    """Collapse whitespace, but never inside \\startverb ... \\stopverb."""
    parts = re.split(r"(\\startverb.*?\\stopverb)", text, flags=re.S)
    return "".join(p if p.startswith("\\startverb") else re.sub(r"[ \t\n]+", " ", p) for p in parts).strip()


# ---------------------------------------------------------------------------
# Pass 3: blocks (paragraphs, displays, lists, environments, sections)

THEOREMS = {"theorem", "lemma", "proposition", "corollary", "definition", "example", "examples",
            "remark", "remarks", "conjecture", "claim", "exercise", "note", "notation", "question",
            "problem", "fact", "observation", "construction", "assumption", "axiom", "hypothesis",
            "solution", "warning", "convention", "algorithm"}
ABBREV = {"thm": "theorem", "lem": "lemma", "prop": "proposition", "cor": "corollary",
          "defn": "definition", "def": "definition", "dfn": "definition", "ex": "example",
          "exa": "example", "rem": "remark", "rmk": "remark", "conj": "conjecture", "exer": "exercise",
          "obs": "observation", "nota": "notation", "notn": "notation", "qn": "question"}
UNWRAP_ENVS = {"center", "flushleft", "flushright", "document", "minipage", "small", "footnotesize",
               "samepage", "figure", "figure*", "table", "table*"}
VERBATIM = {"verbatim", "verbatim*", "lstlisting", "minted", "Verbatim", "alltt"}
LISTS = {"itemize": "ul", "enumerate": "ol", "description": "ul", "compactitem": "ul",
         "compactenum": "ol"}
QUOTES = {"quote", "quotation", "verse"}


def render_display(idx):
    kind, content = MATHS[idx]
    if kind == "tex":
        pkg, body = content
        return "\\figure{\\tex{" + pkg + "}{\n" + body + "\n}}"
    return "##{\n  " + content.replace("\n", "\n  ").rstrip() + "\n}"


def paragraphs(text):
    out = []
    for para in re.split(r"\n\s*\n", text):
        p = tidy(inline(para))
        if p:
            out.append("\\p{" + p + "}")
    return out


def split_items(body):
    """Split a list body at top-level \\item (not inside braces or nested environments)."""
    items = []
    depth = 0
    env_depth = 0
    last = None
    i = 0
    while i < len(body):
        if body.startswith("\\\\", i):
            i += 2
            continue
        if body[i] == "\\":
            m = re.match(r"\\(begin|end)\s*\{[^}]*\}", body[i:])
            if m:
                env_depth += 1 if m.group(1) == "begin" else -1
                i += m.end()
                continue
            if depth == 0 and env_depth == 0 and re.match(r"\\item\b", body[i:]):
                if last is not None:
                    items.append(body[last:i])
                last = i + 5
                i += 5
                continue
            i += 2
            continue
        if body[i] == "{":
            depth += 1
        elif body[i] == "}":
            depth -= 1
        i += 1
    if last is not None:
        items.append(body[last:])
    return items


def unwrap_single_p(blocks):
    if len(blocks) == 1 and blocks[0].startswith("\\p{") and blocks[0].endswith("}"):
        return blocks[0][3:-1]
    return "\n".join(blocks)


def blocks(text):
    """Convert text (with maths placeholders) into a list of Forester block strings."""
    out = []
    pat = re.compile(r"\\begin\s*\{([A-Za-z*]+)\}|\x00D(\d+)\x00")
    pos = 0
    while True:
        m = pat.search(text, pos)
        if not m:
            out += paragraphs(text[pos:])
            break
        before = text[pos:m.start()]
        if m.group(2) is not None:
            # Display maths becomes its own block between paragraphs.
            out += paragraphs(before)
            out.append(render_display(int(m.group(2))))
            pos = m.end()
            continue
        out += paragraphs(before)
        env = m.group(1)
        start = m.end()
        end_start, end = find_env_end(text, start, env)
        body = text[start:end_start]
        pos = end
        key = env.rstrip("*").lower()
        key = ABBREV.get(key, key)
        if env in LISTS:
            items = []
            for item in split_items(body):
                label, rest_i = read_optional(item, 0)
                rest = item[rest_i:] if label is not None else item
                content = unwrap_single_p(blocks(rest))
                if label is not None:
                    content = "\\strong{" + tidy(inline(label)) + "} " + content
                items.append("  \\li{" + content.replace("\n", "\n  ") + "}")
            out.append("\\" + LISTS[env] + "{\n" + "\n".join(items) + "\n}")
        elif key in THEOREMS:
            title, rest_i = read_optional(body, 0)
            inner = blocks(body[rest_i:] if title is not None else body)
            head = "\\subtree{\n\\taxon{" + key.capitalize() + "}\n"
            if title is not None:
                head += "\\title{" + tidy(inline(title)) + "}\n"
            out.append(head + "\n".join(inner) + "\n}")
        elif key == "proof":
            _, rest_i = read_optional(body, 0)
            out.append("\\proof{\n" + "\n".join(blocks(body[rest_i:])) + "\n}")
        elif key == "abstract":
            out.append("\\subtree{\n\\taxon{Abstract}\n" + "\n".join(blocks(body)) + "\n}")
        elif env in QUOTES:
            out.append("\\blockquote{" + unwrap_single_p(blocks(body)) + "}")
        elif env in VERBATIM:
            _, rest_i = read_optional(body, 0)
            if env == "minted":
                _, rest_i = read_group(body, rest_i)
            out.append("\\pre{\\startverb\n" + restore_verbatim(body[rest_i:]).strip("\n") + "\n\\stopverb}")
        else:
            if env not in UNWRAP_ENVS:
                warn("Environment %s has no Forester equivalent: its contents were kept as plain text." % env)
            out += blocks(body)
    return out


SECTION_LEVELS = {"part": 0, "chapter": 0, "section": 1, "subsection": 2, "subsubsection": 3,
                  "paragraph": 4, "subparagraph": 5}


def document(text):
    pat = re.compile(r"\\(part|chapter|section|subsection|subsubsection|paragraph|subparagraph)\*?")
    out = []
    stack = []
    pos = 0
    while True:
        m = pat.search(text, pos)
        if not m:
            out += blocks(text[pos:])
            break
        out += blocks(text[pos:m.start()])
        _, j = read_optional(text, m.end())
        title, j2 = read_group(text, j)
        if title is None:
            out += blocks(text[m.start():m.end()])
            pos = m.end()
            continue
        level = SECTION_LEVELS[m.group(1)]
        while stack and stack[-1] >= level:
            stack.pop()
            out.append("}")
        out.append("\\subtree{\n\\title{" + tidy(inline(title)) + "}")
        stack.append(level)
        pos = j2
    out += ["}"] * len(stack)
    return out


VERB = []


def protect_verbatim(s):
    """Hide verbatim environments so comments and $ inside them are left alone."""
    pat = re.compile(r"(\\begin\s*\{(%s)\}(?:\[[^\]]*\])?(?:\{[^}]*\})?)(.*?)(\\end\s*\{\2\})"
                     % "|".join(re.escape(v) for v in VERBATIM), re.S)

    def keep(m):
        VERB.append(m.group(3))
        return m.group(1) + "\x00V%d\x00" % (len(VERB) - 1) + m.group(4)
    return pat.sub(keep, s)


def restore_verbatim(s):
    return re.sub(r"\x00V(\d+)\x00", lambda m: VERB[int(m.group(1))], s)


def convert(latex):
    del MATHS[:]
    del WARNINGS[:]
    del VERB[:]
    s = latex.replace("\r\n", "\n")
    # Keep only the body if a whole document was pasted.
    m = re.search(r"\\begin\s*\{document\}(.*?)\\end\s*\{document\}", s, re.S)
    if m:
        s = m.group(1)
    s = protect_verbatim(s)
    s = strip_comments(s)
    s = extract_maths(s)
    return "\n\n".join(b for b in document(s) if b.strip()) + "\n"


# ---------------------------------------------------------------------------
# Input and output

ROOT = os.environ["FOREST_ROOT"]


def setting(name):
    """Read FILE / INTO / TITLE: `make paste INTO=K3P9` passes them as environment variables."""
    return (os.environ.get(name) or "").strip()


def read_latex():
    path = setting("FILE") or (sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else "")
    if path:
        with open(path, encoding="utf-8") as f:
            return f.read()
    if sys.stdin.isatty():
        print("Paste your LaTeX (Ctrl+Shift+V), then press Ctrl+D on an empty line:", file=sys.stderr)
    return sys.stdin.read()


LEADING_HEADING = re.compile(
    r"^(?:\s|%[^\n]*\n)*\\(?:section|subsection|chapter)\*?\s*(?:\[[^\]]*\])?\s*\{([^{}]*)\}")


def default_title(latex):
    m = re.search(r"\\(?:section|subsection|chapter)\*?\s*(?:\[[^\]]*\])?\s*\{([^{}]*)\}", latex)
    if not m:
        return "Untitled"
    return re.sub(r"\$([^$]*)\$", r"#{\1}", m.group(1)).strip() or "Untitled"


def tree_path(into):
    name = os.path.basename(into)
    if name.endswith(".tree"):
        name = name[:-5]
    for dirpath, _, files in os.walk(os.path.join(ROOT, "trees")):
        if name + ".tree" in files:
            return os.path.join(dirpath, name + ".tree")
    return None


def new_tree(title):
    """Create a tree with scripts/new.sh (same addresses as `make new`); return its path."""
    res = subprocess.run(["bash", os.path.join(ROOT, "scripts", "new.sh"), title],
                         cwd=ROOT, capture_output=True, text=True)
    m = re.search(r"Created (\S+\.tree)", res.stdout)
    if res.returncode != 0 or not m:
        sys.exit("Could not create a new tree:\n" + res.stdout + res.stderr)
    return os.path.join(ROOT, m.group(1))


def main():
    latex = read_latex()
    if not latex.strip():
        sys.exit("Nothing to convert: no LaTeX was given.")
    result = convert(latex)

    into = setting("INTO")
    if into:
        path = tree_path(into)
        if not path:
            sys.exit("There is no tree called %s in trees/. Nothing was written; the converted text is:\n\n%s"
                     % (into, result))
        with open(path, encoding="utf-8") as f:
            old = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(old.rstrip("\n") + "\n\n" + result)
        action = "Added to the end of"
    else:
        title = setting("TITLE")
        if not title:
            title = default_title(latex)
            # If the text opens with that heading, it becomes the page title rather than a subtree.
            m = LEADING_HEADING.match(latex)
            if m:
                result = convert(latex[m.end():])
        path = new_tree(title)
        with open(path, encoding="utf-8") as f:
            template = f.read()
        # Keep everything new.sh wrote above its placeholder paragraph (title, date, author,
        # imports, ...) and replace only the placeholder "\\p{ Write here ... }".
        m = re.search(r"^\\p\{\s*Write here", template, re.M)
        head = template[:m.start()] if m else template
        with open(path, "w", encoding="utf-8") as f:
            f.write(head.rstrip("\n") + "\n\n" + result)
        action = "Created"

    print(result)
    print("--- %s %s ---" % (action, os.path.relpath(path, ROOT)), file=sys.stderr)
    if not into:
        addr = os.path.basename(path)[:-5]
        print("To list it on the Notes page, add  \\transclude{%s}  to trees/notes.tree" % addr, file=sys.stderr)
    if WARNINGS:
        print("\nCheck by hand:", file=sys.stderr)
        for w in WARNINGS:
            print("  - " + w, file=sys.stderr)


if __name__ == "__main__":
    main()
PY
)

exec python3 -c "$CONVERTER" "$@"
