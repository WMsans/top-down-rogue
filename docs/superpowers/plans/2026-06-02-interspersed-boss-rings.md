# Interspersed Boss Rings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single edge boss ring with three interspersed concentric rings so every radial direction out of spawn crosses a boss arena, eliminating the "walk out and miss every boss" soft-lock.

**Architecture:** `src/core/sector_grid.gd` gains three phase-offset square boss rings at Chebyshev distances `[8, 10, 12]` (8 anchors each, phases `[0, ⅓, ⅔]`). A new radial-ray regression test proves full coverage. Nothing else in the spawn pipeline changes — `composition_dispatcher` already spawns any sector whose slot carries a composition.

**Tech Stack:** Godot 4 / GDScript, GdUnit4 test framework (headless via `addons/gdUnit4/bin/GdUnitCmdTool.gd`).

**Verified design facts (do not re-derive):**
- Boss arena carved radius = `ArenaComposition.nominal_radius` = **960px**. Sector size = **384px**.
- With rings `[8,10,12]`, 8 anchors/ring, phases `[0, 1/3, 2/3]`, the worst-case ray's closest approach to any anchor is **686px** from spawn center — comfortably under 960px. These constants are pre-validated; the test in Task 1 confirms them in-engine.
- Exact anchor coords produced by these constants:
  - d=8: `(-8,-8) (-8,0) (-8,8) (0,-8) (0,8) (8,-8) (8,0) (8,8)`
  - d=10: `(-10,-3) (-10,7) (-7,-10) (-3,10) (3,-10) (7,10) (10,-7) (10,3)`
  - d=12: `(-12,-8) (-12,4) (-8,12) (-4,-12) (4,12) (8,-12) (12,-4) (12,8)`

**Test command (all tasks):**
```bash
GODOT_BIN=/usr/bin/godot godot --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a <test-suite-path>
```
A suite passes when the summary line reads `0 errors | 0 failures` and `Exit code: 0`.

---

## File Structure

- `src/core/sector_grid.gd` — **modify.** Owns world layout: which sector is boss/room/empty. All ring-geometry changes live here.
- `tests/unit/test_boss_ring_coverage.gd` — **create.** The radial-coverage guarantee (regression test).
- `tests/unit/test_sector_grid.gd` — **modify.** Repoint old single-ring assertions to the new layout.
- `tests/unit/test_sector_grid_claim.gd` — **modify.** Repoint anchor coords + expected anchor count.
- `src/core/spawn_dispatcher.gd` — **modify (1 line).** Tier divisor reads the renamed outer-edge constant.

---

## Task 1: Radial-coverage regression test (RED first)

**Files:**
- Create: `tests/unit/test_boss_ring_coverage.gd`

This test compiles against the *current* code (`is_boss_anchor(coord)` already takes one arg), so it goes red because today's single ring leaves angular gaps — demonstrating the bug before we fix it.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_boss_ring_coverage.gd`:

