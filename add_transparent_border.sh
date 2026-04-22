#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <folder> [border_size]"
    echo "  folder      - path to folder containing images"
    echo "  border_size - number of transparent pixels to add (default: 1)"
    exit 1
fi

FOLDER="$1"
BORDER="${2:-1}"

if [ ! -d "$FOLDER" ]; then
    echo "Error: '$FOLDER' is not a directory"
    exit 1
fi

shopt -s nullglob
FILES=("$FOLDER"/*.png)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No .png files found in '$FOLDER'"
    exit 1
fi

for f in "${FILES[@]}"; do
    echo "Processing: $f"
    magick "$f" -bordercolor none -border "${BORDER}x${BORDER}" "$f"
done

echo "Done. Processed ${#FILES[@]} file(s)."
