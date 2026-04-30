#!/usr/bin/env bash
# Run clang-format -i over all C++ sources under gdextension/src/.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v clang-format >/dev/null 2>&1; then
    echo "clang-format not installed. macOS: brew install clang-format. Arch: pacman -S clang." >&2
    exit 1
fi

find src -type f \( -name "*.cpp" -o -name "*.h" \) -print0 \
    | xargs -0 clang-format -i --style=file
echo "Formatted $(find src -type f \( -name '*.cpp' -o -name '*.h' \) | wc -l | tr -d ' ') file(s)."
