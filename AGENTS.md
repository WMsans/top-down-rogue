# AGENTS.md

## Running tests (gdUnit4)

Tests run headless via the gdUnit4 command tool:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```

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
