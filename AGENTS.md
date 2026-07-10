# AGENTS.md

## Running tests (gdUnit4)

### Import the project first in fresh worktrees

The `.godot/` import cache is gitignored, so it is **not** shared across git
worktrees — each working tree needs its own. A newly created worktree has no
`.godot/`, and without it Godot can't resolve imported assets (textures, scenes,
`.uid` references), so test runs fail before any test executes.

Generate the cache once per worktree (idempotent and fast once it exists):

```bash
godot --headless --path . --import
```

To make a run self-contained, prepend the import step:

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```

### Preferred: use `addons/gdUnit4/runtest.sh`
Tests run headless via the gdUnit4 command tool: `addons/gdUnit4/runtest.sh`

There's a wrapper script that handles the flags above for you. It needs the
`GODOT_BIN` env var set (find the binary with `which godot`), and the `-a`
path is relative (no `res://` prefix, no leading `tests/unit/` vs `tests/`
ambiguity — just the real repo-relative path):

```bash
GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_dash_fire_vfx.gd
```

Run it in the foreground and wait for it — headless Godot boot + full autoload
chain takes ~30-60s before any test output appears, so don't assume a quiet
first minute means it hung. Without `GODOT_BIN` it fails fast with a clear
"Godot binary path is not specified" error, not a hang.

A crash with `Nonexistent function 'new' in base 'GDScript'` on the class
under test almost always means that script (or one it depends on) failed to
parse — scroll up in the output for the actual `SCRIPT ERROR: Parse Error`
line rather than chasing the misleading `Nil`/`GDScript` message. In
particular, `const` arrays must use typed-literal syntax
(`const X: Array[Vector2] = [...]`), not a constructor call
(`const X := PackedVector2Array([...])`) — the latter fails to parse as a
constant expression in GDScript 4.
