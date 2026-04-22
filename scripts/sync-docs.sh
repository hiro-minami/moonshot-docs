#!/bin/bash
set -euo pipefail

# Sync docs from moonshot main repo to Starlight content directory
# Usage: ./scripts/sync-docs.sh

REPO="hiro-minami/moonshot"
TEMP_DIR=$(mktemp -d)
CONTENT_DIR="src/content/docs"

# Use token auth for private repo when available
if [[ -n "${MOONSHOT_TOKEN:-}" ]]; then
  REPO_URL="https://x-access-token:${MOONSHOT_TOKEN}@github.com/${REPO}.git"
else
  REPO_URL="https://github.com/${REPO}.git"
fi

echo "📥 Cloning moonshot docs..."
git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" "$TEMP_DIR"
cd "$TEMP_DIR"
git sparse-checkout set docs/adr docs/design
cd -

echo "📝 Syncing ADR files..."
for f in "$TEMP_DIR"/docs/adr/[0-9]*.md; do
  basename=$(basename "$f")
  title=$(head -1 "$f" | sed 's/^# //')
  {
    echo "---"
    echo "title: \"$title\""
    echo "---"
    echo ""
    tail -n +2 "$f"
  } > "$CONTENT_DIR/adr/$basename"
  echo "  ✓ $basename"
done

echo "📝 Syncing Design Doc files..."
for f in "$TEMP_DIR"/docs/design/*.md; do
  basename=$(basename "$f")
  title=$(head -1 "$f" | sed 's/^# //')
  {
    echo "---"
    echo "title: \"$title\""
    echo "---"
    echo ""
    # Fix ADR links: ../adr/xxx.md → ../adr/xxx/
    tail -n +2 "$f" | sed 's|\.\./adr/\([0-9a-z-]*\)\.md|../adr/\1/|g'
  } > "$CONTENT_DIR/design/$basename"
  echo "  ✓ $basename"
done

rm -rf "$TEMP_DIR"
echo "✅ Sync complete!"
