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

# Find the largest existing PREFIX-XXXX number (addresses are base 36, like Forester's own).
max=0
for f in trees/"$PREFIX"-*.tree; do
  [ -e "$f" ] || continue
  id="$(basename "$f" .tree)"
  id="${id#"$PREFIX"-}"
  case "$id" in *[!0-9A-Za-z]*|"") continue ;; esac
  n=$((36#$id))
  [ "$n" -gt "$max" ] && max=$n
done

# Format max+1 as 4 base-36 digits.
n=$((max + 1))
digits=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ
id=""
while [ "$n" -gt 0 ]; do
  id="${digits:$((n % 36)):1}$id"
  n=$((n / 36))
done
while [ "${#id}" -lt 4 ]; do id="0$id"; done

ADDR="$PREFIX-$id"
FILE="trees/$ADDR.tree"

{
  printf '\\title{%s}\n' "$TITLE"
  [ -n "$TAXON" ] && printf '\\taxon{%s}\n' "$TAXON"
  printf '\\date{%s}\n' "$(date +%Y-%m-%d)"
  printf '\\author{%s}\n' "$AUTHOR"
  printf '\\import{macros}\n\n'
  printf '\\p{\n  Write here. Inline maths: #{x^2}, display maths: ##{\\int_0^1 x\\,dx = \\frac{1}{2}}\n}\n'
} > "$FILE"

echo "Created $FILE"
echo "To list it on the Notes page, add this line to trees/notes.tree:"
echo "  \\transclude{$ADDR}"
