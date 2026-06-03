# Noita-Style Boss Wall Arena Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make boss rooms physically unmissable by ringing the central play area with an indestructible bedrock wall whose only openings are huge boss chambers.

**Architecture:** A new compute-shader generation stage fills indestructible `BEDROCK` everywhere at Chebyshev distance ≥ 8 sectors from origin; it runs after room stamping and before the existing cavern-carve stage, so boss-chamber carving punches the only gaps in the wall. The boss ring collapses from three rings (8/10/12) to a single ring at the wall face (distance 8), and chambers grow from ~300px to ~600px. Bedrock is indestructible because digging is opt-in by material mask (it is never listed) and explosions get one explicit skip guard.

**Tech Stack:** Godot 4 (GDScript), GLSL compute shaders, gdUnit4 tests. Material defs live in `MaterialRegistry`, regenerated into `shaders/generated/materials.glslinc` by `tools/generate_material_glsl.gd`.

**Spec:** `docs/superpowers/specs/2026-06-02-noita-boss-wall-design.md`

**Test runner:** `./addons/gdUnit4/runtest.sh -a tests/unit/test_<name>.gd`

---

## File Structure

- **Modify** `src/autoload/material_registry.gd` — add `BEDROCK` material def + `MAT_BEDROCK` field.
- **Regenerate** `shaders/generated/materials.glslinc` + `materials.gdshaderinc` — via the tool; adds `MAT_BEDROCK`, `HAS_COLLIDER[]`, tint entries.
- **Modify** `shaders/include/sim/explode_wave.glslinc` — skip bedrock in the terrain-chew branch.
- **Modify** `src/core/sector_grid.gd` — single boss ring, rename `BOSS_WORLD_EDGE` → `WALL_INNER_SECTORS`, add `enemy_tier_for_distance` static helper, reorder `resolve_sector`.
- **Create** `shaders/include/boss_wall_stage.glslinc` — the bedrock-fill stage.
- **Modify** `shaders/compute/generation.glsl` — include + call `stage_boss_wall` before cavern carve.
- **Modify** `src/core/spawn_dispatcher.gd:148` — use the new tier helper.
- **Modify** `assets/arenas/boss/*.tres` (20 files) — grow `nominal_radius`/`inner_disc_radius`/`lobing_amplitude`.
- **Modify** `tests/unit/test_sector_grid.gd`, `tests/unit/test_boss_ring_coverage.gd` — repoint to single-ring layout.
- **Create** `tests/unit/test_enemy_tier_distance.gd` — lock the tier formula.

---

## Task 1: Add the indestructible BEDROCK material

**Files:**
- Modify: `src/autoload/material_registry.gd`
- Regenerate: `shaders/generated/materials.glslinc`, `shaders/generated/materials.gdshaderinc`
- Test: `tests/unit/test_bedrock_material.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_bedrock_material.gd`:

```gdscript
extends GdUnitTestSuite

func test_bedrock_exists_with_collider() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_BEDROCK).is_greater(0)
	assert_bool(registry.has_collider(registry.MAT_BEDROCK)).is_true()
	assert_bool(registry.has_wall_extension(registry.MAT_BEDROCK)).is_true()

func test_bedrock_is_inert() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.is_flammable(registry.MAT_BEDROCK)).is_false()
	assert_bool(registry.is_fluid(registry.MAT_BEDROCK)).is_false()
	assert_that(registry.get_damage(registry.MAT_BEDROCK)).is_equal(0)

func test_bedrock_is_last_material() -> void:
	# New material appended at the end keeps existing ids stable.
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_BEDROCK).is_equal(registry.materials.size() - 1)
	assert_that(registry.MAT_DUST).is_equal(12)  # pre-existing id unchanged
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_bedrock_material.gd`
Expected: FAIL — `MAT_BEDROCK` does not exist on the registry.

- [ ] **Step 3: Add the material to the registry**

In `src/autoload/material_registry.gd`, add the field declaration alongside the other `var MAT_*` lines (after `var MAT_DUST: int` near line 62):

