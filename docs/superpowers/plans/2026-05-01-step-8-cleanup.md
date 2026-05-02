# Step 8 — Final Cleanup & Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the godot-cpp hot-path port by sweeping every straggler the per-feature steps left behind, then proving the spec's full Done Definition (§11) holds. Step 7's commit (`refactor: delete simulation shaders, compute_device, world_preview, transitional GPU hacks`) already nuked the bulk of the deletion list — the shader directories, `compute_device.gd`, `world_preview.gd`, `comp.spv`, and `generate_materials.sh` are gone. What remains is **the audit**: hunt down stale `.uid` files, dead editor plugins, comment references to deleted classes, leftover entries in `project.godot` / `.gitignore` / `tools/`, and confirm by grep + smoke-test that the post-condition described in spec §11 is reality, not aspiration. No new C++ in this step. No new public surface in this step. The branch ships when this step lands.

**Architecture:** None new. Every class registered in `register_types.cpp` keeps its current shape; no scenes change unless a stale script reference is found. The work is entirely deletions + greps + a final cross-platform smoke test.

**Tech Stack:** Existing `gdextension/build.sh`, gdUnit4, Godot 4.6 editor. No new tooling.

---

## Required Reading Before Starting

You **must** read all of these before deleting anything.

1. **Spec:** `docs/superpowers/specs/2026-04-30-godot-cpp-hot-path-port-design.md`. Mandatory sections:
   - §3.1 — full deletion list. Every entry must be gone after this step. Re-grep each one; do not assume step 7 finished the job.
   - §3.4 — non-goals. **No new public methods, signals, or properties.** This step deletes; it does not add. Resist the urge to "tidy up" by introducing helpers, renaming surfaces, or refactoring callsites that still work.
   - §9.1 step 8 — the canonical step 8 description: "Delete `world_preview.gd` + `.uid` + preview wiring. Confirm `shaders/compute/` and `shaders/include/` are empty; remove the directories. Final grep for `RenderingDevice`, `RDShaderFile`, `compute_list`, `push_constant` to confirm zero hits in `src/` and `gdextension/src/`." Step 7 did most of this; step 8 is the verifying sweep + the stragglers (editor plugin, `.uid` orphans, stale comments, `tools/` cruft).
   - §10.2 — verification gates. Every grep listed there is the contract this step must satisfy.
   - §11 — Done Definition. Print this list. Tick every bullet by command output, not by memory.

2. **Step 7's plan + commit:** `docs/superpowers/plans/2026-05-01-step-7-simulator.md` (Task 13 + Task 14) and `git show 583a942 --stat`. Step 7's Task 14 already ran most of the spec §10.2 greps; this step re-runs them on the merged tree to confirm nothing regressed during merge, then extends the audit to areas Task 14 didn't cover (editor plugins, `tools/`, `tests/`, `addons/`, `.gitignore`, `project.godot`'s non-autoload sections).

3. **Pre-flight inventory of known stragglers** (audit done at plan-write time; treat as a starting list, not exhaustive):
   - `addons/level_preview/` — editor plugin that references the deleted `WorldPreview` class. Dead. Plugin entry in `project.godot`'s `[editor_plugins]` line still enables it; loading the editor will throw a parse error on `WorldPreview`. Must go.
   - `tools/texture_array_builder.gd.uid` — orphaned `.uid` whose `.gd` was deleted earlier in the refactor. Must go.
   - `tools/generate_room_templates.gd:11` — comment "must match MaterialRegistry order; cannot import the autoload" references the deleted `MaterialRegistry`. Update to `MaterialTable` (the C++ singleton replaced it in step 2).
   - Any `.uid` file in `tools/`, `src/`, `tests/`, or `addons/` whose corresponding `.gd` no longer exists.
   - `project.godot` `[editor_plugins]` array — remove the `level_preview` entry once the addon is deleted.
   - Any documentation under `docs/` (excluding `docs/superpowers/specs/` and `docs/superpowers/plans/` — those are historical record) that describes the GPU pipeline as live. Comments-only updates; do not rewrite ADRs.

