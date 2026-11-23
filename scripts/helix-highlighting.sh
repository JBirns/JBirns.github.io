#!/usr/bin/env bash
# Optional: syntax colouring for .tree files in Helix, using the community tree-sitter grammar
# by Kento Okura (https://github.com/kentookura/tree-sitter-forester).
# The language server and live preview work without this; it only adds colours.
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/helix"
REV="4b1c6828cc77c62750302e1a9582dc098d74e227"
mkdir -p "$CONFIG/runtime/queries/forester"

if ! grep -q 'name = "forester"' "$CONFIG/languages.toml" 2>/dev/null; then
  cat >> "$CONFIG/languages.toml" <<EOF

[[grammar]]
name = "forester"
source = { git = "https://github.com/kentookura/tree-sitter-forester", rev = "$REV" }
EOF
  echo "Added the forester grammar to $CONFIG/languages.toml"
fi

hx --grammar fetch
hx --grammar build

curl -fsSL "https://raw.githubusercontent.com/kentookura/tree-sitter-forester/$REV/queries/highlights.scm" \
  -o "$CONFIG/runtime/queries/forester/highlights.scm"

echo "Done. Restart Helix and open a .tree file."