```gdscript
var MAT_BEDROCK: int
```

Then in `_init_materials()`, after the `mat_dust` block (after the line `MAT_DUST = mat_dust.id`), append:

```gdscript
	var mat_bedrock := MaterialDef.new(
		"BEDROCK", "res://textures/Environments/Walls/stone.png",
		false, 0, 0,
		true, true,
		Color(0.06, 0.06, 0.09, 1.0),  # dark slate tint to read as world-edge wall
		false, 0, 1.0,
		999.0  # hardness irrelevant (never a dig target); high for clarity
	)
	mat_bedrock.id = materials.size()
	materials.append(mat_bedrock)
	MAT_BEDROCK = mat_bedrock.id
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_bedrock_material.gd`
Expected: PASS (all three tests).

- [ ] **Step 5: Regenerate the material shader includes**

Run: `godot --headless --script res://tools/generate_material_glsl.gd`
Expected output includes: `Generated shaders/generated/materials.glslinc` and `Generated shaders/generated/materials.gdshaderinc`.

Verify the new constant exists:

Run: `grep -n "MAT_BEDROCK" shaders/generated/materials.glslinc`
Expected: a line like `const int MAT_BEDROCK = 13;` and `MAT_COUNT = 14`.

- [ ] **Step 6: Guard against regressions in the broader material suite**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_material_hardness.gd`
And: `./addons/gdUnit4/runtest.sh -a tests/unit/test_dust_material.gd`
Expected: PASS (these assert specific ids/values that are unchanged by appending BEDROCK).

- [ ] **Step 7: Commit**

```bash
git add src/autoload/material_registry.gd shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc tests/unit/test_bedrock_material.gd
git commit -m "feat: add indestructible BEDROCK material"
```

---

## Task 2: Make explosions skip bedrock

Bedrock is undiggable by melee/projectiles automatically (those only affect materials passed in an explicit target-mask list, and bedrock is never listed). The one active path that erodes *any* colliding solid is the explosion wave's terrain-chew branch. Guard it.

**Files:**
- Modify: `shaders/include/sim/explode_wave.glslinc`

- [ ] **Step 1: Add the skip guard**

In `shaders/include/sim/explode_wave.glslinc`, find Branch D — the block that begins:

```glsl
	// Branch D: this cell is non-flammable solid touching a wave: chew terrain.
	if (HAS_COLLIDER[material]) {
```

Insert the guard as the first line inside that `if`:

```glsl
	// Branch D: this cell is non-flammable solid touching a wave: chew terrain.
	if (HAS_COLLIDER[material]) {
		if (material == MAT_BEDROCK) return false;  // indestructible world-edge wall
		int max_neighbor_power = 0;
```

(`MAT_BEDROCK` is available because `materials.glslinc` is included before the simulation shader.)

- [ ] **Step 2: Runtime smoke test**

This is a GPU compute change with no unit harness; verify at runtime in Task 7's full playthrough. For now confirm the shader still compiles:

Run: `godot --headless --quit-after 3 2>&1 | grep -i "error\|shader" | head`
Expected: no shader compile errors mentioning `explode_wave` or `generation`.

- [ ] **Step 3: Commit**

```bash
git add shaders/include/sim/explode_wave.glslinc
git commit -m "feat: explosions cannot erode BEDROCK"
```

---

## Task 3: Collapse SectorGrid to a single boss ring

Repoint tests first (red), then change the grid. The grid moves to one ring at distance 8, renames `BOSS_WORLD_EDGE` → `WALL_INNER_SECTORS`, reorders `resolve_sector` so boss anchors (which sit exactly at distance 8) are detected before the wall cutoff, and adds a static tier helper used by Task 5.

**Files:**
- Modify: `tests/unit/test_sector_grid.gd`
- Modify: `src/core/sector_grid.gd`

- [ ] **Step 1: Repoint the sector-grid tests (failing)**

In `tests/unit/test_sector_grid.gd`, add a helper to find a real anchor by scanning (do not hardcode coords), then update the three tests that referenced old-ring coords/constants.

Add this helper method to the suite:

```gdscript
func _first_boss_anchor() -> Vector2i:
	for x in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
		for y in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
			if _SectorGrid.is_boss_anchor(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i.MAX
```

Replace `test_boss_ring_returns_boss_slot`:

```gdscript
func test_boss_ring_returns_boss_slot() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var anchor := _first_boss_anchor()
	assert_that(anchor).is_not_equal(Vector2i.MAX)
	var slot := grid.resolve_sector(anchor)
	assert_that(slot.is_boss).is_true()
```

Replace `test_outside_boss_ring_is_empty`:

```gdscript
func test_outside_boss_ring_is_empty() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	# A non-anchor sector at/after the wall radius is empty (becomes bedrock).
	var slot := grid.resolve_sector(Vector2i(9, 1))  # dist 9 >= wall radius 8, not an anchor
	assert_that(slot.is_empty).is_true()
```

Replace `test_rotation_is_zero_for_non_rotatable`:

```gdscript
func test_rotation_is_zero_for_non_rotatable() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var anchor := _first_boss_anchor()
	var slot := grid.resolve_sector(anchor)  # boss anchor, rotatable=false
	assert_that(slot.rotation).is_equal(0)
```

In `test_resolve_sector_seed_changes`, change the constant name:

```gdscript
			if g1.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.WALL_INNER_SECTORS:
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd`
Expected: FAIL — `WALL_INNER_SECTORS` is not defined yet (and the old `(9,1)` sector currently resolves via room roll, not empty).

- [ ] **Step 3: Update the constants in `src/core/sector_grid.gd`**

Replace lines 4–12:

```gdscript
# Single boss ring at the inner face of the bedrock wall (Chebyshev sector dist).
const BOSS_RING_DISTANCES := [8]
const WALL_INNER_SECTORS := 8        # dist >= this is the indestructible bedrock wall
const BOSS_RING_ANCHOR_COUNT := 12   # boss chambers spread around the wall face
# Per-ring phase (fraction of anchor spacing). One ring => single zero phase.
const BOSS_RING_PHASES := [0.0]
const BOSS_CLAIM_RADIUS := 3
const ELITE_CLAIM_RADIUS := 1
const EMPTY_WEIGHT := 1.5
```

- [ ] **Step 4: Reorder `resolve_sector` so anchors beat the wall cutoff**

In `src/core/sector_grid.gd`, replace the body from the `var dist :=` line through the boss-anchor block (current lines 94–109) with:

```gdscript
	var dist := chebyshev_distance(coord, Vector2i.ZERO)

	# Boss anchors sit exactly on the wall face (dist == WALL_INNER_SECTORS),
	# so they must be detected before the wall cutoff below.
	if is_boss_anchor(coord):
		if _biome.boss_compositions.is_empty():
			slot.is_empty = true
			return slot
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))
		slot.is_boss = true
		slot.template_index = rng.randi() % _biome.boss_compositions.size()
		slot.composition = _biome.boss_compositions[slot.template_index]
		return slot

	if dist >= WALL_INNER_SECTORS:
		slot.is_empty = true  # bedrock wall region (shader fills it); no rooms here
		return slot
```

(Everything below — the claim check, the room-template roll — stays unchanged.)

- [ ] **Step 5: Add the enemy-tier helper (used by Task 5)**

In `src/core/sector_grid.gd`, add at the end of the file:

```gdscript

# Maps a sector's Chebyshev distance from origin (0 .. WALL_INNER_SECTORS) to one of
# three enemy tiers, spread evenly across the central play area.
static func enemy_tier_for_distance(sector_dist: int) -> int:
	return clampi(int(floor(float(sector_dist) / float(WALL_INNER_SECTORS) * 3.0)), 0, 2)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd`
Expected: PASS.

Also run the related grid suites to catch fallout:

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid_claim.gd`
Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid_fixed_anchors.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/sector_grid.gd tests/unit/test_sector_grid.gd
git commit -m "feat: single boss ring at wall face, rename BOSS_WORLD_EDGE"
```

---

## Task 4: Add the bedrock-wall generation stage

**Files:**
- Create: `shaders/include/boss_wall_stage.glslinc`
- Modify: `shaders/compute/generation.glsl`

- [ ] **Step 1: Create the stage include**

Create `shaders/include/boss_wall_stage.glslinc`:

```glsl
// Fills indestructible BEDROCK everywhere at Chebyshev distance >= the boss-wall
// inner radius, turning the world into a walled arena whose only openings are the
// boss chambers. Runs AFTER room stamping / secret rings and BEFORE cavern carve,
// so boss-chamber carving punches the gaps back out of the wall.
//
// BOSS_WALL_INNER_PX must mirror SectorGrid: WALL_INNER_SECTORS (8) * SECTOR_SIZE_PX (384).

const float BOSS_WALL_INNER_PX = 3072.0;

void stage_boss_wall(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);
    float cheb = max(abs(world_pos.x), abs(world_pos.y));
    if (cheb >= BOSS_WALL_INNER_PX) {
        float r = float(MAT_BEDROCK) / 255.0;
        imageStore(chunk_tex, pos, vec4(r, 0.0, 0.0, 0.0));
    }
}
```

- [ ] **Step 2: Wire it into the generation pipeline**

In `shaders/compute/generation.glsl`, add the include after the cavern-carve include (line 23):

```glsl
#include "res://shaders/include/cavern_carve_stage.glslinc"
#include "res://shaders/include/boss_wall_stage.glslinc"
```

Then in `main()`, call `stage_boss_wall` between `stage_secret_ring` and `stage_cavern_carve`:

```glsl
    stage_secret_ring(ctx);
    stage_boss_wall(ctx);
    stage_cavern_carve(ctx);
