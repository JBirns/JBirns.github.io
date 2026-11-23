#!/usr/bin/env bash
# Build the site, serve it at http://localhost:1313, and rebuild whenever you save a file.
# (Editors that talk to Forester's language server, such as Helix or Neovim, also get an
#  instant live preview at http://localhost:8080 without this script.)
set -uo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-1313}"

command -v forester >/dev/null || { echo "forester not found: see README.md, step 1" >&2; exit 1; }

build() {
  if forester build; then
    echo "[$(date +%H:%M:%S)] built"
  else
    echo "[$(date +%H:%M:%S)] build FAILED (see the messages above); fix and save again"
  fi
}

# Forester puts the site under output/<path of the url>/ when the url has a path.
site_path() {
  python3 - <<'EOF'
import re
m = re.search(r'^\s*url\s*=\s*"([^"]*)"', open("forest.toml").read(), re.M)
from urllib.parse import urlparse
print(urlparse(m.group(1)).path.strip("/") if m else "")
EOF
}

build
SUB="$(site_path)"
if [ -n "$SUB" ] && [ -f "output/$SUB/index.html" ]; then LINK="http://localhost:$PORT/$SUB/"; else LINK="http://localhost:$PORT/"; fi

python3 -m http.server "$PORT" -d output >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT

echo
echo "Preview: $LINK   (refresh the browser after saving; Ctrl+C to stop)"
echo

snapshot() { ls -lR trees assets forest.toml 2>/dev/null | cksum; }
last="$(snapshot)"
while sleep 1; do
  now="$(snapshot)"
  if [ "$now" != "$last" ]; then
    last="$now"
    build
  fi
done
