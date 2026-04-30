# Step 1 — Bootstrap godot-cpp Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a godot-cpp GDExtension skeleton that builds and loads in Godot 4.6 on both macOS and Arch Linux, with a single shared library (`libtoprogue`), a SCons-based build, and a wrapper script (`build.sh`). No game logic is ported in this step — the extension registers zero classes. The deliverable is a working build/load loop that all subsequent migration steps depend on.

**Architecture:** A new top-level `gdextension/` directory holds C++ source, a godot-cpp git submodule, and a `SConstruct`. A platform-detecting `build.sh` wraps SCons. Output binaries land in `bin/lib/` (gitignored). A `bin/toprogue.gdextension` manifest declares the entry symbol and per-platform binary paths. Godot detects the manifest at editor launch and loads the (empty) extension.

**Tech Stack:** godot-cpp (4.x branch matching Godot 4.6), SCons, C++17, Apple clang on macOS, gcc/clang on Arch Linux.

---

## Required Reading Before Starting

You **must** read both of these before writing any code. They define everything this plan implements (and what later plans will implement).

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. The full design lives there. Sections most relevant to Step 1: §4 (Architecture / layout), §5 (Build System & Toolchain), §9.1 step 1 (this step's place in the migration). Sections you don't need to act on yet but should skim for context: §6 (Cellular Simulation), §7 (Materials), §8 (Generation, Collider, Rendering Bridge).

2. **godot-cpp official docs:** https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/gdextension_cpp_example.html and the `gdextension/godot-cpp/README.md` after the submodule is added. The "GDExtension C++ example" page is the canonical reference for the SConstruct + manifest layout we're following.

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate.

## What Comes After Step 1 (Read This)

Step 1 is the first of 8 migration steps defined in spec §9.1. The other 7 will each get their own plan, written at the time that step starts (not now). The reason is that each step's plan needs to reference real C++ class signatures and file paths created by the previous steps; writing all 8 plans up front would lock in details that should emerge during the earlier work.

**Map of which spec sections drive which migration step's future plan:**

| Step | Plan filename to use when written | Spec sections to read |
|---|---|---|
| 2. `MaterialTable` | `2026-XX-XX-step-2-material-table.md` | §3.1, §3.2, §7, §9.1 step 2 |
| 3. Resources | `2026-XX-XX-step-3-resources.md` | §3.2, §9.1 step 3, §9.3 (`.tres` migration) |
| 4. Leaves (`Chunk`, `SectorGrid`, `GenerationContext`) | `2026-XX-XX-step-4-leaves.md` | §6.1 (Cell layout), §3.2, §9.1 step 4 |
| 5. ColliderBuilder + physics | `2026-XX-XX-step-5-collider-physics.md` | §8.3, §8.5–§8.7, §9.1 step 5 |
| 6. Generator + SimplexCaveGenerator | `2026-XX-XX-step-6-generator.md` | §8.1, §8.2, §8.4, §9.1 step 6 |
| 7. Simulator + ChunkManager + WorldManager + TerrainModifier | `2026-XX-XX-step-7-simulator.md` | §6 in full, §8.5, §8.6, §9.1 step 7 |
| 8. Cleanup | `2026-XX-XX-step-8-cleanup.md` | §3.1, §9.1 step 8, §10.2 verification, §11 done definition |

**How to write the plan for step N once step N−1 has merged:**

1. Confirm step N−1 is fully merged on `refactor/cpp` and the game launches/plays.
2. Read spec §9.1 step N to understand the goal and deliverables.
3. Read the spec sections listed in the table above for that step.
4. Read the C++ files step N−1 created (under `gdextension/src/`) to ground the plan in real signatures, not guesses.
5. Invoke the `writing-plans` skill with: *"Write the plan for migration step N (see spec §9.1 step N at `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`). Predecessor (step N−1) is merged; its source is under `gdextension/src/`."*
6. Save the resulting plan to `docs/superpowers/plans/YYYY-MM-DD-step-N-<topic>.md` and commit before starting implementation.

**Do not** implement step N's work using the *spec* alone as guidance. The plans exist to break each step into bite-sized tasks; skipping the plan-writing pass means you lose the bite-sized structure and will probably skip TDD.

## Conventions Used in This Plan

- All paths are relative to the repo root: `/Users/jeremyzhao/Development/godot/top-down-rogue`.
- Shell commands assume `cwd` = repo root unless stated otherwise.
- "Run on both machines" means: do the same step on macOS first, then `git pull` on Arch and verify there. Step 1 is the only place you touch each machine; later steps trust the build is working on both.
- Commit after every task. Granular history is the rollback mechanism.

## File Structure (created in this plan)

```
top-down-rogue/
├── gdextension/                                    NEW — top-level for all C++
│   ├── godot-cpp/                                  NEW — git submodule (not committed source, just the pin)
│   ├── src/
│   │   └── register_types.cpp                      NEW — empty registration entry point
│   ├── SConstruct                                  NEW — SCons build file
│   ├── build.sh                                    NEW — platform-detecting wrapper
│   ├── format.sh                                   NEW — clang-format helper
│   └── .clang-format                               NEW — copied from godot-cpp
├── bin/
│   └── toprogue.gdextension                        NEW — extension manifest
└── .gitignore                                      MODIFIED — add bin/lib/, godot-cpp build outputs, SCons cache
```

**File responsibilities:**

- `gdextension/SConstruct` — orchestrates the build: invokes godot-cpp's own SConstruct to produce the bindings library, then compiles `gdextension/src/*.cpp` against those bindings into `libtoprogue.<platform>.<target>.<arch>.{dylib,so}`.
- `gdextension/src/register_types.cpp` — implements the GDExtension entry point (`toprogue_library_init` / `toprogue_library_deinit`) and the per-init-level callbacks. In Step 1 these are empty. Step 2+ will register classes here.
- `gdextension/build.sh` — wraps SCons with platform/arch/jobcount auto-detection. Subcommands: `debug`, `release`, `clean`, `both`.
- `gdextension/format.sh` — runs `clang-format -i` over `gdextension/src/`.
- `gdextension/.clang-format` — code style; copied verbatim from `gdextension/godot-cpp/.clang-format` after the submodule is added.
- `bin/toprogue.gdextension` — declares the extension name, entry symbol, compatibility floor (4.6), and per-platform binary paths under `bin/lib/`.
- `.gitignore` — keeps build output and SCons cache out of git.

`bin/lib/` is intentionally **not** created or committed. Each developer builds locally after `git pull`.

---

## Task 1: Add godot-cpp as a git submodule

**Files:**
- Create: `gdextension/godot-cpp/` (via submodule add)
- Modify: `.gitmodules` (created automatically by `git submodule add`)

- [ ] **Step 1: Create the gdextension directory**

```bash
mkdir -p gdextension
```

- [ ] **Step 2: Add the godot-cpp submodule pinned to the 4.x branch matching Godot 4.6**

```bash
git submodule add -b 4.x https://github.com/godotengine/godot-cpp.git gdextension/godot-cpp
git submodule update --init --recursive
```

Expected: `gdextension/godot-cpp/` populated; `.gitmodules` created with the entry. The branch `4.x` tracks the latest 4.6-compatible release line; if `git submodule add` complains the branch doesn't exist, use `master` instead (the maintainers have renamed branches before; the spec pins by SHA, not branch name).

- [ ] **Step 3: Pin the submodule to a specific commit and record it in the spec**

```bash
cd gdextension/godot-cpp
git log -1 --format="%H %s"
cd ../..
```

Copy the printed SHA. Append the following note to the spec at `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`, under §5.3 Pins, replacing the existing "godot-cpp pinned to a specific commit" sentence with the actual SHA:

```markdown
godot-cpp pinned to commit `<paste-sha-here>` (4.x branch as of bootstrap). Submodule SHA recorded in this repo at `gdextension/godot-cpp`.
```

- [ ] **Step 4: Verify the submodule builds godot-cpp's own bindings (smoke test only — discard output)**

```bash
cd gdextension/godot-cpp
scons platform=$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/') target=template_debug -j4
cd ../..
```

Expected: SCons compiles `godot-cpp/gen/` bindings (1–3 minutes first time). If it fails, you have a toolchain issue — install Xcode CLT (mac) or `base-devel` (Arch) before continuing. Discard the build output; the real build is driven from `gdextension/SConstruct` in Task 3.

- [ ] **Step 5: Commit**

```bash
git add .gitmodules gdextension/godot-cpp docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md
git commit -m "chore: add godot-cpp 4.x submodule for GDExtension"
```

---

## Task 2: Write the empty `register_types.cpp` entry point

**Files:**
- Create: `gdextension/src/register_types.cpp`
- Create: `gdextension/src/register_types.h`

- [ ] **Step 1: Create the header**

Create `gdextension/src/register_types.h`:

```cpp
#pragma once

#include <godot_cpp/godot.hpp>

void initialize_toprogue_module(godot::ModuleInitializationLevel p_level);
void uninitialize_toprogue_module(godot::ModuleInitializationLevel p_level);
```

- [ ] **Step 2: Create the entry point implementation**

Create `gdextension/src/register_types.cpp`:

```cpp
#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    // Step 1 (bootstrap): no classes registered yet.
    // Step 2 onward will register MaterialTable, then resources, then terrain classes.
}

void uninitialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT toprogue_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_toprogue_module);
    init_obj.register_terminator(uninitialize_toprogue_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}
}
```

The `extern "C"` symbol `toprogue_library_init` is what `bin/toprogue.gdextension` will reference as the entry symbol in Task 5. The name is load-bearing — match it exactly.

- [ ] **Step 3: Commit**

```bash
git add gdextension/src/register_types.h gdextension/src/register_types.cpp
git commit -m "feat: add empty GDExtension entry point"
```

---

## Task 3: Write the SConstruct

**Files:**
- Create: `gdextension/SConstruct`

- [ ] **Step 1: Create `gdextension/SConstruct`**

```python
#!/usr/bin/env python
import os
import sys

# Use godot-cpp's own SConstruct as a tool to set up the build environment.
env = SConscript("godot-cpp/SConstruct")

# Sources for our extension.
env.Append(CPPPATH=["src/"])
sources = Glob("src/*.cpp")

# Output filename pattern:
# libtoprogue.<platform>.<target>.<arch>.<ext>
# e.g. libtoprogue.macos.template_debug.arm64.dylib
#      libtoprogue.linux.template_debug.x86_64.so
output_dir = "#bin/lib"
filename = "libtoprogue{}{}".format(env["suffix"], env["SHLIBSUFFIX"])
library = env.SharedLibrary(
    target=os.path.join(output_dir, filename),
    source=sources,
)

Default(library)
```

The `env["suffix"]` token (set by godot-cpp's SConstruct based on `platform`, `target`, `arch`, `dev_build`) produces the platform-specific portion of the filename automatically. We don't construct it by hand.

- [ ] **Step 2: Test-build for the host platform**

```bash
cd gdextension
scons platform=$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/') target=template_debug dev_build=yes -j4
cd ..
```

Expected (macOS arm64): file `bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib` exists. (If your Mac is Intel, replace `arm64` with `x86_64`.)
Expected (Arch x86_64): file `bin/lib/libtoprogue.linux.template_debug.dev.x86_64.so` exists.

If the build fails with "godot-cpp is not built yet": run `cd gdextension/godot-cpp && scons platform=<platform> target=template_debug -j4` once first to produce its bindings library, then retry. (godot-cpp's SConstruct caches into its own tree; this is one-time per platform/target combination.)

- [ ] **Step 3: Verify the .dylib / .so loads as a Mach-O / ELF object**

On macOS:
```bash
file bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib
```
Expected: `Mach-O 64-bit dynamically linked shared library arm64`.

On Arch:
```bash
file bin/lib/libtoprogue.linux.template_debug.dev.x86_64.so
```
Expected: `ELF 64-bit LSB shared object, x86-64, ...`.

- [ ] **Step 4: Commit**

```bash
git add gdextension/SConstruct
git commit -m "feat: add SConstruct for godot-cpp extension build"
```

---

## Task 4: Write the `build.sh` wrapper

**Files:**
- Create: `gdextension/build.sh`

- [ ] **Step 1: Create the script**

Create `gdextension/build.sh`:

```bash
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
        scons --clean platform="$PLATFORM" arch="$ARCH" target=template_debug || true
        scons --clean platform="$PLATFORM" arch="$ARCH" target=template_release || true
        ;;
    *)
        echo "Usage: $0 {debug|release|clean|both}" >&2
        exit 1
        ;;
esac
```

- [ ] **Step 2: Make executable and run debug build via wrapper**

```bash
chmod +x gdextension/build.sh
./gdextension/build.sh debug
```

Expected: same output as Task 3 step 2, plus a leading toolchain version block. The build should be a fast no-op since Task 3 already produced the binary.

- [ ] **Step 3: Run release build via wrapper**

```bash
./gdextension/build.sh release
```

Expected: produces `libtoprogue.<platform>.template_release.<arch>.{dylib,so}` in `bin/lib/`.

- [ ] **Step 4: Run clean and verify**

```bash
./gdextension/build.sh clean
ls bin/lib/ 2>/dev/null || echo "bin/lib/ removed/empty (ok)"
```

Expected: `bin/lib/` is empty or absent. (SCons may leave the directory empty; that's fine.)

- [ ] **Step 5: Rebuild debug for the next tasks**

```bash
./gdextension/build.sh debug
```

- [ ] **Step 6: Commit**

```bash
git add gdextension/build.sh
git commit -m "feat: add platform-detecting build.sh wrapper"
```

---

## Task 5: Write the `.gdextension` manifest

**Files:**
- Create: `bin/toprogue.gdextension`

- [ ] **Step 1: Create the manifest**

Create `bin/toprogue.gdextension`:

```ini
[configuration]

entry_symbol = "toprogue_library_init"
compatibility_minimum = "4.6"

[libraries]

macos.template_debug.arm64       = "res://bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib"
macos.template_release.arm64     = "res://bin/lib/libtoprogue.macos.template_release.arm64.dylib"
macos.template_debug.x86_64      = "res://bin/lib/libtoprogue.macos.template_debug.dev.x86_64.dylib"
macos.template_release.x86_64    = "res://bin/lib/libtoprogue.macos.template_release.x86_64.dylib"
linux.template_debug.x86_64      = "res://bin/lib/libtoprogue.linux.template_debug.dev.x86_64.so"
linux.template_release.x86_64    = "res://bin/lib/libtoprogue.linux.template_release.x86_64.so"
```

The exact filename suffixes (`.dev.arm64.dylib` etc.) must match what godot-cpp's SConstruct produces. After Task 3 you should have a real file in `bin/lib/` — if its name differs from any of the lines above, edit the manifest to match. The pattern is `libtoprogue<env_suffix><SHLIBSUFFIX>` from the SConstruct.

- [ ] **Step 2: Verify the path on the manifest's first line resolves to a real file (debug, host platform)**

On macOS arm64:
```bash
ls -la bin/lib/libtoprogue.macos.template_debug.dev.arm64.dylib
```

On Arch x86_64:
```bash
ls -la bin/lib/libtoprogue.linux.template_debug.dev.x86_64.so
```

Expected: file exists. If not, the SCons output filename doesn't match the manifest — fix the manifest to match the real filename.

- [ ] **Step 3: Open the project in the Godot 4.6 editor and confirm the extension loads**

Launch Godot 4.6, open the project at `/Users/jeremyzhao/Development/godot/top-down-rogue`, and watch the editor's bottom-panel **Output** log on first open.

Expected: no errors mentioning `toprogue` or `GDExtension`. Specifically, no "Could not open library", no "Cannot resolve symbol toprogue_library_init", no "Compatibility too low".

If you see "Cannot find binary for current platform": the manifest path doesn't match the on-disk file. Re-check Task 5 step 2.

If you see "Symbol not found: toprogue_library_init": the `extern "C"` block in `register_types.cpp` is missing or the symbol got mangled. Re-check Task 2 step 2.

If you see "compatibility_minimum is greater than current engine version": confirm the editor is 4.6 (Help → About).

- [ ] **Step 4: Close the editor and commit**

```bash
git add bin/toprogue.gdextension
git commit -m "feat: add .gdextension manifest for toprogue extension"
```

---

## Task 6: Add `.gitignore` entries and verify nothing dirty leaks into git

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Read the current `.gitignore`**

```bash
cat .gitignore
```

Note what's already there. The new entries below need to be appended; do not duplicate existing rules.

- [ ] **Step 2: Append godot-cpp / SCons / build-output entries**

Append these lines to `.gitignore` (skip any that already exist):

```
# godot-cpp GDExtension build outputs
bin/lib/
gdextension/godot-cpp/bin/
gdextension/godot-cpp/gen/

# SCons
.sconsign.dblite
.sconf_temp/
config.log
*.o
*.os
*.obj
```

- [ ] **Step 3: Verify `git status` is clean of build artifacts**

```bash
git status
```

Expected: `bin/lib/`, `gdextension/godot-cpp/bin/` (if present), and any `*.o`/`.sconsign.dblite` files do **not** appear in the output. If they do, the `.gitignore` rule didn't take effect — check for path-prefix mistakes.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore godot-cpp build artifacts and SCons cache"
```

---

## Task 7: Add `.clang-format` and `format.sh`

**Files:**
- Create: `gdextension/.clang-format`
- Create: `gdextension/format.sh`

- [ ] **Step 1: Copy godot-cpp's clang-format**

```bash
cp gdextension/godot-cpp/.clang-format gdextension/.clang-format
```

- [ ] **Step 2: Create `gdextension/format.sh`**

```bash
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
```

- [ ] **Step 3: Make executable and run it**

```bash
chmod +x gdextension/format.sh
./gdextension/format.sh
```

Expected: prints `Formatted 2 file(s).` (`register_types.cpp`, `register_types.h`).

- [ ] **Step 4: Verify formatting did not break the build**

```bash
./gdextension/build.sh debug
```

Expected: incremental build succeeds (likely no recompile needed if formatting was a no-op).

- [ ] **Step 5: Commit**

```bash
git add gdextension/.clang-format gdextension/format.sh gdextension/src/
git commit -m "chore: add clang-format config and format.sh helper"
```

---

## Task 8: Cross-machine verification

This task is the only point where dual-machine validation matters; later steps trust that what worked on one machine works on the other.

- [ ] **Step 1: Push to remote on the machine you've been working on**

```bash
git push origin refactor/cpp
```

- [ ] **Step 2: On the other machine, pull and init the submodule**

```bash
git pull
git submodule update --init --recursive
```

Expected: `gdextension/godot-cpp/` populated at the same SHA pinned in Task 1 step 3.

- [ ] **Step 3: On the other machine, run a clean build**

```bash
./gdextension/build.sh debug
```

Expected: produces the platform-correct binary in `bin/lib/`. (E.g., if the first machine was macOS, the second is Arch and produces a `.so` rather than the `.dylib` from machine 1. The `.gdextension` manifest already contains entries for both.)

- [ ] **Step 4: On the other machine, open the project in Godot 4.6 and confirm clean load**

Same expectations as Task 5 step 3.

- [ ] **Step 5: No commit needed for this task.** The deliverable is the verification, not a code change. If anything went wrong, fix it in a follow-up task and commit that fix.

---

## Task 9: Update the project README (or create a build note) so future contributors know the build steps

**Files:**
- Modify or Create: `gdextension/README.md`

- [ ] **Step 1: Check whether a top-level README exists**

```bash
ls README.md 2>/dev/null || echo "no top-level README"
```

If a top-level `README.md` exists, you'll add a small "Building the GDExtension" section to it. If not, create `gdextension/README.md` instead. The decision: keep build instructions next to the code they describe (`gdextension/README.md`), reference it from the top-level README only if one exists.

- [ ] **Step 2: Create `gdextension/README.md`**

```markdown
# GDExtension (godot-cpp)

This directory holds the C++ GDExtension that replaces the project's compute
shaders and hot-path GDScript with native code. See the design spec at
`docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md` for
full context.

## First-time setup

After cloning the repo:

```bash
git submodule update --init --recursive
```

This fetches `godot-cpp/` (the official C++ bindings) at the SHA this repo pins.

### macOS

```bash
xcode-select --install            # if not already installed
pip install scons                 # SCons build system
```

### Arch Linux

```bash
sudo pacman -S base-devel scons python
```

## Building

```bash
./gdextension/build.sh debug      # development build (assertions, -O0)
./gdextension/build.sh release    # optimized build
./gdextension/build.sh both       # both debug and release
./gdextension/build.sh clean      # remove build artifacts
```

Output binaries land in `bin/lib/` (gitignored). The `.gdextension` manifest
at `bin/toprogue.gdextension` tells Godot which file to load per platform.

After a successful build, open the project in Godot 4.6 — the extension
loads automatically.

## When to rebuild

After every C++ change, and after every `git pull` that touched
`gdextension/`. Each developer's machine builds locally; binaries are not
committed.

## Formatting

```bash
./gdextension/format.sh
```
```

- [ ] **Step 3: Commit**

```bash
git add gdextension/README.md
git commit -m "docs: add build instructions for the GDExtension"
```

---

## Final verification

- [ ] **Step 1: Confirm the working tree is clean**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

- [ ] **Step 2: Confirm the build still produces the binary**

```bash
./gdextension/build.sh debug
ls bin/lib/
```

Expected: at least one `libtoprogue.*.{dylib,so}` file present.

- [ ] **Step 3: Confirm the editor still opens the project cleanly**

Launch Godot 4.6 → open the project → check Output log. No `toprogue` / `GDExtension` errors.

- [ ] **Step 4: Confirm the gdUnit4 tests still pass (sanity check, since we changed nothing they depend on)**

Run the `gdUnit4` suite via the editor's Test panel (or the `gdUnit4` CLI if you've set that up). All tests should pass — Step 1 added zero game-logic changes.

- [ ] **Step 5: Push the branch**

```bash
git push origin refactor/cpp
```

---

## Done definition for Step 1

- `gdextension/godot-cpp/` exists as a git submodule pinned to a specific SHA recorded in the spec.
- `gdextension/build.sh debug` succeeds on macOS and Arch Linux.
- `bin/lib/libtoprogue.<platform>.template_debug.dev.<arch>.{dylib,so}` exists after a debug build.
- `bin/toprogue.gdextension` references that binary and Godot 4.6 loads it without errors on both machines.
- `bin/lib/` and SCons artifacts are gitignored.
- `gdUnit4` test suite still passes (zero regressions).
- The game still launches and plays as before — Step 1 added zero classes, so nothing about runtime behavior changed.

When all of the above are true, Step 1 is complete and you may proceed to write the plan for **Step 2 — `MaterialTable`** following the instructions in the "What Comes After Step 1" section at the top of this document.