```

- [ ] **Step 3: Smoke test — shader compiles and world generates**

Run: `godot --headless --quit-after 3 2>&1 | grep -i "error\|shader\|generation" | head`
Expected: no compile/link errors for `generation`.

- [ ] **Step 4: Visual verification**

Launch the project, spawn at center, and walk outward in any direction.
Expected: you reach a solid dark wall ringing the area at ~3072px from origin; the only ways past it are large boss chambers. You can no longer walk out into open void.

Run: launch via the editor or `godot` and observe (no automated assertion).

- [ ] **Step 5: Commit**

```bash
git add shaders/include/boss_wall_stage.glslinc shaders/compute/generation.glsl
git commit -m "feat: bedrock wall generation stage rings the arena"
```

---

## Task 5: Repoint enemy-tier scaling to the wall radius

**Files:**
- Test: `tests/unit/test_enemy_tier_distance.gd` (create)
- Modify: `src/core/spawn_dispatcher.gd:148`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_enemy_tier_distance.gd`:

```gdscript
extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")

func test_tiers_span_zero_to_two_across_central_area() -> void:
	# Distances 0..WALL_INNER_SECTORS map onto tiers 0,1,2 in order, clamped.
	assert_that(_SectorGrid.enemy_tier_for_distance(0)).is_equal(0)
	assert_that(_SectorGrid.enemy_tier_for_distance(2)).is_equal(0)
	assert_that(_SectorGrid.enemy_tier_for_distance(3)).is_equal(1)
	assert_that(_SectorGrid.enemy_tier_for_distance(5)).is_equal(1)
	assert_that(_SectorGrid.enemy_tier_for_distance(6)).is_equal(2)
	assert_that(_SectorGrid.enemy_tier_for_distance(8)).is_equal(2)

func test_tier_is_clamped() -> void:
	assert_that(_SectorGrid.enemy_tier_for_distance(-1)).is_equal(0)
	assert_that(_SectorGrid.enemy_tier_for_distance(99)).is_equal(2)
```

