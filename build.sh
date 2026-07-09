#!/usr/bin/env bash
# Builds the CurseForge release zip: NextCast-<version>.zip in the parent
# directory, containing the addon folder without dev files (assets,
# build script, git internals).
set -euo pipefail

cd "$(dirname "$0")"
VERSION=$(grep -m1 "^## Version:" NextCast.toc | sed 's/.*: *//' | tr -d '[:space:]')
[ -n "$VERSION" ] || { echo "ERROR: no ## Version: in NextCast.toc" >&2; exit 1; }

FOLDER=$(basename "$PWD")
OUT="NextCast-${VERSION}.zip"

cd ..
rm -f "$OUT"
zip -rq "$OUT" "$FOLDER" \
    -x "$FOLDER/assets/*" \
    -x "$FOLDER/build.sh" \
    -x "$FOLDER/CURSEFORGE.md" \
    -x "$FOLDER/CLAUDE.md" \
    -x "$FOLDER/.git/*" \
    -x "$FOLDER/.gitignore" \
    -x "*.DS_Store"

echo "Built $(pwd)/$OUT"
unzip -l "$OUT"