If anything in this plan conflicts with the spec, the spec wins — flag the conflict and stop, do not silently deviate.

## What This Step Does NOT Do

- **Does not** add new C++ classes, methods, signals, or properties (per §3.4 #1). Step 7 closed the implementation surface; step 8 only deletes.
- **Does not** rewrite ADRs, specs, or plans under `docs/`. Those are historical record. Update only top-level docs (e.g. `README.md`, `CLAUDE.md`) if they actively describe the project as GPU-driven.
- **Does not** touch the chunk-render shader (`shaders/visual/render_chunk.gdshader`) or any other non-compute `.gdshader` (per §3.3). Confirm by file listing they're untouched at the end.
- **Does not** open a PR, force-push, or merge to `master`. The branch (`refactor/cpp`) stays open for the user to merge or PR by hand.
- **Does not** introduce CI (per §3.4). The verification is local + cross-machine smoke, run by hand.
- **Does not** add a benchmarking harness. If frame-budget concerns surface during the smoke playthrough, that's follow-up work per spec §10.1 risk #1 — open a separate plan.
- **Does not** rebalance gameplay, retune materials, or tweak generation. Sim-feel divergences from the GPU baseline are expected per §3.4 Q3.
- **Does not** delete the spec or plan files for steps 1–7. Those are the project's record of how the port happened.

## Pre-flight Verification (do this first)

- [ ] **Step 1: Confirm step 7 is merged and the build is green**

```bash
git status
git log --oneline -10
./gdextension/build.sh debug
ls bin/lib/
```

Expected: working tree clean (or only this plan staged), `583a942` ("refactor: delete simulation shaders, compute_device, world_preview, transitional GPU hacks") in the recent log, debug dylib present in `bin/lib/`.

If the working tree has unrelated changes, stop and ask the user before continuing — the audit greps below assume a clean tree.

- [ ] **Step 2: Inventory the stragglers**

Run each of these and capture the output. The lists feed Tasks 1–4 below.

```bash
# (a) Stale .uid orphans (any .uid whose .gd sibling is missing).
find . -name "*.gd.uid" -not -path "./.git/*" -not -path "./gdextension/godot-cpp/*" \
    | while read f; do gd="${f%.uid}"; [ ! -f "$gd" ] && echo "ORPHAN: $f"; done

# (b) Editor plugins that reference deleted classes.
ls addons/

# (c) Top-level docs/scripts that mention the deleted classes.
grep -rn "MaterialRegistry\|compute_device\|ComputeDevice\|WorldPreview\|world_preview\|RenderingDevice\|RDShaderFile\|RDShaderSPIRV\|compute_list\|push_constant\|RDUniform" \
    --include="*.md" --include="*.gd" --include="*.sh" --include="*.py" --include="*.cfg" \
    --exclude-dir=docs --exclude-dir=.git --exclude-dir=gdextension/godot-cpp --exclude-dir=addons/gdUnit4 .

# (d) project.godot autoload + editor_plugins state.
grep -A30 "^\[autoload\]" project.godot
grep "^enabled" project.godot

# (e) Confirm the legacy shader directories are gone.
ls shaders/
find shaders/compute shaders/include shaders/generated 2>&1
ls comp.spv generate_materials.sh 2>&1
```

Save the combined output to `/tmp/step8-inventory-before.txt`. Re-run at end of step (Task 5) and diff.

If output (a) lists any `.uid` orphan: it goes in Task 1.
If output (b) shows `level_preview` (or anything else with a `WorldPreview` / `compute_device` / GPU-pipeline dependency): it goes in Task 2.
If output (c) is non-empty (excluding `docs/superpowers/specs/` and `docs/superpowers/plans/`): each hit goes in Task 3.
If output (d) shows a `level_preview` entry in `[editor_plugins]`: it goes in Task 2.
If output (e) shows any of the legacy paths existing: stop — step 7 didn't actually delete them, and this is now a step 7 bug. Flag to the user; do not delete in this step.

---

## Task 1: Delete `.uid` orphans

- [ ] **Step 1: Re-list orphans** (from pre-flight (a))

```bash
find . -name "*.gd.uid" -not -path "./.git/*" -not -path "./gdextension/godot-cpp/*" \
    | while read f; do gd="${f%.uid}"; [ ! -f "$gd" ] && echo "$f"; done
```

- [ ] **Step 2: Delete each orphan**

For every line printed above, `rm` it. Known target as of plan-write time: `tools/texture_array_builder.gd.uid`. Add any others surfaced by the find.

```bash
rm tools/texture_array_builder.gd.uid
# rm <other orphans as enumerated>
```

- [ ] **Step 3: Re-run the find and confirm empty**

```bash
find . -name "*.gd.uid" -not -path "./.git/*" -not -path "./gdextension/godot-cpp/*" \
    | while read f; do gd="${f%.uid}"; [ ! -f "$gd" ] && echo "ORPHAN: $f"; done
```

Expected: no output.

---

## Task 2: Remove the `level_preview` editor plugin

The plugin's script (`addons/level_preview/level_preview_plugin.gd`) references `WorldPreview` and `WorldPreviewInspectorPlugin`, both of which were deleted in step 7. With the addon enabled, the editor will print parse errors on launch. The feature is dead per spec §3.1.

- [ ] **Step 1: Confirm the addon's contents are dead**

```bash
ls addons/level_preview/
grep -n "WorldPreview\|world_preview\|WorldPreviewInspectorPlugin" addons/level_preview/*.gd
```

Expected: every reference points at a deleted class. If the addon contains anything still in use (a non-trivial check — the addon is small, ~50 LOC, scan it visually), stop and surface to the user before deleting.

- [ ] **Step 2: Delete the addon directory**

```bash
rm -rf addons/level_preview
```

- [ ] **Step 3: Remove the `[editor_plugins]` entry from `project.godot`**

Edit `project.godot`. Find:

```
enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg", "res://addons/level_preview/plugin.cfg")
```

Replace with:

```
enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")
```

Use the `Edit` tool with the exact full-line strings; do not hand-edit with `sed`.

- [ ] **Step 4: Confirm**

```bash
grep "level_preview\|WorldPreview" project.godot addons/ -rn 2>&1
ls addons/
```

Expected: zero hits, and `addons/` shows only `gdUnit4`.

---

## Task 3: Update stale comments / doc references

Each hit from pre-flight grep (c) gets resolved here. The known target list:

- [ ] **Step 1: Fix `tools/generate_room_templates.gd:11`**

The comment currently reads (or similar):

```
# Material IDs (must match MaterialRegistry order; cannot import the autoload
```

Replace `MaterialRegistry` with `MaterialTable`. The note about "cannot import the autoload" no longer applies — `MaterialTable` is a registered engine singleton; reachable via `MaterialTable.get_id("foo")` from any GDScript context. Update the comment to reflect that, but **do not** restructure the script's hardcoded id list — material id stability is load-bearing per spec §7.5, and the codegen tool predates the C++ table.

- [ ] **Step 2: Fix every other hit from pre-flight grep (c)**

For each remaining `.md` / `.gd` / `.sh` / `.py` / `.cfg` line that references a deleted class:
- If it's a top-level `README.md` or `CLAUDE.md` describing the project as GPU-driven: rewrite the line to describe the CPU pipeline (one-line replacements, not whole-paragraph rewrites).
- If it's a tool script referring to `compute_device` / `RenderingDevice` paths: the script is broken — surface to the user, do not silently delete.
- If it's a dead reference in a comment: update or delete the comment.

Do not touch any file under `docs/superpowers/specs/` or `docs/superpowers/plans/` — those are historical.

- [ ] **Step 3: Confirm**

```bash
grep -rn "MaterialRegistry\|compute_device\|ComputeDevice\|WorldPreview\|world_preview\|RenderingDevice\|RDShaderFile\|RDShaderSPIRV\|compute_list\|push_constant\|RDUniform" \
    --include="*.md" --include="*.gd" --include="*.sh" --include="*.py" --include="*.cfg" \
    --exclude-dir=docs --exclude-dir=.git --exclude-dir=gdextension/godot-cpp --exclude-dir=addons/gdUnit4 .
```

Expected: zero hits. If anything remains, decide per Step 2 above; do not paper over with a `--exclude` flag.

---

## Task 4: Sweep `tests/` and `tools/` for dead references

- [ ] **Step 1: Test references to removed classes**

```bash
grep -rn "MaterialRegistry\|ComputeDevice\|compute_device\|WorldPreview\|RenderingDevice\|RDShaderFile" tests/
```

Expected: zero hits. If a test still imports or instantiates a removed class, the test was supposed to die or migrate during the per-feature step that owned that class. Surface to the user — do not silently delete tests in this step. If the test only references the removed class in a string (e.g. an error-message assertion), update the string.

- [ ] **Step 2: Tool scripts that drove the GPU pipeline**

```bash
ls tools/
grep -l "RenderingDevice\|RDShaderFile\|compute_list\|push_constant" tools/*.{gd,sh,py} 2>/dev/null
```

Expected: no hits. Any tool that wrapped the GPU pipeline (e.g. a `.spv` build script beyond `generate_materials.sh`) should already be gone.

- [ ] **Step 3: `.gitignore` entries for paths that no longer exist**

```bash
cat .gitignore
```

`shaders/generated/` if listed: remove the entry (the directory is gone). `comp.spv`: remove if listed. Keep `bin/lib/`, `gdextension/godot-cpp/bin/`, `gdextension/godot-cpp/gen/`, `*.o`, `*.os`, `.sconsign.dblite`, SCons cache dirs (these are still required per spec §5.6).

- [ ] **Step 4: Confirm**

```bash
git status
```

Expected: only the deletions + edits from Tasks 1–4 staged.

---

## Task 5: Final spec-defined verification (the gate)

This task runs every grep in spec §10.2 and ticks every bullet in spec §11. Step 7 ran most of these once at its tail; this run is the authoritative end-of-refactor sign-off.

- [ ] **Step 1: Compute-shader directory removal**

```bash
find shaders/compute -type f 2>&1
find shaders/include -type f 2>&1
find shaders/generated -type f 2>&1
ls shaders/
```

Expected:
- First three: `find: No such file or directory` (or empty output).
- `ls shaders/`: only `chromatic_flash.gdshader` (+ `.uid`), `ui/`, `visual/`, `weapons/`. The `visual/render_chunk.gdshader` is the chunk-render shader spec §3.3 keeps. No `compute/`, `include/`, `generated/`.

- [ ] **Step 2: GPU API references**

```bash
grep -rn "RenderingDevice\|RDShaderFile\|RDShaderSPIRV\|compute_list\|push_constant\|RDUniform" src/ gdextension/src/
```

Expected: zero hits. Per spec §11.

- [ ] **Step 3: Build artifacts removed**

```bash
ls comp.spv generate_materials.sh 2>&1
ls shaders/generated 2>&1
```

Expected: all "No such file or directory."

- [ ] **Step 4: Removed GDScripts gone**

```bash
ls src/core/compute_device.gd src/autoload/material_registry.gd src/terrain/world_preview.gd 2>&1
```

Expected: all "No such file or directory."

- [ ] **Step 5: `project.godot` post-conditions**

```bash
grep -A30 "^\[autoload\]" project.godot
```

Expected: no `MaterialRegistry`, `WorldPreview`, `ComputeDevice` autoload entries.

```bash
grep "^enabled" project.godot
```

Expected: no `level_preview` entry; `gdUnit4` only.

- [ ] **Step 6: Class registration sanity**

```bash
grep "GDREGISTER_CLASS\|GDREGISTER_ABSTRACT_CLASS\|GDREGISTER_INTERNAL_CLASS" gdextension/src/register_types.cpp
```

Expected to include (from steps 2–7): `MaterialTable` (or `Engine::register_singleton`), `TerrainCell`, `BiomeDef`, `PoolDef`, `RoomTemplate`, `TemplatePack`, `Chunk`, `SectorGrid`, `GenerationContext`, `TerrainCollider`, `GasInjector`, `TerrainCollisionHelper`, `TerrainPhysical`, `ColliderBuilder`, `Generator`, `SimplexCaveGenerator`, `Simulator`, `ChunkManager`, `WorldManager`, `TerrainModifier`. Cross-check against spec §3.2.

- [ ] **Step 7: `.tres` files use native classes (per step 3)**

```bash
grep -l 'script_class="BiomeDef"\|script_class="PoolDef"\|script_class="RoomTemplate"\|script_class="TemplatePack"\|script_class="TerrainCell"' -r .
```

Expected: zero hits. Every relevant `.tres` should use the native shape (`[gd_resource type="BiomeDef" ...]`) per spec §9.3.

- [ ] **Step 8: Diff against pre-flight inventory**

```bash
grep -rn "MaterialRegistry\|compute_device\|ComputeDevice\|WorldPreview\|world_preview\|RenderingDevice\|RDShaderFile\|RDShaderSPIRV\|compute_list\|push_constant\|RDUniform" \
    --include="*.md" --include="*.gd" --include="*.sh" --include="*.py" --include="*.cfg" \
    --exclude-dir=docs --exclude-dir=.git --exclude-dir=gdextension/godot-cpp --exclude-dir=addons/gdUnit4 . \
    > /tmp/step8-inventory-after.txt
diff /tmp/step8-inventory-before.txt /tmp/step8-inventory-after.txt | head -60
cat /tmp/step8-inventory-after.txt
```

Expected: `step8-inventory-after.txt` is empty.

---

## Task 6: Build + editor smoke + gdUnit4

- [ ] **Step 1: Clean build, both targets**

```bash
./gdextension/build.sh clean
./gdextension/build.sh debug
./gdextension/build.sh release
ls -la bin/lib/
```

Expected:
- `libtoprogue.macos.template_debug.{arm64,x86_64}.dylib` (whichever your macOS arch is) **or** `libtoprogue.linux.template_debug.x86_64.so`.
- Same for `template_release`.
- No SCons errors, no missing godot-cpp symbols.

- [ ] **Step 2: Editor smoke**

Launch Godot 4.6. **Restart cold** — do not rely on hot-reload (per spec §5.7).

Confirm the **Output** panel is clean:
- No `Failed to load resource: res://shaders/compute/...`.
- No `Failed to load resource: res://src/core/compute_device.gd`.
- No `Failed to load resource: res://src/autoload/material_registry.gd`.
- No `Failed to load resource: res://src/terrain/world_preview.gd`.
- No `Failed to load resource: res://addons/level_preview/...`.
- No "Could not parse script" or "Missing script" warnings on any scene.
- No "GDExtension class not found" errors.

If any of the above fire: do not proceed. Track each error to its source and fix in this step.

- [ ] **Step 3: gdUnit4 suite**

Run the gdUnit4 panel (or `addons/gdUnit4/runtest.sh` if scripted). Expected: **all green** per spec §11.

If a test red-lines: per Task 4 step 1, surface to the user before patching. The contract from spec §9.5 is "tests don't change unless they were poking at a private GDScript field that got ported away" — at this stage in the migration, no such field should remain, so a failure is a real regression.

---

## Task 7: Smoke playthrough (per spec §10.2)

Repeat the playthrough on **both macOS and Arch Linux**. The cross-machine sanity is the spec's explicit gate (§11: "Smoke playthrough passes on both machines").

- [ ] **Step 1: macOS playthrough**

Launch the project → F5 → walk through a generated level for ~2 minutes. Exercise:
- **Generation:** caves/biomes/stamps/secret rings render correctly. No black chunks, no infinite-loading edges.
- **Lava:** weapon-emit lava at a chunk boundary; lava flows downhill, pools, cools, crosses chunk borders, no flicker, no spurious solids.
- **Gas:** gas weapon → gas drifts, diffuses, dissipates; cross-chunk migration works.
- **Burning:** lava on wood → wood ignites → flames spread → wood becomes air. Gas + fire interaction matches step-7 baseline.
- **Digging:** carving walls (`TerrainModifier::place_material(MAT_AIR, ...)`); collider rebuilds; player walks through.
- **Sleeping:** stand still in a settled area for ~5 s; CPU drops as chunks sleep. Walk; frames recover.
- **Floor advance:** portal → next floor → sim still works on the new level.
- **Combat:** at least one enemy fight; weapons hit; drops appear; pickups work.
- **Exit cleanly.** No crash on quit, no hang.

No frame stutters > 1 s anywhere.

- [ ] **Step 2: Cross-machine pull on Arch**

```bash
git pull
git submodule update --init --recursive
./gdextension/build.sh clean
./gdextension/build.sh debug
ls -la bin/lib/
```

- [ ] **Step 3: Arch playthrough**

Repeat Task 7 Step 1 on Arch. Per spec §6.8, sim outputs may visibly differ from macOS (different lava shapes, different burn fronts) — that's fine, cross-machine determinism is explicitly out of scope. The bar is "the level generates and plays correctly, no crashes, no deadlocks, no stutters > 1 s."

If something is structurally broken on Arch (crash, missing rooms, sim deadlock, build failure not caused by toolchain): fix and commit before declaring step 8 done.

---

## Task 8: Format, commit, push

- [ ] **Step 1: Format any stragglers**

```bash
./gdextension/format.sh
git diff gdextension/src/
```

Expected: no diff (step 7 already formatted). If the formatter changed anything (unlikely — no C++ touched in step 8), commit the format-only change separately.

- [ ] **Step 2: Commit step 8 cleanup**

Stage only the intended changes (`.uid` deletions, `addons/level_preview/` removal, `project.godot` edit, comment updates, `.gitignore` trim). Do not blanket `git add -A` — confirm `git status` shows nothing unrelated.

```bash
git status
git diff --staged
git commit -m "$(cat <<'EOF'
chore: final cleanup — remove level_preview addon, orphan .uid files, stale MaterialRegistry comments

Closes the godot-cpp hot-path port (steps 1–8 of the 2026-04-30 design spec).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Push the branch**

```bash
git push origin refactor/cpp
```

The branch stays open for the user to merge or PR by hand. Per non-goals, this step does not open a PR or merge.

---

## Done Definition for Step 8

(Cross-reference spec §11 "Done Definition" — every bullet there must be true at the end of this step. Confirm by running the command, not by recall.)

- `find shaders/compute -type f` returns empty / no-such-dir; same for `shaders/include` and `shaders/generated`.
- `ls shaders/` shows only the non-compute visual shaders (`chromatic_flash.gdshader`, `ui/`, `visual/`, `weapons/`).
- `grep -rn "RenderingDevice\|RDShaderFile\|RDShaderSPIRV\|compute_list\|push_constant\|RDUniform" src/ gdextension/src/` returns zero hits.
- `comp.spv`, `generate_materials.sh`, `shaders/generated/` are gone.
- `src/core/compute_device.gd`, `src/autoload/material_registry.gd`, `src/terrain/world_preview.gd` (and their `.uid` siblings) are gone.
- `project.godot` `[autoload]` has no `MaterialRegistry`/`WorldPreview`/`ComputeDevice` entry; `[editor_plugins]` has no `level_preview` entry.
- `addons/level_preview/` is gone.
- No orphan `.uid` files in `tools/`, `src/`, `tests/`, `addons/` (except `gdUnit4` and `godot-cpp` submodule).
- No stale `MaterialRegistry` / `compute_device` / `world_preview` references in top-level `.md`, `.gd`, `.sh`, `.py`, `.cfg` files (excluding `docs/superpowers/specs/` and `docs/superpowers/plans/`, which are historical).
- `bin/toprogue.gdextension` loads on macOS and Arch; debug + release dylibs both build clean.
- `gdUnit4` suite green on both machines.
- Smoke playthrough (~2 min, generation + lava + gas + fire + digging + combat + floor advance + clean exit) passes on both machines.
- Spec §11 Done Definition is fully satisfied.

When every checkbox above is ticked, the godot-cpp hot-path port is complete. The branch (`refactor/cpp`) is ready for the user to merge to `master` at their discretion.
