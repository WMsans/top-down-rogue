#!/usr/bin/env bash
# Wrapper around scons for the toprogue GDExtension.
# Auto-detects platform, arch, and job count.
# Usage: ./build.sh {debug|release|clean|both}

set -euo pipefail

# Detect platform.
case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *)      echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

# Detect arch.
case "$(uname -m)" in
    arm64|aarch64) ARCH="arm64" ;;
    x86_64)        ARCH="x86_64" ;;
    *)             echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

# Detect job count.
if [[ "$PLATFORM" == "macos" ]]; then
    JOBS="$(sysctl -n hw.ncpu)"
else
    JOBS="$(nproc)"
fi

# Resolve script directory (so this works from any cwd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Log toolchain versions (so a busted Arch update leaves a fingerprint).
echo "===== build.sh: toolchain ====="
echo "platform=$PLATFORM arch=$ARCH jobs=$JOBS"
echo -n "scons: "; scons --version | head -1
echo -n "python: "; python3 --version
if command -v clang >/dev/null 2>&1; then echo -n "clang: "; clang --version | head -1; fi
if command -v gcc   >/dev/null 2>&1; then echo -n "gcc: ";   gcc   --version | head -1; fi
echo "==============================="

run_scons() {
    local target="$1"; shift
    scons platform="$PLATFORM" arch="$ARCH" target="$target" "$@" -j"$JOBS"
}

case "${1:-debug}" in
    debug)
        run_scons template_debug dev_build=yes debug_symbols=yes
        ;;
    release)
        run_scons template_release debug_symbols=yes
        ;;
    both)
        run_scons template_debug dev_build=yes debug_symbols=yes
        run_scons template_release debug_symbols=yes
        ;;
    clean)
        scons --clean platform="$PLATFORM" arch="$ARCH" target=template_debug dev_build=yes || true
        scons --clean platform="$PLATFORM" arch="$ARCH" target=template_release || true
        ;;
    *)
        echo "Usage: $0 {debug|release|clean|both}" >&2
        exit 1
        ;;
esac
