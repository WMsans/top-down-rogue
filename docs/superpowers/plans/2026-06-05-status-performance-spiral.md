# Status Performance Death-Spiral Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the 90→7 fps physics death-spiral caused by every status-bearing entity polling terrain every physics step (×8 substep amplification), and smooth the chunk-generation hitch.

**Architecture:** Move `StatusComponent`'s per-frame work off `_physics_process` (which Godot multiplies up to 8× during catch-up) onto `_process`; throttle the expensive terrain poll to every Kth frame with a per-instance phase and accumulated delta; shrink the footprint sample grid; cap physics substeps as defense-in-depth; and cap how many new chunks `world_manager` generates per frame.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 test framework.

**Test command (whole suite for one file):**
`GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`

---

## File Structure

- `src/status/status_component.gd` — Tasks 1, 2. Add scheduling state + `update()`, move orchestration to `_process`, shrink sample grid.
- `tests/unit/test_status_component.gd` — Task 1 test (throttle frequency + delta accumulation). Existing poll tests guard Task 2.
- `project.godot` — Task 3. `max_physics_steps_per_frame` cap.
- `src/core/world_manager.gd` — Task 4. Static chunk-selection helper + per-frame cap.
- `tests/unit/test_world_manager_chunk_budget.gd` — Task 4 test (pure static selector).

---

## Task 1: Throttle status updates and move them off `_physics_process`

Implements design A1 (off `_physics_process`) and A2 (stagger + throttle the terrain poll, accumulate delta). `tick()` keeps running every render frame; only `_poll_terrain` is throttled.

**Files:**
- Modify: `src/status/status_component.gd` (vars ~29-33, `_ready` ~36-40, replace `_physics_process` ~120-123)
- Test: `tests/unit/test_status_component.gd`

- [ ] **Step 1: Write the failing test**

Add this inner class near the top of `tests/unit/test_status_component.gd` (after the existing `FakeBody` class, before the first `func`):

```gdscript
# Counts/records _poll_terrain calls so we can assert the throttle schedule
# without driving the real GPU probe pipeline.
class CountingStatus extends StatusComponent:
	var poll_count: int = 0
	var last_poll_delta: float = 0.0
	func _poll_terrain(delta: float) -> void:
		poll_count += 1
		last_poll_delta = delta
```

Add this test function at the end of the file:

```gdscript
func test_update_throttles_terrain_poll() -> void:
	var owner := auto_free(Node.new())
	add_child(owner)
	var c := CountingStatus.new()
	owner.add_child(c)          # _ready runs here
	c._poll_phase = 0           # deterministic phase for the test
	c._frame_counter = 0
	var dt := 1.0 / 60.0
	var frames := StatusComponent.POLL_INTERVAL * 3
	for _i in frames:
		c.update(dt)
	# One poll per POLL_INTERVAL frames -> exactly 3 over 3 intervals.
	assert_int(c.poll_count).is_equal(3)
	# Each poll receives the delta accumulated across the whole interval,
	# so stain rates stay identical to the unthrottled version.
	assert_float(c.last_poll_delta).is_equal_approx(dt * StatusComponent.POLL_INTERVAL, 0.0001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: FAIL — `update` / `POLL_INTERVAL` / `_poll_phase` / `_frame_counter` do not exist yet (parse or assertion error).

- [ ] **Step 3: Add scheduling state**

In `src/status/status_component.gd`, after the line `const _HISTORY_FRAMES := 3` (currently line 27) add:

```gdscript
# Terrain polling is the dominant per-entity cost. Run it every POLL_INTERVAL
# render frames (not physics steps), spread across entities by a per-instance
# phase, accumulating delta so stain rates are unchanged. See the design doc
# 2026-06-05-status-performance-spiral-design.md.
const POLL_INTERVAL := 4
```

After the line `var _origin_history: Array[Vector2] = []  # recent poll positions, oldest first` (currently line 33) add:

```gdscript
var _frame_counter: int = 0
var _poll_phase: int = 0           # which frame-in-interval this component polls on
var _accum_poll_delta: float = 0.0  # delta accumulated since the last terrain poll
```

- [ ] **Step 4: Stagger the phase in `_ready`**

In `_ready`, after the existing `_terrain_physical` assignment block (currently ends line 40), add:

```gdscript
	_poll_phase = int(get_instance_id() % POLL_INTERVAL)
```

So `_ready` becomes:

```gdscript
func _ready() -> void:
	_owner_node = get_parent()
	var wm: Node = get_tree().get_first_node_in_group("world_manager")
	if wm != null:
		_terrain_physical = wm.get_node_or_null("TerrainPhysical")
	_poll_phase = int(get_instance_id() % POLL_INTERVAL)
```

