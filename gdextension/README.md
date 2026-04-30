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