```gdscript
extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

# ArenaComposition.nominal_radius — the carved boss-arena radius in px.
const NOMINAL_RADIUS := 960.0
# Outer ring distance; scan/march bound. Equals SectorGrid.BOSS_WORLD_EDGE post-Task-2.
const EDGE := 12

func _biome() -> Resource:
	var b := _BiomeDef.new()
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b

func _anchor_world_positions(grid) -> Array:
	var pts: Array = []
	for x in range(-EDGE, EDGE + 1):
		for y in range(-EDGE, EDGE + 1):
			if _SectorGrid.is_boss_anchor(Vector2i(x, y)):
				pts.append(Vector2(grid.sector_to_world_center(Vector2i(x, y))))
	return pts

func test_every_radial_direction_crosses_a_boss_arena() -> void:
	var grid := _SectorGrid.new(0, _biome())
	var anchors := _anchor_world_positions(grid)
	assert_that(anchors.size() > 0).is_true()
	var src := Vector2(grid.sector_to_world_center(Vector2i.ZERO))
	# Far enough to reach the corner of the d=12 square (12*384*sqrt2 ~= 6519).
	var edge_dist := float(EDGE) * _SectorGrid.SECTOR_SIZE_PX * 1.5
	var rays := 3600
	var uncovered := 0
	for i in range(rays):
		var a := TAU * float(i) / float(rays)
		var dir := Vector2(cos(a), sin(a))
		var covered := false
		for p in anchors:
			var q: Vector2 = p - src
			var proj := q.dot(dir)
			if proj < 0.0 or proj > edge_dist:
				continue  # behind the ray or past the world edge
			var perp := absf(q.x * dir.y - q.y * dir.x)  # dist anchor->ray line
			if perp < NOMINAL_RADIUS:
				covered = true
				break
		if not covered:
			uncovered += 1
	assert_that(uncovered).is_equal(0)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
GODOT_BIN=/usr/bin/godot godot --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a tests/unit/test_boss_ring_coverage.gd
```
Expected: **FAIL** — `uncovered` is large (the current single ring covers only ~⅔ of directions). Summary shows `1 failure`.

- [ ] **Step 3: Commit the red test**

```bash
git add tests/unit/test_boss_ring_coverage.gd
git commit -m "test: radial-coverage guarantee for boss rings (red)"
```

---

## Task 2: Generalize ring geometry (make coverage GREEN)

**Files:**
- Modify: `src/core/sector_grid.gd`

- [ ] **Step 1: Replace the ring constants**

In `src/core/sector_grid.gd`, replace this block:

```gdscript
const SECTOR_SIZE_PX := 384
const BOSS_RING_DISTANCE := 10
const BOSS_RING_STRIDE := 8
const BOSS_CLAIM_RADIUS := 3
const ELITE_CLAIM_RADIUS := 1
const EMPTY_WEIGHT := 1.5
```

with:

```gdscript
const SECTOR_SIZE_PX := 384
# Three interspersed concentric square boss rings (Chebyshev sectors), inner -> outer.
const BOSS_RING_DISTANCES := [8, 10, 12]
const BOSS_WORLD_EDGE := 12          # dist > this is empty void (world edge)
const BOSS_RING_ANCHOR_COUNT := 8    # anchors per ring
# Per-ring phase (fraction of anchor spacing) so anchors interleave in angle.
const BOSS_RING_PHASES := [0.0, 1.0 / 3.0, 2.0 / 3.0]
const BOSS_CLAIM_RADIUS := 3
const ELITE_CLAIM_RADIUS := 1
const EMPTY_WEIGHT := 1.5
```

- [ ] **Step 2: Generalize `_ring_index` and `is_boss_anchor`**

Replace this block:

```gdscript
static func _ring_index(coord: Vector2i) -> int:
	if coord.x == BOSS_RING_DISTANCE:  return coord.y + BOSS_RING_DISTANCE
	if coord.y == BOSS_RING_DISTANCE:  return 20 + (BOSS_RING_DISTANCE - coord.x)
	if coord.x == -BOSS_RING_DISTANCE: return 40 + (BOSS_RING_DISTANCE - coord.y)
	return 60 + (coord.x + BOSS_RING_DISTANCE)


static func is_boss_anchor(coord: Vector2i) -> bool:
	if max(abs(coord.x), abs(coord.y)) != BOSS_RING_DISTANCE:
		return false
	return (_ring_index(coord) % BOSS_RING_STRIDE) == 0
```

with:

