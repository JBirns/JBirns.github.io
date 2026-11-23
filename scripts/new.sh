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

if [ "${MODE:-sequential}" = "random" ]; then
  # A random unused address among the 36^4 = 1,679,616 possibilities.
  while :; do
    n=$(( (RANDOM * 32768 + RANDOM) % 1679616 ))
    id="$(to_base36 "$n")"
    [ -e "trees/$pat$id.tree" ] || break
  done
else
  # The next address after the largest existing one.
  max=0
  for f in trees/"$pat"????.tree; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .tree)"
    id="${id#"$pat"}"
    case "$id" in *[!0-9A-Z]*|"") continue ;; esac
    n=$((36#$id))
    [ "$n" -gt "$max" ] && max=$n
  done
  id="$(to_base36 $((max + 1)))"
fi

ADDR="$pat$id"
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
