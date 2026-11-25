#!/usr/bin/env bash
# Create a new tree (page) with the next free address, e.g. trees/al-0003.tree
#
#   ./scripts/new.sh "Title of the note"              # an ordinary note
#   ./scripts/new.sh "Compact sets" Definition        # with a taxon (Definition, Theorem, Lemma, ...)
set -euo pipefail
cd "$(dirname "$0")/.."

AUTHOR="yourname"
PREFIX="note"
[ -f scripts/config.sh ] && . scripts/config.sh

TITLE="${1:-Untitled}"
TAXON="${2:-}"

if [ -n "$PREFIX" ]; then pat="$PREFIX-"; else pat=""; fi
digits=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ

# Format a number as 4 base-36 digits (0000 ... ZZZZ).
to_base36() {
  local n=$1 out=""
  while [ "$n" -gt 0 ]; do
    out="${digits:$((n % 36)):1}$out"
    n=$((n / 36))
  done
  while [ "${#out}" -lt 4 ]; do out="0$out"; done
  printf '%s' "$out"
}

# Every address already in use: the file names of all .tree files in the tree folders listed in
# forest.toml (and their subfolders) and in drafts/, plus addresses given to subtrees inside them
# with \subtree[ADDR]{...}.
USED="$(python3 - <<'PY'
import os, re
text = open("forest.toml", encoding="utf-8").read()
m = re.search(r"^\s*trees\s*=\s*\[(.*?)\]", text, re.S | re.M)
folders = re.findall(r'"([^"]*)"', m.group(1)) if m else ["trees"]
used = set()
for folder in folders + ["drafts"]:
    for dirpath, _, files in os.walk(folder):
        for f in files:
            if f.endswith(".tree"):
                used.add(f[:-5])
                try:
                    src = open(os.path.join(dirpath, f), encoding="utf-8").read()
                except (OSError, UnicodeDecodeError):
                    continue
                used.update(a.strip() for a in re.findall(r"\\subtree\s*\[([^\]]+)\]", src))
print("\n".join(sorted(used)))
PY
)"

taken() {
  grep -qxF -- "$1" <<< "$USED"
}

if [ "${MODE:-sequential}" = "random" ]; then
  # A random unused address among the 36^4 = 1,679,616 possibilities.
  while :; do
    n=$(( (RANDOM * 32768 + RANDOM) % 1679616 ))
    id="$(to_base36 "$n")"
    taken "$pat$id" || break
  done
else
  # The first unused address counting up from 0001 (0001, 0002, ... 0009, 000A, ...).
  n=1
  while :; do
    id="$(to_base36 "$n")"
    taken "$pat$id" || break
    n=$((n + 1))
  done
fi

ADDR="$pat$id"
FILE="trees/$ADDR.tree"

{
  printf '\\title{%s}\n' "$TITLE"
  [ -n "$TAXON" ] && printf '\\taxon{%s}\n' "$TAXON"
  printf '\\date{%s}\n' "$(date +%Y-%m-%d)"
  printf '\\author{%s}\n' "$AUTHOR"
  printf '\\import{macros}\n\n'
  printf '\\import{names}\n\n'
  printf '\\p{\n  Write here. Inline maths: #{x^2}, display maths: ##{\\int_0^1 x\\,dx = \\frac{1}{2}}\n}\n'
} > "$FILE"

echo "Created $FILE"
echo "To list it on the Notes page, add this line to trees/notes.tree:"
echo "  \\transclude{$ADDR}"