```gdscript
# Index of a sector walking the perimeter of the square ring of radius d: 0 .. 8d-1.
static func _ring_index(coord: Vector2i, d: int) -> int:
	if coord.x == d:  return coord.y + d
	if coord.y == d:  return 2 * d + (d - coord.x)
	if coord.x == -d: return 4 * d + (d - coord.y)
	return 6 * d + (coord.x + d)


static func is_boss_anchor(coord: Vector2i) -> bool:
	var d: int = max(abs(coord.x), abs(coord.y))
	var k := BOSS_RING_DISTANCES.find(d)
	if k == -1:
		return false  # not on any boss ring
	var perim := 8 * d
	var r := _ring_index(coord, d)
	var phase: float = BOSS_RING_PHASES[k]
	for j in range(BOSS_RING_ANCHOR_COUNT):
		var t := int(round((float(j) + phase) * float(perim) / float(BOSS_RING_ANCHOR_COUNT))) % perim
		if t == r:
			return true
	return false
```

- [ ] **Step 3: Update `resolve_sector` boundary + boss branch**

In `resolve_sector`, replace:

```gdscript
	var dist := chebyshev_distance(coord, Vector2i.ZERO)

	if dist > BOSS_RING_DISTANCE:
		slot.is_empty = true
		return slot

	if dist == BOSS_RING_DISTANCE and is_boss_anchor(coord):
		if _biome.boss_compositions.is_empty():
```

with:

```gdscript
	var dist := chebyshev_distance(coord, Vector2i.ZERO)

	if dist > BOSS_WORLD_EDGE:
		slot.is_empty = true
		return slot

	if is_boss_anchor(coord):
		if _biome.boss_compositions.is_empty():
```