- [ ] **Step 5: Replace `_physics_process` with `_process` + `update`**

Replace the current function (lines 120-123):

```gdscript
func _physics_process(delta: float) -> void:
	_poll_terrain(delta)
	tick(delta)
```

with:

```gdscript
func _process(delta: float) -> void:
	update(delta)


# Per-frame entry. tick() (decay/reactions/burn) runs every frame; the heavy
# terrain poll runs once per POLL_INTERVAL frames and is handed the accumulated
# delta so accumulation totals match an every-frame poll.
func update(delta: float) -> void:
	_accum_poll_delta += delta
	_frame_counter += 1
	if (_frame_counter % POLL_INTERVAL) == _poll_phase:
		_poll_terrain(_accum_poll_delta)
		_accum_poll_delta = 0.0
	tick(delta)
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: PASS — including all pre-existing tests (they call `_poll_terrain`/`tick` directly, so they are unaffected).

- [ ] **Step 7: Commit**

```bash
git add src/status/status_component.gd tests/unit/test_status_component.gd
git commit -m "perf: throttle status terrain poll and run it on _process not _physics_process"
```

---

## Task 2: Shrink the footprint sample grid

Implements design A3. `_SAMPLE_STEPS` 3 → 2 turns each origin's 3×3 (9) samples into 2×2 (4) corner samples, roughly halving the remaining poll cost. The corners still span the full footprint, so stain pickup is preserved.

**Files:**
- Modify: `src/status/status_component.gd` (currently line 18)
- Test: `tests/unit/test_status_component.gd` (existing poll tests guard behavior)

- [ ] **Step 1: Make the change**

In `src/status/status_component.gd`, change:

```gdscript
const _SAMPLE_STEPS := 3
```

to:

```gdscript
const _SAMPLE_STEPS := 2
```

(The `lerpf(..., float(iy) / (_SAMPLE_STEPS - 1))` math stays valid: divisor becomes 1, sampling the two footprint edges.)

- [ ] **Step 2: Run the existing terrain-poll tests to confirm pickup still works**

Run: `GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: PASS — the stationary/moving terrain-poll tests still accumulate stain (corner samples cover the footprint).

- [ ] **Step 3: Commit**

```bash
git add src/status/status_component.gd
git commit -m "perf: reduce status footprint sampling from 9 to 4 points per origin"
```

---

## Task 3: Cap physics substeps (defense-in-depth)

Implements design A4. Prevents any future regression from re-triggering the 8× catch-up amplification; under extreme load the game degrades to mild slow-mo instead of freezing.

**Files:**
- Modify: `project.godot` (`[physics]` section)

- [ ] **Step 1: Add the setting**

In `project.godot`, find the `[physics]` section (it currently contains `3d/physics_engine="Jolt Physics"`). Add this line inside that section:

```
common/max_physics_steps_per_frame=2
```

Resulting section:

```
[physics]

common/max_physics_steps_per_frame=2
3d/physics_engine="Jolt Physics"
```

- [ ] **Step 2: Verify the setting is present and the project still parses**

Run: `grep -n "max_physics_steps_per_frame" project.godot`
Expected: prints `common/max_physics_steps_per_frame=2`

Run: `GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: PASS (sanity check that `project.godot` is still valid — the suite loads the project).

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "perf: cap max_physics_steps_per_frame at 2 to prevent physics death-spiral"
```

---

## Task 4: Amortize chunk generation across frames

Implements design B1. `world_manager._update_chunks` currently creates+generates every newly-desired chunk in one frame (the `read_region`/`populate`/decoration/light-bake spike). Cap creations per frame; the remaining desired chunks are still requested next frame, so nothing is lost — the fill-in just ramps smoothly.

**Files:**
- Modify: `src/core/world_manager.gd` (`_update_chunks`, currently lines 99-133)
- Test: `tests/unit/test_world_manager_chunk_budget.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_world_manager_chunk_budget.gd`:

```gdscript
extends GdUnitTestSuite

# world_manager.gd has no class_name, so preload the script and call the static
# selector directly — no WorldManager instance (which needs a RenderingDevice).
const WorldManagerScript = preload("res://src/core/world_manager.gd")

func test_select_new_chunks_caps_per_frame() -> void:
	var desired := [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	]
	var loaded := {}  # nothing loaded yet
	var picked := WorldManagerScript._select_new_chunks(desired, loaded, 2)
	assert_int(picked.size()).is_equal(2)
	assert_array(picked).is_equal([Vector2i(0, 0), Vector2i(1, 0)])

func test_select_new_chunks_skips_already_loaded() -> void:
	var desired := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var loaded := {Vector2i(0, 0): true}  # first one already loaded
	var picked := WorldManagerScript._select_new_chunks(desired, loaded, 2)
	assert_array(picked).is_equal([Vector2i(1, 0), Vector2i(2, 0)])

func test_select_new_chunks_returns_all_when_under_cap() -> void:
	var desired := [Vector2i(0, 0), Vector2i(1, 0)]
	var picked := WorldManagerScript._select_new_chunks(desired, {}, 5)
	assert_int(picked.size()).is_equal(2)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_world_manager_chunk_budget.gd`
Expected: FAIL — `_select_new_chunks` does not exist yet.

- [ ] **Step 3: Add the static selector and the per-frame cap constant**

In `src/core/world_manager.gd`, add a constant near the top (after the `var` declarations block, before `func _process`):

```gdscript
# Max new chunks to create+generate per frame; the rest stay "desired but not
# loaded" and are picked up on following frames, spreading the populate/decor/
# light-bake cost instead of spiking it in one frame.
const MAX_NEW_CHUNKS_PER_FRAME := 2
```

Add this static method (place it directly above `func _update_chunks`):

```gdscript
# Pure selection of which desired chunks to create this frame: skip already-loaded
# coords, take at most `cap` in desired order. Static + side-effect-free for testing.
static func _select_new_chunks(desired: Array, loaded: Dictionary, cap: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord in desired:
		if loaded.has(coord):
			continue
		if out.size() >= cap:
			break
		out.append(coord)
	return out
```

- [ ] **Step 4: Use the selector in `_update_chunks`**

In `_update_chunks`, replace the new-chunk loop (currently lines 116-120):

```gdscript
	var new_chunks: Array[Vector2i] = []
	for coord in desired:
		if not chunks.has(coord):
			chunk_manager.create_chunk(coord)
			new_chunks.append(coord)
```

with:

```gdscript
	var new_chunks: Array[Vector2i] = _select_new_chunks(desired, chunks, MAX_NEW_CHUNKS_PER_FRAME)
	for coord in new_chunks:
		chunk_manager.create_chunk(coord)
```

Leave the rest of the function (the `if not new_chunks.is_empty()` generation dispatch / emit, and the `to_remove` unload loop above it) unchanged. Unload still happens fully each frame; only creation is capped.

- [ ] **Step 5: Run the test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot timeout 120 bash ./addons/gdUnit4/runtest.sh -a tests/unit/test_world_manager_chunk_budget.gd`
Expected: PASS (all three cases).

- [ ] **Step 6: Commit**

```bash
git add src/core/world_manager.gd tests/unit/test_world_manager_chunk_budget.gd
git commit -m "perf: cap new chunk generation to 2 per frame to smooth streaming hitch"
```

---

## Task 5: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full unit suite**

Run: `GODOT_BIN=/usr/bin/godot timeout 180 bash ./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS — in particular `test_status_component`, `test_status_reactions`, `test_status_visuals`, `test_world_manager_chunk_budget`, and the terrain tests. Report the pass/fail counts; do not claim success without the summary line.

- [ ] **Step 2: In-game re-profile (manual)**

Launch the game, reach a level, and fight to ~70 enemies with heavy blood. Open the Godot profiler.
Expected after the fix:
- `Enemy._physics_process` call count ≈ the live enemy count (NOT ~8× it) — confirms the substep multiplier is gone.
- `StatusComponent._poll_terrain` total time down by roughly `POLL_INTERVAL × sample-reduction` (≈ 6–8×).
- Sustained frame time back under ~11 ms (≈90 fps); no 41 ms single-frame chunk-generation spikes when crossing chunk boundaries.

- [ ] **Step 3: Final commit (if any profiling tweaks were made)**

Only if `POLL_INTERVAL` or `MAX_NEW_CHUNKS_PER_FRAME` needed tuning during Step 2:

```bash
git add -A
git commit -m "perf: tune status poll interval / chunk budget after profiling"
```
```

## Notes for the implementer

- `tick()` deliberately still runs every frame — it is cheap (~6 ms/696 in the profile, i.e. unamplified ~0.75 ms) and keeping burn DoT / decay smooth matters more than the tiny saving from throttling it. Do not throttle `tick`.
- Front B2 (collision-rebuild debounce) was investigated and found **already implemented** in `terrain_collision_helper.gd` (`MAX_DISPATCH_PER_FRAME = 4`, `_last_seg_hash` skip). No task — see the spec.