- [ ] **Step 2: Run test to verify it passes already**

`enemy_tier_for_distance` was added in Task 3, so this test should pass immediately — it locks the intended behavior before changing the call site.

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_tier_distance.gd`
Expected: PASS. (If it fails, the helper from Task 3 Step 5 is wrong — fix it there.)

- [ ] **Step 3: Use the helper at the call site**

In `src/core/spawn_dispatcher.gd`, replace line 148:

```gdscript
	var tier_index: int = clampi(int(floor(float(sector_dist) / float(SectorGrid.BOSS_WORLD_EDGE) * 2.0)), 0, 2)
```

with:

```gdscript
	var tier_index: int = SectorGrid.enemy_tier_for_distance(sector_dist)
```

- [ ] **Step 4: Verify nothing else references the old constant**

Run: `grep -rn "BOSS_WORLD_EDGE" src tests`
Expected: no matches (all references repointed).

- [ ] **Step 5: Commit**

```bash
git add src/core/spawn_dispatcher.gd tests/unit/test_enemy_tier_distance.gd
git commit -m "feat: scale enemy tier across central area via wall radius"
```

---

## Task 6: Enlarge boss chambers to ~600px

The 20 boss compositions in `assets/arenas/boss/*.tres` each end with a `[resource]` block carrying `nominal_radius = 300`, `lobing_amplitude = 50`, `inner_disc_radius = 80` (values vary slightly per file). Double them so chambers read as huge Noita-style rooms and reliably breach the wall into the central area.

**Files:**
- Modify: `assets/arenas/boss/caves_a.tres` … `vault_d.tres` (20 files)

- [ ] **Step 1: Inspect current values**

Run: `grep -n "nominal_radius\|lobing_amplitude\|inner_disc_radius" assets/arenas/boss/*.tres`
Expected: each file shows the three fields in its trailing `[resource]` block.

- [ ] **Step 2: Double the three carve fields in every boss composition**

For each of the 20 files, in the final `[resource]` block, set:
- `nominal_radius` → `600`
- `lobing_amplitude` → `100`
- `inner_disc_radius` → `200`

These are the only carve-geometry fields; feature regions (pillars/enemies at radii ≤290) stay inside the larger chamber. Apply per file with an exact edit, e.g. for `caves_a.tres` change:

```
nominal_radius = 300
lobing_amplitude = 50
inner_disc_radius = 80
```
to:
```
nominal_radius = 600
lobing_amplitude = 100
inner_disc_radius = 200
```

Verify all 20 updated:

Run: `grep -c "nominal_radius = 600" assets/arenas/boss/*.tres | grep -v ":1" || echo "all 20 set to 600"`
Expected: `all 20 set to 600` (every file has exactly one match).

- [ ] **Step 3: Visual verification**

Launch the project. Walk to a boss chamber.
Expected: the chamber is a large enclosed room (~1200px across) set into the wall, with the boss inside; its mouth opens into the central cave area.

- [ ] **Step 4: Commit**

```bash
git add assets/arenas/boss
git commit -m "feat: enlarge boss chambers to ~600px radius"
```

---

## Task 7: Repoint the coverage test and verify end-to-end

The old `test_boss_ring_coverage.gd` asserted every radial ray from center crosses a boss arena (the pre-wall guarantee). With a solid wall, the meaningful guarantee is different: exactly `BOSS_RING_ANCHOR_COUNT` chambers sit on the wall face, and no stretch of blank wall between consecutive chambers is too long to traverse.

**Files:**
- Modify: `tests/unit/test_boss_ring_coverage.gd`

- [ ] **Step 1: Rewrite the coverage test (failing on old constants)**

Replace the entire contents of `tests/unit/test_boss_ring_coverage.gd`:

```gdscript
extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")

# Walk the d=8 square perimeter (the inner wall face) clockwise and collect the
# anchor positions along it, so we can measure spacing between chamber openings.
func _perimeter_anchor_steps() -> Array:
	var d := _SectorGrid.WALL_INNER_SECTORS
	var ring: Array = []
	# Top edge L->R, right edge T->B, bottom edge R->L, left edge B->T (no corner dupes).
	for x in range(-d, d):        ring.append(Vector2i(x, -d))
	for y in range(-d, d):        ring.append(Vector2i(d, y))
	for x in range(d, -d, -1):    ring.append(Vector2i(x, d))
	for y in range(d, -d, -1):    ring.append(Vector2i(-d, y))
	var steps: Array = []
	for i in range(ring.size()):
		if _SectorGrid.is_boss_anchor(ring[i]):
			steps.append(i)
	return steps

func test_anchor_count_matches_constant() -> void:
	assert_that(_perimeter_anchor_steps().size()).is_equal(_SectorGrid.BOSS_RING_ANCHOR_COUNT)

func test_no_long_blank_wall_between_chambers() -> void:
	var steps := _perimeter_anchor_steps()
	assert_that(steps.size() > 0).is_true()
	var perim := 8 * _SectorGrid.WALL_INNER_SECTORS  # 64 sectors around the d=8 ring
	var max_gap := 0
	for i in range(steps.size()):
		var a: int = steps[i]
		var b: int = steps[(i + 1) % steps.size()]
		var gap: int = b - a if (i + 1) < steps.size() else (b + perim - a)
		max_gap = max(max_gap, gap)
	# 12 anchors over 64 perimeter sectors => avg ~5.3; no gap may exceed 8 sectors
	# (~3072px of wall) so the player always meets the next chamber quickly.
	assert_that(max_gap).is_less_equal(8)

func test_all_anchors_on_wall_face() -> void:
	for x in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
		for y in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
			if _SectorGrid.is_boss_anchor(Vector2i(x, y)):
				assert_that(max(abs(x), abs(y))).is_equal(_SectorGrid.WALL_INNER_SECTORS)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_ring_coverage.gd`
Expected: PASS. If `test_no_long_blank_wall_between_chambers` fails, the anchor distribution is uneven — bump `BOSS_RING_ANCHOR_COUNT` (Task 3 Step 3) until the max gap ≤ 8, then re-run.

- [ ] **Step 3: Run the full unit suite**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: PASS across the suite (no lingering references to the old ring layout).

- [ ] **Step 4: Full runtime playthrough**

Launch the project and verify the complete behavior:
1. Spawn at center; explore the central cave (normal rooms present).
2. Walk outward in several directions → always hit the bedrock wall, never open void.
3. Follow the wall → reach a large boss chamber within a short walk.
4. Enter, kill the boss → portal spawns; press E → next floor.
5. On the new floor, attack the wall with melee and with an explosive (fire orb) → the wall does not erode.

Expected: all five hold. This is the acceptance check for "bosses are impossible to miss."

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_boss_ring_coverage.gd
git commit -m "test: wall-perimeter chamber coverage replaces radial coverage"
```

---

## Self-Review Notes

- **Spec coverage:** BEDROCK material (Task 1) ✓; explosion guard (Task 2) ✓; `stage_boss_wall` (Task 4) ✓; single ring + `WALL_INNER_SECTORS` rename + no-rooms-past-wall (Task 3) ✓; bigger chambers (Task 6) ✓; tier scaling repoint (Task 5) ✓; test repointing (Tasks 3, 7) ✓. Melee/projectile indestructibility needs no code (opt-in mask) — noted in Task 2 preamble.
- **Risk follow-ups from spec** (lava/biome hazards vs bedrock; corner-anchor opening geometry; chamber overlap) are covered by the Task 4 and Task 6 visual checks and the Task 7 playthrough; if a magma/frozen hazard is observed eroding the wall, apply the same `material == MAT_BEDROCK` guard pattern in the offending sim branch.
- **Constant sync:** `BOSS_WALL_INNER_PX = 3072.0` (shader) must equal `WALL_INNER_SECTORS * SECTOR_SIZE_PX = 8 * 384` (GDScript). Both carry comments pointing at each other.