(The rest of that branch — the RNG seed, `slot.is_boss`, `template_index`, `composition` — is unchanged. `_find_claiming_anchor` is unchanged: it already calls `is_boss_anchor`, so it now claims around every ring's anchors automatically.)

- [ ] **Step 4: Run the coverage test to verify it passes**

```bash
GODOT_BIN=/usr/bin/godot godot --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a tests/unit/test_boss_ring_coverage.gd
```
Expected: **PASS** — `0 failures`, `Exit code: 0` (`uncovered == 0`).

- [ ] **Step 5: Commit**

```bash
git add src/core/sector_grid.gd
git commit -m "feat: interspersed boss rings at [8,10,12] for full radial coverage"
```

---

## Task 3: Repoint existing sector-grid tests to the new layout

The old tests assert specific d=10 anchors and a d=10 world edge. Under the new layout: d=10 is now interior (edge is 12), the d=10 ring has 8 anchors (was 10), and `(10,0)`/`(10,-10)` are no longer anchors. New d=10 anchors include **`(10,-7)`** and **`(10,3)`**.

**Files:**
- Modify: `tests/unit/test_sector_grid.gd`
- Modify: `tests/unit/test_sector_grid_claim.gd`

- [ ] **Step 1: Fix `test_sector_grid.gd` assertions**

Edit 1 — world edge moved to 12 (`test_outside_boss_ring_is_empty`). Replace:

```gdscript
	var slot := grid.resolve_sector(Vector2i(11, 0))
	assert_that(slot.is_empty).is_true()
```
with:
```gdscript
	var slot := grid.resolve_sector(Vector2i(13, 0))  # dist 13 > edge 12
	assert_that(slot.is_empty).is_true()
```

Edit 2 — a real d=10 anchor (`test_boss_ring_returns_boss_slot`). Replace:

```gdscript
	var slot := grid.resolve_sector(Vector2i(10, -10))
	assert_that(slot.is_boss).is_true()
```
with:
```gdscript
	var slot := grid.resolve_sector(Vector2i(10, -7))  # d=10 anchor
	assert_that(slot.is_boss).is_true()
```

Edit 3 — non-rotatable boss slot (`test_rotation_is_zero_for_non_rotatable`). Replace:

```gdscript
	var slot := grid.resolve_sector(Vector2i(10, 0))  # boss, rotatable=false
	assert_that(slot.rotation).is_equal(0)
```
with:
```gdscript
	var slot := grid.resolve_sector(Vector2i(10, -7))  # boss anchor, rotatable=false
	assert_that(slot.rotation).is_equal(0)
```

Edit 4 — renamed constant (`test_resolve_sector_seed_changes`). Replace:

```gdscript
			if g1.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.BOSS_RING_DISTANCE:
```
with:
```gdscript
			if g1.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.BOSS_WORLD_EDGE:
```

- [ ] **Step 2: Fix `test_sector_grid_claim.gd` assertions**

Edit 1 — `test_boss_anchor_at_spaced_offset_only`. Replace:

```gdscript
	var s0 := grid.resolve_sector(Vector2i(10, -10))
	assert_that(s0.is_boss).is_true()
	var s1 := grid.resolve_sector(Vector2i(10, -9))
	assert_that(s1.is_boss).is_false()
	assert_that(s1.is_claimed).is_true()
```
with:
```gdscript
	var s0 := grid.resolve_sector(Vector2i(10, -7))  # d=10 anchor
	assert_that(s0.is_boss).is_true()
	var s1 := grid.resolve_sector(Vector2i(10, -6))  # neighbor, within claim radius
	assert_that(s1.is_boss).is_false()
	assert_that(s1.is_claimed).is_true()
```

Edit 2 — `test_boss_anchor_count_per_floor` (8 anchors/ring now, was 10). Replace:

```gdscript
	assert_that(count).is_equal(10)
```
with:
```gdscript
	assert_that(count).is_equal(8)
```

(`test_non_anchor_ring10_sectors_empty_or_claimed` and `test_claim_extends_to_inner_neighbors` need **no change** — every non-anchor ring-10 sector is still within claim radius 3 of an adjacent-ring anchor, and `(9,-9)` is still claimed by anchor `(8,-8)`.)

- [ ] **Step 3: Run both sector-grid suites**

```bash
GODOT_BIN=/usr/bin/godot godot --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a tests/unit/test_sector_grid.gd -a tests/unit/test_sector_grid_claim.gd
```
Expected: **PASS** — `0 failures` across both suites.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test_sector_grid.gd tests/unit/test_sector_grid_claim.gd
git commit -m "test: repoint sector-grid tests to interspersed ring layout"
```

---

## Task 4: Point the difficulty-tier divisor at the new edge constant

`spawn_dispatcher.gd` scales enemy tier by `sector_dist / BOSS_RING_DISTANCE`. That constant no longer exists; use the outer edge so tier 2 still tops out at the world edge.

**Files:**
- Modify: `src/core/spawn_dispatcher.gd:148`

- [ ] **Step 1: Update the constant reference**

Replace:

```gdscript
	var tier_index: int = clampi(int(floor(float(sector_dist) / float(SectorGrid.BOSS_RING_DISTANCE) * 2.0)), 0, 2)
```
with:
```gdscript
	var tier_index: int = clampi(int(floor(float(sector_dist) / float(SectorGrid.BOSS_WORLD_EDGE) * 2.0)), 0, 2)
```

- [ ] **Step 2: Run the full unit suite to confirm nothing else references the removed constants**

```bash
GODOT_BIN=/usr/bin/godot godot --headless --path . \
  -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a tests/unit
```
Expected: **PASS** — `0 errors | 0 failures`, `Exit code: 0`. (A parse error here would mean a lingering reference to `BOSS_RING_DISTANCE` or `BOSS_RING_STRIDE`; grep `src/` and `tests/` for those names and fix.)

- [ ] **Step 3: Commit**

```bash
git add src/core/spawn_dispatcher.gd
git commit -m "fix: scale enemy tier by BOSS_WORLD_EDGE after ring rework"
```

---

## Done criteria

- `test_boss_ring_coverage.gd` passes (zero uncovered radial directions).
- All `tests/unit` suites pass.
- No remaining references to `BOSS_RING_DISTANCE` or `BOSS_RING_STRIDE` in `src/` or `tests/`.
- Manual sanity (optional, via Godot editor): start a run, walk straight out in several directions — each reaches a boss arena rather than a dead void wall.
