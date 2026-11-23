#!/usr/bin/env bash
# One-time setup: put your name, GitHub username and site address into the starter files.
#
#   ./scripts/personalize.sh "Ada Lovelace" adalovelace                 # repo named adalovelace.github.io
#   ./scripts/personalize.sh "Ada Lovelace" adalovelace my-website      # repo named my-website
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -lt 2 ]; then
  echo "usage: $0 \"Your Name\" your-github-username [repository-name]" >&2
  exit 1
fi

NAME="$1"
GH_USER="$2"
REPO="${3:-$GH_USER.github.io}"

# Address of your "person" tree, e.g. "Ada Lovelace" -> adalovelace
SLUG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cd 'a-z0-9')"
# Prefix for new note addresses, e.g. "Ada Lovelace" -> al  (notes become al-0001, al-0002, ...)
PREFIX="$(printf '%s' "$NAME" | awk '{for (i = 1; i <= NF; i++) printf "%s", tolower(substr($i, 1, 1))}' | LC_ALL=C tr -cd 'a-z0-9')"
[ -n "$SLUG" ] || SLUG="me"
[ -n "$PREFIX" ] || PREFIX="note"

if [ "$REPO" = "$GH_USER.github.io" ]; then
  URL="https://$GH_USER.github.io/"
else
  URL="https://$GH_USER.github.io/$REPO/"
fi

# sed -i differs between macOS and Linux; this form works on both.
replace() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

# Escape characters that are special in sed replacements.
NAME_ESC="$(printf '%s' "$NAME" | sed 's/[&|\\]/\\&/g')"

for f in trees/*.tree forest.toml; do
  replace "s|YOUR NAME|$NAME_ESC|g" "$f"
  replace "s|YOUR-GITHUB-USERNAME|$GH_USER|g" "$f"
  replace "s|(yourname)|($SLUG)|g; s|{yourname}|{$SLUG}|g" "$f"
done
replace "s|^url = .*|url = \"$URL\"|" forest.toml

if [ -f trees/yourname.tree ] && [ "$SLUG" != "yourname" ]; then
  mv trees/yourname.tree "trees/$SLUG.tree"
fi

cat > scripts/config.sh <<EOF
# Written by personalize.sh; used by scripts/new.sh
AUTHOR="$SLUG"
PREFIX="$PREFIX"
EOF

echo "Done."
echo "  Your page:        trees/$SLUG.tree"
echo "  New notes will be named $PREFIX-0001, $PREFIX-0002, ..."
echo "  Site address:     $URL"
echo "  GitHub repository to create: $GH_USER/$REPO"
