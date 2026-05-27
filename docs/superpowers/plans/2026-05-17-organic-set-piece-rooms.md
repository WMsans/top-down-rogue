# Organic Set-Piece Rooms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace rectangular boss-arena (512²) and elite-chest-room (256²) stamps with 2048² and 512² organic carved caverns whose interiors are populated by data-driven `ArenaComposition` resources authored by Claude. Delete the `addons/level_preview` editor plugin as part of this work.

**Architecture:** A new GPU stage (`stage_cavern_carve`) reads a per-chunk cavern SSBO and writes `MAT_AIR` inside an angular-noise-modulated radius around each anchor. A new GDScript pass (`CompositionDispatcher`) hooks to `world_manager.chunks_generated` and walks each composition's `ArenaFeature` list, sampling positions from `ArenaRegion`s and either spawning entities (boss/enemies/barrels/vents/chests) or stamping material discs (pillars/pool patches) into the chunk via existing `world_manager` APIs. `SectorGrid` is updated to space boss anchors every 8th sector around the Chebyshev-10 ring (10 bosses per floor, no overlap) and to mark the 7×7 sector block around each boss as `is_claimed`.

**Tech Stack:** Godot 4.6 (GDScript + GDShader compute), GdUnit4 for tests, `RenderingDevice` low-level API for compute.

**Spec:** `docs/superpowers/specs/2026-05-17-organic-set-piece-rooms-design.md`

---

## File Structure

### New files
| Path | Responsibility |
|---|---|
| `src/core/arena_region.gd` | `ArenaRegion` base class + 4 subclasses (`RegionPoint`, `RegionDisc`, `RegionRing`, `RegionArc`). Each implements `sample(rng) -> Vector2`. |
| `src/core/arena_feature.gd` | `ArenaFeature` base + 7 subclasses (boss-spawn, enemy-pack, pillar-cluster, pool-patch, barrel-cluster, vent, chest-spawn). Each implements `apply(ctx)`. |
| `src/core/arena_composition.gd` | `ArenaComposition` resource — variant id, biome, nominal radius, `features: Array[ArenaFeature]`. |
| `src/core/composition_dispatcher.gd` | Post-gen GDScript pass; evaluates compositions for caverns overlapping freshly-generated chunks. |
| `shaders/include/cavern_carve_stage.glslinc` | GPU stage: angular-noise carve, writes `MAT_AIR` + `NO_PROPS` flag. |
| `assets/arenas/boss/<biome>_<variant>.tres` | 20 boss compositions (5 biomes × 4 variants). |
| `assets/arenas/elite/<biome>_<variant>.tres` | 15 elite compositions (5 biomes × 3 variants). |
| `tests/unit/test_arena_region.gd` | Region sampling tests. |
| `tests/unit/test_arena_composition.gd` | Composition load/serialize tests. |
| `tests/unit/test_sector_grid_claim.gd` | Spaced boss + claim tests (new file to avoid bloating the existing one). |

### Modified files
| Path | Change |
|---|---|
| `project.godot` | Remove `level_preview` from `editor_plugins.enabled`. |
| `addons/level_preview/` | **Deleted entirely.** |
| `src/core/room_template.gd` | Add `cavern_carve: bool`, `composition: Resource` (ArenaComposition). |
| `src/core/biome_def.gd` | Add `boss_compositions: Array[Resource]`. Drop `secret_ring_thickness` (already deleted by Part 2 follow-up if present; verify). |
| `src/core/sector_grid.gd` | Add `is_claimed` to `RoomSlot`; spaced boss selection (every 8th); claim scan for neighbors. |
| `src/core/compute_device.gd` | New `gen_cavern_buffer` (SSBO, set=4); allocate `chunk_flags_tex` companion (set=5); plumb both through `dispatch_generation`. |
| `src/core/chunk_manager.gd` | Build per-batch cavern list from active sectors → pass bytes to `dispatch_generation`. |
| `src/core/world_manager.gd` | Add `read_flag_region(region)` mirror of `read_region`. |
| `shaders/compute/generation.glsl` | `#include` and call `stage_cavern_carve` after `stage_pixel_scene_stamp`; bind cavern SSBO at set=4 and flag image at set=5. |
| `assets/biomes/*.tres` | Add `boss_compositions` array referencing new `.tres` files; add elite composition references. |

### Deleted files
- `addons/level_preview/**` — entire addon directory.

---

## Task 1: Delete `level_preview` addon

**Files:**
- Delete: `addons/level_preview/` (recursive)
- Modify: `project.godot:40`

- [ ] **Step 1: Verify nothing else depends on level_preview**

Run: `grep -rn "level_preview" --include="*.gd" --include="*.tres" --include="*.tscn" src/ assets/ scenes/ tests/`
Expected: no output (already verified during planning).

- [ ] **Step 2: Delete addon directory**

```bash
rm -rf addons/level_preview
```

- [ ] **Step 3: Remove from project.godot enabled plugins**

Modify `project.godot` line 40 from:
```ini
enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg", "res://addons/level_preview/plugin.cfg")
```
to:
```ini
enabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")
```

- [ ] **Step 4: Headless parse check**

Run: `godot --headless --quit 2>&1 | grep -iE "error|level_preview" || echo "clean"`
Expected: `clean` (no errors mentioning level_preview).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete level_preview addon"
```

---

## Task 2: ArenaRegion classes

**Files:**
- Create: `src/core/arena_region.gd`
- Test: `tests/unit/test_arena_region.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_arena_region.gd`:

```gdscript
extends GdUnitTestSuite

const RegionPoint = preload("res://src/core/arena_region.gd").RegionPoint
const RegionDisc = preload("res://src/core/arena_region.gd").RegionDisc
const RegionRing = preload("res://src/core/arena_region.gd").RegionRing
const RegionArc = preload("res://src/core/arena_region.gd").RegionArc

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	return r

func test_point_sample_is_offset() -> void:
	var p := RegionPoint.new()
	p.offset = Vector2(10, -5)
	assert_that(p.sample(_rng())).is_equal(Vector2(10, -5))

func test_disc_sample_within_radius() -> void:
	var d := RegionDisc.new()
	d.center = Vector2(0, 0)
	d.radius = 100.0
	var rng := _rng()
	for i in 64:
		var s: Vector2 = d.sample(rng)
		assert_that(s.length()).is_less_equal(100.0)

func test_ring_sample_in_annulus() -> void:
	var r := RegionRing.new()
	r.center = Vector2.ZERO
	r.r_min = 50.0
	r.r_max = 100.0
	var rng := _rng()
	for i in 64:
		var s: Vector2 = r.sample(rng)
		var d := s.length()
		assert_that(d).is_greater_equal(50.0)
		assert_that(d).is_less_equal(100.0)

func test_arc_sample_within_angle_span() -> void:
	var a := RegionArc.new()
	a.center = Vector2.ZERO
	a.angle = 0.0
	a.span = PI / 2.0       # 90°
	a.r_min = 100.0
	a.r_max = 200.0
	var rng := _rng()
	for i in 64:
		var s: Vector2 = a.sample(rng)
		var theta: float = atan2(s.y, s.x)
		# normalize theta into [-span/2, span/2]
		assert_that(theta).is_greater_equal(-a.span / 2.0 - 1e-3)
		assert_that(theta).is_less_equal(a.span / 2.0 + 1e-3)
		var d := s.length()
		assert_that(d).is_greater_equal(100.0)
		assert_that(d).is_less_equal(200.0)
```

- [ ] **Step 2: Run test — should fail (class missing)**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_arena_region.gd`
Expected: FAIL — preload of `arena_region.gd` errors.

- [ ] **Step 3: Implement `arena_region.gd`**

Create `src/core/arena_region.gd`:

```gdscript
class_name ArenaRegion
extends Resource

## Base class for arena feature regions. Concrete subclasses below.
## `sample(rng)` returns a Vector2 offset relative to the arena center.
func sample(_rng: RandomNumberGenerator) -> Vector2:
	return Vector2.ZERO


class RegionPoint extends ArenaRegion:
	@export var offset: Vector2 = Vector2.ZERO

	func sample(_rng: RandomNumberGenerator) -> Vector2:
		return offset


class RegionDisc extends ArenaRegion:
	@export var center: Vector2 = Vector2.ZERO
	@export var radius: float = 100.0

	func sample(rng: RandomNumberGenerator) -> Vector2:
		var theta: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * radius
		return center + Vector2(cos(theta), sin(theta)) * r


class RegionRing extends ArenaRegion:
	@export var center: Vector2 = Vector2.ZERO
	@export var r_min: float = 100.0
	@export var r_max: float = 200.0

	func sample(rng: RandomNumberGenerator) -> Vector2:
		var theta: float = rng.randf() * TAU
		# Uniform-area sample in annulus.
		var u: float = rng.randf()
		var r: float = sqrt(u * (r_max * r_max - r_min * r_min) + r_min * r_min)
		return center + Vector2(cos(theta), sin(theta)) * r


class RegionArc extends ArenaRegion:
	@export var center: Vector2 = Vector2.ZERO
	@export var angle: float = 0.0       # midline angle (radians)
	@export var span: float = PI / 2.0   # full angular width
	@export var r_min: float = 100.0
	@export var r_max: float = 200.0

	func sample(rng: RandomNumberGenerator) -> Vector2:
		var theta: float = angle + (rng.randf() - 0.5) * span
		var u: float = rng.randf()
		var r: float = sqrt(u * (r_max * r_max - r_min * r_min) + r_min * r_min)
		return center + Vector2(cos(theta), sin(theta)) * r
```

- [ ] **Step 4: Run test — should pass**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_arena_region.gd`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/arena_region.gd tests/unit/test_arena_region.gd
git commit -m "feat(arenas): ArenaRegion resource hierarchy"
```

---

## Task 3: ArenaFeature classes

**Files:**
- Create: `src/core/arena_feature.gd`

- [ ] **Step 1: Create `arena_feature.gd`**

```gdscript
class_name ArenaFeature
extends Resource

## Base class. Concrete subclasses below.
## `region` is the spatial distribution; `apply(ctx)` is called by the dispatcher
## once per feature. Subclasses spawn entities or stamp material via ctx.
##
## ctx is a CompositionContext (see composition_dispatcher.gd):
##   - anchor_world_pos: Vector2 (arena center in world coords)
##   - rng: RandomNumberGenerator
##   - dispatcher: CompositionDispatcher (for entity spawning + material writes)
##   - mask_air: Callable(world_pos) -> bool (checks current carve mask)
@export var region: ArenaRegion

const _AR = preload("res://src/core/arena_region.gd")


func apply(_ctx) -> void:
	pass


# --- Concrete features ---

class FeatureBossSpawn extends ArenaFeature:
	@export var boss_scene: PackedScene
	@export var floor_scaling: bool = true

	func apply(ctx) -> void:
		# Boss is always at the exact arena center (inner-disc air guaranteed).
		ctx.dispatcher.spawn_boss(ctx.anchor_world_pos, boss_scene)


class FeatureEnemyPack extends ArenaFeature:
	@export var enemy_scene: PackedScene
	@export var count: int = 4
	@export var is_elite: bool = false

	func apply(ctx) -> void:
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			ctx.dispatcher.spawn_enemy(pos, enemy_scene, is_elite)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeaturePillarCluster extends ArenaFeature:
	@export var count: int = 6
	@export var pillar_radius_cells: int = 10
	@export var spacing_min: float = 64.0

	func apply(ctx) -> void:
		var placed: Array[Vector2] = []
		for i in count:
			var pos := _try_place(ctx, placed)
			if pos == null:
				continue
			placed.append(pos)
			ctx.dispatcher.stamp_material_disc(pos, pillar_radius_cells, ctx.background_material)

	func _try_place(ctx, placed: Array[Vector2]):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if not ctx.mask_air.call(world):
				continue
			var too_close := false
			for p in placed:
				if p.distance_to(world) < spacing_min:
					too_close = true
					break
			if too_close:
				continue
			return world
		return null


class FeaturePoolPatch extends ArenaFeature:
	@export var material_id: int = 0           # resolved against MaterialRegistry
	@export var count: int = 1
	@export var size_min_cells: int = 6
	@export var size_max_cells: int = 14

	func apply(ctx) -> void:
		if material_id <= 0:
			return  # deferred/uninitialized — skip silently
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			var radius: int = ctx.rng.randi_range(size_min_cells, size_max_cells)
			ctx.dispatcher.stamp_material_disc(pos, radius, material_id)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeatureBarrelCluster extends ArenaFeature:
	@export var barrel_scene: PackedScene  # null = deferred, no-op
	@export var count: int = 3

	func apply(ctx) -> void:
		if barrel_scene == null:
			return
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			ctx.dispatcher.spawn_prop(pos, barrel_scene)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeatureVent extends ArenaFeature:
	@export var vent_scene: PackedScene  # null = deferred, no-op
	@export var count: int = 1

	func apply(ctx) -> void:
		if vent_scene == null:
			return
		for i in count:
			var pos := _sample_air(ctx)
			if pos == null:
				continue
			ctx.dispatcher.spawn_prop(pos, vent_scene)

	func _sample_air(ctx):
		if region == null:
			return null
		for retry in 8:
			var local: Vector2 = region.sample(ctx.rng)
			var world: Vector2 = ctx.anchor_world_pos + local
			if ctx.mask_air.call(world):
				return world
		return null


class FeatureChestSpawn extends ArenaFeature:
	@export var rare: bool = false

	func apply(ctx) -> void:
		# Always at exact arena center.
		ctx.dispatcher.spawn_chest(ctx.anchor_world_pos, rare)
```

- [ ] **Step 2: Commit (no test yet; tested integratively in Task 10)**

```bash
git add src/core/arena_feature.gd
git commit -m "feat(arenas): ArenaFeature class hierarchy"
```

---

## Task 4: ArenaComposition resource

**Files:**
- Create: `src/core/arena_composition.gd`
- Test: `tests/unit/test_arena_composition.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_arena_composition.gd`:

```gdscript
extends GdUnitTestSuite

const ArenaComposition = preload("res://src/core/arena_composition.gd")
const ArenaFeature = preload("res://src/core/arena_feature.gd")

func test_composition_defaults() -> void:
	var c: ArenaComposition = ArenaComposition.new()
	assert_that(c.arena_kind).is_equal(&"boss")
	assert_that(c.features.size()).is_equal(0)

func test_composition_holds_features() -> void:
	var c: ArenaComposition = ArenaComposition.new()
	var f := ArenaFeature.FeatureBossSpawn.new()
	c.features.append(f)
	assert_that(c.features.size()).is_equal(1)
```

- [ ] **Step 2: Run test — should fail**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_arena_composition.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `src/core/arena_composition.gd`:

```gdscript
class_name ArenaComposition
extends Resource

@export var arena_kind: StringName = &"boss"   # &"boss" or &"elite"
@export var biome: StringName = &""            # caves / mines / magma / frozen / vault
@export var variant_id: StringName = &"a"
@export var nominal_radius: int = 960
@export var lobing_amplitude: int = 160
@export var inner_disc_radius: int = 256
@export var features: Array[ArenaFeature] = []
```

- [ ] **Step 4: Run test — should pass**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_arena_composition.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/arena_composition.gd tests/unit/test_arena_composition.gd
git commit -m "feat(arenas): ArenaComposition resource"
```

---

## Task 5: RoomTemplate + BiomeDef schema updates

**Files:**
- Modify: `src/core/room_template.gd`
- Modify: `src/core/biome_def.gd`

- [ ] **Step 1: Update RoomTemplate**

Replace `src/core/room_template.gd`:

```gdscript
class_name RoomTemplate
extends Resource

@export var png_path: String = ""
@export var weight: float = 1.0
@export var size_class: int = 64
@export var is_secret: bool = false
@export var is_boss: bool = false
@export var is_elite_chest: bool = false
@export var rotatable: bool = true
@export var cavern_carve: bool = false
@export var composition: Resource = null   # ArenaComposition when cavern_carve = true
```

- [ ] **Step 2: Update BiomeDef**

Replace `src/core/biome_def.gd`:

```gdscript
class_name BiomeDef
extends Resource

@export var display_name: String = ""
@export var cave_noise_scale: float = 0.008
@export var cave_threshold: float = 0.42
@export var ridge_weight: float = 0.3
@export var ridge_scale: float = 0.012
@export var octaves: int = 5
@export var background_material: int = 2  # STONE
@export var pool_materials: Array[PoolDef] = []
@export var room_templates: Array[RoomTemplate] = []
@export var boss_compositions: Array[Resource] = []   # ArenaComposition list, replaces boss_templates
@export var secret_ring_thickness: int = 3            # secret system unchanged
@export var tint: Color = Color.WHITE
@export var cave_spawn_rate: float = 1.0
@export var enemy_pool: Array[PackedScene] = []
@export var elite_chance: float = 0.15
@export var boss_scene: PackedScene = null
```

(`boss_templates` field is removed; existing `assets/biomes/*.tres` files will lose that array when re-saved in Task 14.)

- [ ] **Step 3: Run all existing tests — they may still pass against the schema change**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_biome_def.gd -a tests/unit/test_sector_grid.gd`
Expected: existing tests that don't reference `boss_templates` PASS. Tests that reference `boss_templates` may FAIL — those will be rewritten in Task 6.

- [ ] **Step 4: Commit**

```bash
git add src/core/room_template.gd src/core/biome_def.gd
git commit -m "feat(arenas): RoomTemplate.cavern_carve flag and BiomeDef.boss_compositions"
```

---

## Task 6: SectorGrid — spaced boss selection and claim mechanic

**Files:**
- Modify: `src/core/sector_grid.gd`
- Modify: `tests/unit/test_sector_grid.gd`
- Create: `tests/unit/test_sector_grid_claim.gd`

- [ ] **Step 1: Write new failing test file**

Create `tests/unit/test_sector_grid_claim.gd`:

```gdscript
extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

func _biome_with_one_boss_comp() -> Resource:
	var b: Resource = _BiomeDef.new()
	var comp: Resource = _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b

func test_boss_anchor_at_spaced_offset_only() -> void:
	# Anchor selection walks the Chebyshev-10 ring clockwise from (10,-10).
	# Every 8th step is a boss anchor.
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	# Anchor 0 → (10, -10)
	var s0 := grid.resolve_sector(Vector2i(10, -10))
	assert_that(s0.is_boss).is_true()
	# Step 1 → (10, -9): not anchor; claimed by anchor 0 (chebyshev distance ≤ 3)
	var s1 := grid.resolve_sector(Vector2i(10, -9))
	assert_that(s1.is_boss).is_false()
	assert_that(s1.is_claimed).is_true()

func test_boss_anchor_count_per_floor() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	var count := 0
	# Walk full Chebyshev-10 ring (80 sectors)
	for coord in _ring10_coords():
		if grid.resolve_sector(coord).is_boss:
			count += 1
	assert_that(count).is_equal(10)

func test_non_anchor_ring10_sectors_empty_or_claimed() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	for coord in _ring10_coords():
		var slot := grid.resolve_sector(coord)
		if not slot.is_boss:
			assert_that(slot.is_empty or slot.is_claimed).is_true()

func test_claim_extends_to_inner_neighbors() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	# (10, -10) is the first anchor; (9, -9) is at Chebyshev 1 from it → claimed.
	var s := grid.resolve_sector(Vector2i(9, -9))
	assert_that(s.is_claimed).is_true()
	assert_that(s.is_empty).is_true()

func _ring10_coords() -> Array[Vector2i]:
	# Returns 80 sectors at Chebyshev distance 10 from origin in clockwise order
	# starting at (10, -10).
	var out: Array[Vector2i] = []
	# top row: y=-10, x from -10..10 inclusive (right-to-left after start? — see grid for spec)
	# Simpler: enumerate all sectors with Chebyshev = 10 and sort by clockwise order.
	for x in range(-10, 11):
		for y in range(-10, 11):
			if max(abs(x), abs(y)) == 10:
				out.append(Vector2i(x, y))
	out.sort_custom(func(a, b): return _clockwise_index(a) < _clockwise_index(b))
	return out

static func _clockwise_index(c: Vector2i) -> int:
	# Clockwise from (10, -10): right edge top→bottom, bottom edge right→left,
	# left edge bottom→top, top edge left→right.
	if c.x == 10:  return c.y + 10                # 0..20 (top-right to bottom-right)
	if c.y == 10:  return 20 + (10 - c.x)          # 20..40 (bottom-right to bottom-left)
	if c.x == -10: return 40 + (10 - c.y)          # 40..60 (bottom-left to top-left)
	return 60 + (c.x + 10)                         # 60..80 (top-left to top-right)
```

- [ ] **Step 2: Run new tests — should fail**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid_claim.gd`
Expected: FAIL — `is_claimed` does not exist on `RoomSlot`, behavior not implemented.

- [ ] **Step 3: Update sector_grid.gd**

Replace `src/core/sector_grid.gd`:

```gdscript
class_name SectorGrid

const SECTOR_SIZE_PX := 384
const BOSS_RING_DISTANCE := 10
const BOSS_RING_STRIDE := 8           # every Nth ring sector is a boss anchor
const BOSS_CLAIM_RADIUS := 3          # Chebyshev radius around each boss anchor
const ELITE_CLAIM_RADIUS := 1         # for elite-cavern templates
const EMPTY_WEIGHT := 1.5

class RoomSlot:
	var is_empty: bool = false
	var is_boss: bool = false
	var is_claimed: bool = false
	var template_index: int = -1
	var rotation: int = 0
	var template_size: int = 0
	var composition: Resource = null

var _seed: int
var _biome: BiomeDef


func _init(world_seed: int, biome: BiomeDef) -> void:
	_seed = world_seed
	_biome = biome


func world_to_sector(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / SECTOR_SIZE_PX),
		floori(world_pos.y / SECTOR_SIZE_PX)
	)


func sector_to_world_center(coord: Vector2i) -> Vector2i:
	return Vector2i(
		coord.x * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2,
		coord.y * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2
	)


func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))


# Clockwise index 0..79 along the Chebyshev-10 ring, starting at (10, -10).
static func _ring_index(coord: Vector2i) -> int:
	if coord.x == BOSS_RING_DISTANCE:  return coord.y + BOSS_RING_DISTANCE                   # 0..20
	if coord.y == BOSS_RING_DISTANCE:  return 20 + (BOSS_RING_DISTANCE - coord.x)            # 20..40
	if coord.x == -BOSS_RING_DISTANCE: return 40 + (BOSS_RING_DISTANCE - coord.y)            # 40..60
	return 60 + (coord.x + BOSS_RING_DISTANCE)                                                # 60..80


static func is_boss_anchor(coord: Vector2i) -> bool:
	if max(abs(coord.x), abs(coord.y)) != BOSS_RING_DISTANCE:
		return false
	return (_ring_index(coord) % BOSS_RING_STRIDE) == 0


# Find any boss anchor whose claim block includes `coord`. Returns the anchor
# coord, or Vector2i.MAX if none.
func _find_claiming_anchor(coord: Vector2i) -> Vector2i:
	for dx in range(-BOSS_CLAIM_RADIUS, BOSS_CLAIM_RADIUS + 1):
		for dy in range(-BOSS_CLAIM_RADIUS, BOSS_CLAIM_RADIUS + 1):
			var candidate := coord + Vector2i(dx, dy)
			if is_boss_anchor(candidate):
				return candidate
	return Vector2i.MAX


func resolve_sector(coord: Vector2i) -> RoomSlot:
	var slot := RoomSlot.new()
	var dist := chebyshev_distance(coord, Vector2i.ZERO)

	if dist > BOSS_RING_DISTANCE:
		slot.is_empty = true
		return slot

	# 1. Boss anchor itself.
	if dist == BOSS_RING_DISTANCE and is_boss_anchor(coord):
		if _biome.boss_compositions.is_empty():
			slot.is_empty = true
			return slot
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))
		slot.is_boss = true
		slot.template_index = rng.randi() % _biome.boss_compositions.size()
		slot.composition = _biome.boss_compositions[slot.template_index]
		return slot

	# 2. Claimed by a boss anchor.
	var anchor := _find_claiming_anchor(coord)
	if anchor != Vector2i.MAX:
		slot.is_empty = true
		slot.is_claimed = true
		return slot

	# 3. Regular template roll (elite + normal rooms).
	if _biome.room_templates.is_empty():
		slot.is_empty = true
		return slot

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash(_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663))
	var total := EMPTY_WEIGHT
	for tmpl in _biome.room_templates:
		total += (tmpl as RoomTemplate).weight
	var roll := rng2.randf() * total
	if roll < EMPTY_WEIGHT:
		slot.is_empty = true
		return slot
	var cumulative := EMPTY_WEIGHT
	for i in range(_biome.room_templates.size()):
		cumulative += (_biome.room_templates[i] as RoomTemplate).weight
		if roll < cumulative:
			slot.template_index = i
			var tmpl: RoomTemplate = _biome.room_templates[i]
			slot.rotation = (rng2.randi() % 4) * 90 if tmpl.rotatable else 0
			slot.template_size = tmpl.size_class
			if tmpl.cavern_carve:
				slot.composition = tmpl.composition
			return slot

	slot.is_empty = true
	return slot


func get_template_for_slot(slot: RoomSlot) -> RoomTemplate:
	if slot.is_empty or slot.is_boss:
		return null
	return _biome.room_templates[slot.template_index]
```

- [ ] **Step 4: Update existing test_sector_grid.gd to match new API**

The old test built a biome with `boss_templates`; switch to `boss_compositions`. Replace the `_make_biome()` function in `tests/unit/test_sector_grid.gd` (lines 7-21) with:

```gdscript
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

func _make_biome() -> Resource:
	var b: Resource = _BiomeDef.new()
	var rt: Resource = _RoomTemplate.new()
	rt.png_path = "rt0"
	rt.weight = 1.0
	var rt2: Resource = _RoomTemplate.new()
	rt2.png_path = "rt1"
	rt2.weight = 2.0
	b.room_templates = [rt, rt2]
	var comp: Resource = _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b
```

Also: the existing test `test_boss_ring_returns_boss_slot` uses `Vector2i(10, 0)`. After spacing, (10, 0) is NOT a boss anchor — anchor 0 is (10, -10), and stride 8 gives anchors at ring indices 0, 8, 16, 24, ... `(10, 0)` is at ring index 10 — not divisible by 8 → not an anchor. **Update that test** to use `(10, -10)`:

```gdscript
func test_boss_ring_returns_boss_slot() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var slot := grid.resolve_sector(Vector2i(10, -10))
	assert_that(slot.is_boss).is_true()
```

- [ ] **Step 5: Run all sector_grid tests**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd -a tests/unit/test_sector_grid_claim.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/core/sector_grid.gd tests/unit/test_sector_grid.gd tests/unit/test_sector_grid_claim.gd
git commit -m "feat(arenas): spaced boss anchors and claim-block mechanic in SectorGrid"
```

---

## Task 7: Cavern carve GLSL stage

**Files:**
- Create: `shaders/include/cavern_carve_stage.glslinc`
- Modify: `shaders/compute/generation.glsl`

- [ ] **Step 1: Create the carve include**

Create `shaders/include/cavern_carve_stage.glslinc`:

```glsl
// Carves organic caverns at registered anchors. Each cavern is parameterized by
// center, base radius, lobing amplitude, inner disc radius, and angular noise seed.
// Buffer at set=4 binding=0. Compatible with materials.glslinc and Context.

layout(set = 4, binding = 0, std430) readonly buffer CavernBuffer {
    int count;
    int _pad[3];
    // Each cavern packed as two vec4s:
    //   c0: center.xy, base_radius, lobing_amplitude
    //   c1: inner_disc_radius, noise_seed, _pad, _pad
    vec4 caverns[64];
} cavern_buf;

// Periodic 1D noise over angle. 4-harmonic sine sum with seeded phase/amplitude.
float cavern_angular_noise(float theta, float seed) {
    float n = 0.0;
    for (int k = 1; k <= 4; k++) {
        float phase = fract(sin(seed * 12.9898 + float(k) * 78.233) * 43758.5453) * 6.28318530718;
        float amp   = (1.0 / float(k));
        n += amp * sin(float(k) * theta + phase);
    }
    return n * 0.5;  // ≈ [-1, 1]
}

// Returns true if this cell is inside any cavern's carve region (interior or guaranteed disc).
// `out_in_inner` set when inside the hard-guaranteed inner disc.
bool cavern_carves_cell(vec2 world_pos, out bool out_in_inner) {
    out_in_inner = false;
    for (int i = 0; i < cavern_buf.count; i++) {
        vec4 c0 = cavern_buf.caverns[i * 2 + 0];
        vec4 c1 = cavern_buf.caverns[i * 2 + 1];
        vec2 center = c0.xy;
        float base_r = c0.z;
        float lobing = c0.w;
        float inner_r = c1.x;
        float noise_seed = c1.y;

        vec2 d = world_pos - center;
        float dist = length(d);
        if (dist < inner_r) {
            out_in_inner = true;
            return true;
        }
        if (dist >= base_r + lobing + 4.0) continue;  // outside max reach

        float theta = atan(d.y, d.x);
        float r = base_r + cavern_angular_noise(theta, noise_seed) * lobing;
        if (dist < r - 16.0) {
            return true;
        }
    }
    return false;
}

void stage_cavern_carve(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    vec2 world_pos = vec2(ctx.chunk_coord * 256) + vec2(pos);

    bool in_inner = false;
    if (cavern_carves_cell(world_pos, in_inner)) {
        imageStore(chunk_tex, pos, vec4(0.0, 0.0, 0.0, 0.0));  // MAT_AIR = 0
        // NO_PROPS write: deferred to Task 9 (flag_tex). For now, this stage
        // only writes MAT_AIR.
    }
}
```

- [ ] **Step 2: Wire into `generation.glsl`**

Modify `shaders/compute/generation.glsl`. Add the `#include` (before `void main()`) and the stage call. After:

```glsl
#include "res://shaders/include/secret_ring_stage.glslinc"
```

Add:

```glsl
#include "res://shaders/include/cavern_carve_stage.glslinc"
```

And in `void main()`, after `stage_secret_ring(ctx);`, append:

```glsl
    stage_cavern_carve(ctx);
```

(The carve runs *after* stamps so it overrides any rectangular wall stamps that may have been placed on a claimed sector — defensive.)

- [ ] **Step 3: Commit (compile verified in Task 8 after CPU plumbing)**

```bash
git add shaders/include/cavern_carve_stage.glslinc shaders/compute/generation.glsl
git commit -m "feat(arenas): cavern carve GPU stage"
```

---

## Task 8: CPU-side cavern SSBO plumbing

**Files:**
- Modify: `src/core/compute_device.gd`
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Add cavern buffer to compute_device**

In `src/core/compute_device.gd`, near the existing `STAMP_BUFFER_SIZE` declaration, add:

```gdscript
const CAVERN_BUFFER_SIZE := 16 + 64 * 2 * 16   # header (4 ints) + 64 caverns × 2 vec4s
var gen_cavern_buffer: RID
var gen_cavern_uniform_set: RID
```

Add an init function next to `init_gen_stamp_buffer`:

```gdscript
func init_gen_cavern_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(CAVERN_BUFFER_SIZE)
	zero.fill(0)
	gen_cavern_buffer = rd.storage_buffer_create(CAVERN_BUFFER_SIZE, zero)

	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = 0
	u.add_id(gen_cavern_buffer)
	gen_cavern_uniform_set = rd.uniform_set_create([u], gen_shader, 4)
```

Find the existing `_ready` or init-sequence call site for `init_gen_stamp_buffer()` (search for `init_gen_stamp_buffer`) and add a matching call to `init_gen_cavern_buffer()` immediately after.

Find the free path (search for `if gen_stamp_buffer.is_valid():`) and add:

```gdscript
	if gen_cavern_buffer.is_valid():
		rd.free_rid(gen_cavern_buffer)
		gen_cavern_buffer = RID()
```

- [ ] **Step 2: Update `dispatch_generation` signature and body**

In `src/core/compute_device.gd`, replace the existing `dispatch_generation` signature:

```gdscript
func dispatch_generation(
	chunks: Dictionary,
	new_coords: Array[Vector2i],
	seed_val: int,
	stamp_bytes: PackedByteArray = PackedByteArray(),
	cavern_bytes: PackedByteArray = PackedByteArray()
) -> Array[RID]:
```

After the existing stamp buffer upload, add:

```gdscript
	# Upload cavern buffer
	var cav_upload := cavern_bytes
	if cav_upload.size() < CAVERN_BUFFER_SIZE:
		cav_upload = cavern_bytes.duplicate()
		cav_upload.resize(CAVERN_BUFFER_SIZE)
	rd.buffer_update(gen_cavern_buffer, 0, CAVERN_BUFFER_SIZE, cav_upload)
```

After the existing `rd.compute_list_bind_uniform_set(compute_list, gen_biome_uniform_set, 2)` line, add:

```gdscript
	if gen_cavern_uniform_set.is_valid():
		rd.compute_list_bind_uniform_set(compute_list, gen_cavern_uniform_set, 4)
```

- [ ] **Step 3: Build cavern bytes in chunk_manager**

In `src/core/chunk_manager.gd`, near the top, add:

```gdscript
const _ArenaComposition = preload("res://src/core/arena_composition.gd")
```

Add a helper method:

```gdscript
func _build_cavern_bytes(new_chunks: Array[Vector2i]) -> PackedByteArray:
	# Collect distinct cavern anchors whose footprint overlaps any new chunk.
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null:
		return PackedByteArray()
	var anchors: Dictionary = {}  # Vector2i sector → ArenaComposition
	for chunk_coord in new_chunks:
		var chunk_world := chunk_coord * world_manager.CHUNK_SIZE
		# Scan a generous neighborhood of sectors that could carve into this chunk.
		# Max reach ≈ base_r + lobing ≈ 1120 px = 3 sectors.
		var min_s := grid.world_to_sector(Vector2(chunk_world.x - 1120, chunk_world.y - 1120))
		var max_s := grid.world_to_sector(Vector2(chunk_world.x + world_manager.CHUNK_SIZE + 1120, chunk_world.y + world_manager.CHUNK_SIZE + 1120))
		for sx in range(min_s.x, max_s.x + 1):
			for sy in range(min_s.y, max_s.y + 1):
				var sector := Vector2i(sx, sy)
				if anchors.has(sector):
					continue
				var slot := grid.resolve_sector(sector)
				var comp: Resource = slot.composition
				if comp == null:
					continue
				if not slot.is_boss and not (slot.template_index >= 0 and (grid.get_template_for_slot(slot) as RoomTemplate).cavern_carve):
					continue
				anchors[sector] = comp

	var bytes := PackedByteArray()
	bytes.resize(16 + 64 * 32)
	bytes.fill(0)
	var count: int = min(anchors.size(), 64)
	bytes.encode_s32(0, count)
	var i := 0
	for sector in anchors:
		if i >= 64:
			break
		var comp: ArenaComposition = anchors[sector]
		var center := Vector2(grid.sector_to_world_center(sector))
		var base_r: float = float(comp.nominal_radius)
		var lobing: float = float(comp.lobing_amplitude)
		var inner_r: float = float(comp.inner_disc_radius)
		var noise_seed: float = float(hash(sector.x * 73856093 ^ sector.y * 19349663) & 0xFFFFFF)
		var off := 16 + i * 32
		bytes.encode_float(off + 0,  center.x)
		bytes.encode_float(off + 4,  center.y)
		bytes.encode_float(off + 8,  base_r)
		bytes.encode_float(off + 12, lobing)
		bytes.encode_float(off + 16, inner_r)
		bytes.encode_float(off + 20, noise_seed)
		i += 1
	return bytes
```

Modify `generate_chunks_at` — find the call site of `world_manager.compute_device.dispatch_generation(chunks, new_chunks, seed_val)` and replace with:

```gdscript
	var stamp_bytes := _build_stamp_bytes(new_chunks)
	var cavern_bytes := _build_cavern_bytes(new_chunks)
	world_manager._gen_uniform_sets_to_free = world_manager.compute_device.dispatch_generation(chunks, new_chunks, seed_val, stamp_bytes, cavern_bytes)
```

If `_build_stamp_bytes` does not yet exist, locate the existing stamp-building code (search `stamp_bytes` or `stamp_buf` callers in `chunk_manager.gd`) and extract it; otherwise pass `PackedByteArray()` as a placeholder.

- [ ] **Step 4: Launch the game (smoke check)**

Run: `godot --headless --quit 2>&1 | grep -iE "error|warning" | head -20`
Expected: clean, or warnings unrelated to caverns. If the cavern_compositions array is empty in biomes (Task 14 not done yet), `count=0` and no caverns are dispatched — chunk gen should behave identically to pre-change.

- [ ] **Step 5: Commit**

```bash
git add src/core/compute_device.gd src/core/chunk_manager.gd
git commit -m "feat(arenas): per-chunk cavern SSBO plumbing"
```

---

## Task 9: chunk_flags_tex (NO_PROPS mask)

**Files:**
- Modify: `src/core/chunk.gd`
- Modify: `src/core/compute_device.gd`
- Modify: `src/core/world_manager.gd`
- Modify: `shaders/compute/generation.glsl`
- Modify: `shaders/include/cavern_carve_stage.glslinc`

- [ ] **Step 1: Allocate companion texture in Chunk**

In `src/core/chunk.gd`, locate where `rd_texture` is allocated (the main chunk image). Below it, add a parallel R8 storage texture `rd_flag_texture`:

```gdscript
var rd_flag_texture: RID = RID()

func create_flag_texture(rd: RenderingDevice, size: int) -> void:
	var tf := RDTextureFormat.new()
	tf.width = size
	tf.height = size
	tf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var zero := PackedByteArray()
	zero.resize(size * size)
	zero.fill(0)
	rd_flag_texture = rd.texture_create(tf, RDTextureView.new(), [zero])
```

Call `create_flag_texture(rd, CHUNK_SIZE)` wherever `rd_texture` is created. On chunk free, also free `rd_flag_texture` if valid.

- [ ] **Step 2: Bind flag texture in dispatch_generation (set=5)**

In `src/core/compute_device.gd`, inside the per-chunk loop in `dispatch_generation`, after creating the existing chunk uniform set, add a second uniform set for the flag image:

```gdscript
		var flag_uniform := RDUniform.new()
		flag_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		flag_uniform.binding = 0
		flag_uniform.add_id(chunk.rd_flag_texture)
		var flag_uniform_set := rd.uniform_set_create([flag_uniform], gen_shader, 5)
		created_uniform_sets.append(flag_uniform_set)
		rd.compute_list_bind_uniform_set(compute_list, flag_uniform_set, 5)
```

- [ ] **Step 3: Declare and write the flag image in the shader**

In `shaders/compute/generation.glsl`, near the existing `chunk_tex` declaration, add:

```glsl
layout(r8, set = 5, binding = 0) uniform image2D chunk_flag_tex;
```

In `shaders/include/cavern_carve_stage.glslinc`, replace the comment-only NO_PROPS line in `stage_cavern_carve` with an actual write. After `imageStore(chunk_tex, pos, vec4(0.0, 0.0, 0.0, 0.0));` add:

```glsl
        imageStore(chunk_flag_tex, pos, vec4(1.0 / 255.0, 0.0, 0.0, 0.0));  // bit 0 = NO_PROPS
```

(The flag image is `r8_unorm` so writing 1/255 ≈ byte 1.)

- [ ] **Step 4: Add `read_flag_region` to world_manager**

In `src/core/world_manager.gd`, immediately after `read_region`, add:

```gdscript
func read_flag_region(region: Rect2i) -> PackedByteArray:
	var width: int = region.size.x
	var height: int = region.size.y
	var result := PackedByteArray()
	result.resize(width * height)
	result.fill(0)

	var min_chunk := Vector2i(floori(float(region.position.x) / CHUNK_SIZE), floori(float(region.position.y) / CHUNK_SIZE))
	var max_chunk := Vector2i(floori(float(region.end.x - 1) / CHUNK_SIZE), floori(float(region.end.y - 1) / CHUNK_SIZE))

	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var chunk_coord := Vector2i(cx, cy)
			if not chunks.has(chunk_coord):
				continue
			var chunk: Chunk = chunks[chunk_coord]
			if not chunk.rd_flag_texture.is_valid():
				continue
			var chunk_data: PackedByteArray = rd.texture_get_data(chunk.rd_flag_texture, 0)
			var chunk_origin := chunk_coord * CHUNK_SIZE
			var chunk_rect := Rect2i(chunk_origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			var overlap := region.intersection(chunk_rect)
			for y in range(overlap.position.y, overlap.end.y):
				for x in range(overlap.position.x, overlap.end.x):
					var local_x: int = x - chunk_origin.x
					var local_y: int = y - chunk_origin.y
					var src_idx: int = local_y * CHUNK_SIZE + local_x
					var dst_x: int = x - region.position.x
					var dst_y: int = y - region.position.y
					result[dst_y * width + dst_x] = chunk_data[src_idx]
	return result
```

- [ ] **Step 5: Smoke check**

Run: `godot --headless --quit 2>&1 | head -40`
Expected: no shader compile errors, no missing-binding errors.

- [ ] **Step 6: Commit**

```bash
git add src/core/chunk.gd src/core/compute_device.gd src/core/world_manager.gd shaders/compute/generation.glsl shaders/include/cavern_carve_stage.glslinc
git commit -m "feat(arenas): chunk_flags_tex NO_PROPS mask written by cavern carve"
```

---

## Task 10: CompositionDispatcher

**Files:**
- Create: `src/core/composition_dispatcher.gd`
- Modify: `project.godot` (autoload)
- Modify: `src/core/spawn_dispatcher.gd` (skip cavern slots)

- [ ] **Step 1: Create the dispatcher**

Create `src/core/composition_dispatcher.gd`:

```gdscript
extends Node

const CHUNK_SIZE := 256
const _ArenaFeature = preload("res://src/core/arena_feature.gd")

class CompositionContext:
	var anchor_world_pos: Vector2
	var rng: RandomNumberGenerator
	var dispatcher: Node
	var mask_air: Callable
	var background_material: int = 2

var _dispatched_anchors: Dictionary = {}  # sector_coord → true
var _world_manager: Node = null
var _spawn_parent: Node = null


func _process(_delta: float) -> void:
	if _world_manager != null and is_instance_valid(_world_manager):
		return
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm == null:
		return
	_world_manager = wm
	_spawn_parent = _world_manager.get_chunk_container()
	_dispatched_anchors.clear()
	_world_manager.chunks_generated.connect(_on_chunks_generated)


func clear() -> void:
	_dispatched_anchors.clear()


func _on_chunks_generated(new_coords: Array[Vector2i]) -> void:
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null:
		return
	for chunk_coord in new_coords:
		var chunk_world := chunk_coord * CHUNK_SIZE
		# Scan sectors whose anchor could overlap this chunk (reach ≈ 3 sectors).
		var min_s := grid.world_to_sector(Vector2(chunk_world.x - 1120, chunk_world.y - 1120))
		var max_s := grid.world_to_sector(Vector2(chunk_world.x + CHUNK_SIZE + 1120, chunk_world.y + CHUNK_SIZE + 1120))
		for sx in range(min_s.x, max_s.x + 1):
			for sy in range(min_s.y, max_s.y + 1):
				var sector := Vector2i(sx, sy)
				if _dispatched_anchors.has(sector):
					continue
				var slot := grid.resolve_sector(sector)
				if slot.composition == null:
					continue
				# Only dispatch when the anchor's chunk is part of new_coords —
				# otherwise we may try to write into a chunk that hasn't been
				# generated yet. The anchor chunk contains the inner disc, which
				# is the only cell we strictly need spawn-time access to.
				var anchor_chunk := grid.world_to_sector(Vector2(grid.sector_to_world_center(sector)))
				var anchor_chunk_coord := Vector2i(
					floori(grid.sector_to_world_center(sector).x / float(CHUNK_SIZE)),
					floori(grid.sector_to_world_center(sector).y / float(CHUNK_SIZE)),
				)
				if anchor_chunk_coord != chunk_coord:
					continue
				_dispatched_anchors[sector] = true
				_evaluate_composition(grid, sector, slot)


func _evaluate_composition(grid: SectorGrid, sector: Vector2i, slot) -> void:
	var comp: ArenaComposition = slot.composition
	if comp == null:
		return
	var anchor_world := Vector2(grid.sector_to_world_center(sector))
	var biome: BiomeDef = LevelManager.current_biome
	var background_mat: int = biome.background_material if biome else 2
	for i in comp.features.size():
		var f: ArenaFeature = comp.features[i]
		if f == null:
			continue
		var ctx := CompositionContext.new()
		ctx.anchor_world_pos = anchor_world
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.seed = hash(LevelManager.world_seed ^ sector.x * 73856093 ^ sector.y * 19349663 ^ i)
		ctx.dispatcher = self
		ctx.background_material = background_mat
		ctx.mask_air = func(world_pos: Vector2) -> bool:
			return _is_air(world_pos)
		f.apply(ctx)


func _is_air(world_pos: Vector2) -> bool:
	var ipos := Vector2i(floori(world_pos.x), floori(world_pos.y))
	var data: PackedByteArray = _world_manager.read_region(Rect2i(ipos, Vector2i(1, 1)))
	if data.size() == 0:
		return false
	return data[0] == MaterialRegistry.MAT_AIR


# --- Dispatcher API consumed by ArenaFeature subclasses ---

func spawn_boss(world_pos: Vector2, boss_scene: PackedScene) -> void:
	if boss_scene == null:
		return
	var inst := boss_scene.instantiate()
	inst.global_position = world_pos
	_spawn_parent.add_child(inst)

func spawn_enemy(world_pos: Vector2, enemy_scene: PackedScene, is_elite: bool) -> void:
	if enemy_scene == null:
		return
	var inst := enemy_scene.instantiate()
	if is_elite and "is_elite" in inst:
		inst.is_elite = true
	inst.global_position = world_pos
	_spawn_parent.add_child(inst)

func spawn_prop(world_pos: Vector2, prop_scene: PackedScene) -> void:
	if prop_scene == null:
		return
	var inst := prop_scene.instantiate()
	inst.global_position = world_pos
	_spawn_parent.add_child(inst)

func spawn_chest(world_pos: Vector2, rare: bool) -> void:
	const CHEST_SCENE = preload("res://scenes/chest.tscn")
	var chest := CHEST_SCENE.instantiate()
	chest.global_position = world_pos
	if rare and "rare_drop" in chest:
		chest.rare_drop = true
	_spawn_parent.add_child(chest)

func stamp_material_disc(world_pos: Vector2, radius_cells: int, material_id: int) -> void:
	if _world_manager == null or material_id <= 0:
		return
	_world_manager.place_material(world_pos, float(radius_cells), material_id)
```

- [ ] **Step 2: Register as autoload**

In `project.godot`, append to the `[autoload]` section:

```ini
CompositionDispatcher="*res://src/core/composition_dispatcher.gd"
```

- [ ] **Step 3: Make spawn_dispatcher skip cavern slots**

In `src/core/spawn_dispatcher.gd`, find `_spawn_for_slot` and add an early return for cavern-driven slots. Immediately after the `var tmpl: RoomTemplate = grid.get_template_for_slot(slot)` line:

```gdscript
	if tmpl == null:
		return
	if tmpl.cavern_carve:
		return  # CompositionDispatcher handles cavern interiors
```

Also: spawn_dispatcher's per-sector loop already skips `slot.is_boss == true` via reaching `_spawn_for_slot` then `tmpl == null` (since `get_template_for_slot` returns null for boss). Confirm with a quick scan — no change needed if `tmpl` is null path covers it. Add a defensive skip:

In `_on_chunks_generated`, after `var slot := grid.resolve_sector(sector)`:

```gdscript
			if slot.is_boss:
				_spawned_sectors[sector] = true
				continue   # boss handled by CompositionDispatcher
			if slot.is_claimed:
				_spawned_sectors[sector] = true
				continue
```

- [ ] **Step 4: Smoke check — run game headless and check init**

Run: `godot --headless --quit 2>&1 | head -30`
Expected: no autoload errors; `CompositionDispatcher` loads cleanly.

- [ ] **Step 5: Commit**

```bash
git add src/core/composition_dispatcher.gd src/core/spawn_dispatcher.gd project.godot
git commit -m "feat(arenas): CompositionDispatcher autoload + spawn_dispatcher hand-off"
```

---

## Task 11: Author boss compositions (20 files)

**Files:**
- Create: `assets/arenas/boss/<biome>_<variant>.tres` × 20

Each composition is hand-authored as a Godot resource. The 4 variants per biome follow these archetypes (spec §2.4):

| Variant | Concept | Feature mix |
|---|---|---|
| `a` Pillar Hall | Dense pillar ring | 12 pillars (ring 600–900), 6 enemies (ring 700–950), 2 elites (ring 400–700), 1 lava patch (RegionDisc), boss center |
| `b` Pool Trap | Central pools | 3 lava patches near center, 2 enemy packs at perimeter (ring 800–1100), 3 barrels mid (ring 500–800), 4 pillars sparse, boss center |
| `c` Vent Maze | Gas-vent pockets | 4 vent clusters (3 vents each, RegionArc), 5 pillars irregular, 4 enemies in clearings (ring 600–900), boss center |
| `d` Open Killing Field | Wave-based | 2 pillars only, 8 enemies (ring 500–800), 4 enemies (ring 800–1100), 2 barrel clusters of 3 each, boss center |

Per-biome flavor:

| Biome | Pillar material | Pool material(s) | Barrel scene | Notes |
|---|---|---|---|---|
| caves | `MAT_STONE` | `MAT_LAVA` | barrel.tscn or null | as default |
| mines | `MAT_WOOD` (if defined) else `MAT_STONE` | `MAT_LAVA` | barrel.tscn or null | wooden pillars |
| magma | `MAT_STONE` | `MAT_LAVA` (heavy) | null (deferred) | more pools |
| frozen | `MAT_ICE` | `MAT_WATER` | null | no lava |
| vault | `MAT_STONE` | none | null | no pools |

- [ ] **Step 1: Create `assets/arenas/boss/` directory**

```bash
mkdir -p assets/arenas/boss assets/arenas/elite
```

- [ ] **Step 2: Create the 20 boss composition files**

The repetitive structure is best generated by a one-shot tool script. Create `tools/generate_arena_compositions.gd`:

```gdscript
@tool
extends EditorScript

const ArenaComposition = preload("res://src/core/arena_composition.gd")
const ArenaFeature = preload("res://src/core/arena_feature.gd")
const ArenaRegion = preload("res://src/core/arena_region.gd")

# Resolve a biome's flavor parameters.
static func _biome_params(biome: StringName) -> Dictionary:
	match biome:
		&"caves":  return {"pillar_mat": MaterialRegistry.MAT_STONE, "pool_mat": MaterialRegistry.MAT_LAVA, "boss_scene": load("res://scenes/enemies/boss_enemy.tscn")}
		&"mines":  return {"pillar_mat": MaterialRegistry.MAT_WOOD,  "pool_mat": MaterialRegistry.MAT_LAVA, "boss_scene": load("res://scenes/enemies/boss_enemy.tscn")}
		&"magma":  return {"pillar_mat": MaterialRegistry.MAT_STONE, "pool_mat": MaterialRegistry.MAT_LAVA, "boss_scene": load("res://scenes/enemies/boss_enemy.tscn")}
		&"frozen": return {"pillar_mat": MaterialRegistry.MAT_ICE,   "pool_mat": MaterialRegistry.MAT_WATER, "boss_scene": load("res://scenes/enemies/boss_enemy.tscn")}
		&"vault":  return {"pillar_mat": MaterialRegistry.MAT_STONE, "pool_mat": -1, "boss_scene": load("res://scenes/enemies/boss_enemy.tscn")}
	return {}

static func _ring(r_min: float, r_max: float) -> ArenaRegion.RegionRing:
	var r := ArenaRegion.RegionRing.new()
	r.center = Vector2.ZERO
	r.r_min = r_min
	r.r_max = r_max
	return r

static func _disc(center: Vector2, radius: float) -> ArenaRegion.RegionDisc:
	var d := ArenaRegion.RegionDisc.new()
	d.center = center
	d.radius = radius
	return d

static func _point(pos: Vector2 = Vector2.ZERO) -> ArenaRegion.RegionPoint:
	var p := ArenaRegion.RegionPoint.new()
	p.offset = pos
	return p

static func _boss(scene: PackedScene) -> ArenaFeature.FeatureBossSpawn:
	var b := ArenaFeature.FeatureBossSpawn.new()
	b.region = _point()
	b.boss_scene = scene
	return b

static func _pillars(count: int, r_min: float, r_max: float, pillar_mat: int) -> ArenaFeature.FeaturePillarCluster:
	var f := ArenaFeature.FeaturePillarCluster.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.pillar_radius_cells = 10
	f.spacing_min = 64.0
	# pillar_radius_cells stamps in background_material; ctx supplies it
	return f

static func _enemies(count: int, r_min: float, r_max: float, is_elite: bool, scene: PackedScene) -> ArenaFeature.FeatureEnemyPack:
	var f := ArenaFeature.FeatureEnemyPack.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.is_elite = is_elite
	f.enemy_scene = scene
	return f

static func _pool(center: Vector2, radius: float, mat: int, count: int = 1) -> ArenaFeature.FeaturePoolPatch:
	var f := ArenaFeature.FeaturePoolPatch.new()
	f.region = _disc(center, radius)
	f.material_id = mat
	f.count = count
	f.size_min_cells = 8
	f.size_max_cells = 16
	return f

static func _build_variant_a(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"
	c.biome = biome
	c.variant_id = &"a"
	c.nominal_radius = 960
	c.lobing_amplitude = 160
	c.inner_disc_radius = 256
	var melee_scene := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [
		_boss(p["boss_scene"]),
		_pillars(12, 600, 900, p["pillar_mat"]),
		_enemies(6, 700, 950, false, melee_scene),
		_enemies(2, 400, 700, true, melee_scene),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(-200, 100), 200, p["pool_mat"], 1))
	return c

static func _build_variant_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = 960; c.lobing_amplitude = 160; c.inner_disc_radius = 256
	var melee_scene := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [
		_boss(p["boss_scene"]),
		_pillars(4, 700, 950, p["pillar_mat"]),
		_enemies(4, 800, 1100, false, melee_scene),
		_enemies(2, 800, 1100, true, melee_scene),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(0, 0), 300, p["pool_mat"], 3))
	return c

static func _build_variant_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = 960; c.lobing_amplitude = 160; c.inner_disc_radius = 256
	var melee_scene := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [
		_boss(p["boss_scene"]),
		_pillars(5, 500, 850, p["pillar_mat"]),
		_enemies(4, 600, 900, false, melee_scene),
		_enemies(2, 700, 950, true, melee_scene),
	]
	return c

static func _build_variant_d(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"d"
	c.nominal_radius = 960; c.lobing_amplitude = 160; c.inner_disc_radius = 256
	var melee_scene := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [
		_boss(p["boss_scene"]),
		_pillars(2, 500, 700, p["pillar_mat"]),
		_enemies(8, 500, 800, false, melee_scene),
		_enemies(4, 800, 1100, false, melee_scene),
		_enemies(1, 600, 900, true, melee_scene),
	]
	return c

func _run() -> void:
	for biome in [&"caves", &"mines", &"magma", &"frozen", &"vault"]:
		for variant_builder in [
			[&"a", _build_variant_a],
			[&"b", _build_variant_b],
			[&"c", _build_variant_c],
			[&"d", _build_variant_d],
		]:
			var variant_id: StringName = variant_builder[0]
			var build_fn: Callable = variant_builder[1]
			var comp: ArenaComposition = build_fn.call(biome)
			var path := "res://assets/arenas/boss/%s_%s.tres" % [biome, variant_id]
			var err := ResourceSaver.save(comp, path)
			print("Wrote %s — %s" % [path, "OK" if err == OK else err])
```

- [ ] **Step 3: Run the generator from the Godot editor**

Open the project in Godot, open `tools/generate_arena_compositions.gd`, run it via *File → Run* (EditorScript). Verify 20 files exist:

```bash
ls assets/arenas/boss/ | wc -l
```
Expected: `20`.

- [ ] **Step 4: Commit**

```bash
git add tools/generate_arena_compositions.gd assets/arenas/boss/
git commit -m "feat(arenas): author 20 boss compositions"
```

---

## Task 12: Author elite compositions (15 files)

**Files:**
- Create: `assets/arenas/elite/<biome>_<variant>.tres` × 15
- Modify: `tools/generate_arena_compositions.gd`

- [ ] **Step 1: Extend the generator**

In `tools/generate_arena_compositions.gd`, add elite variant builders before `_run`:

```gdscript
static func _build_elite_a(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"
	c.biome = biome
	c.variant_id = &"a"
	c.nominal_radius = 224
	c.lobing_amplitude = 48
	c.inner_disc_radius = 48
	var chest_feature := ArenaFeature.FeatureChestSpawn.new()
	chest_feature.region = _point()
	chest_feature.rare = false
	var melee := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [
		chest_feature,
		_enemies(3, 80, 180, true, melee),
		_pillars(2, 100, 180, p["pillar_mat"]),
	]
	return c

static func _build_elite_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = 224; c.lobing_amplitude = 48; c.inner_disc_radius = 48
	var chest_feature := ArenaFeature.FeatureChestSpawn.new()
	chest_feature.region = _point()
	var melee := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [chest_feature, _enemies(2, 100, 200, true, melee)]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(60, -60), 60, p["pool_mat"], 1))
	return c

static func _build_elite_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = 224; c.lobing_amplitude = 48; c.inner_disc_radius = 48
	var chest_feature := ArenaFeature.FeatureChestSpawn.new()
	chest_feature.region = _point()
	var melee := load("res://scenes/enemies/melee_enemy.tscn") as PackedScene
	c.features = [
		chest_feature,
		_enemies(3, 80, 200, true, melee),
		_pillars(1, 80, 150, p["pillar_mat"]),
	]
	return c
```

Append to `_run()`:

```gdscript
	for biome in [&"caves", &"mines", &"magma", &"frozen", &"vault"]:
		for variant_builder in [
			[&"a", _build_elite_a],
			[&"b", _build_elite_b],
			[&"c", _build_elite_c],
		]:
			var variant_id: StringName = variant_builder[0]
			var build_fn: Callable = variant_builder[1]
			var comp: ArenaComposition = build_fn.call(biome)
			var path := "res://assets/arenas/elite/%s_%s.tres" % [biome, variant_id]
			var err := ResourceSaver.save(comp, path)
			print("Wrote %s — %s" % [path, "OK" if err == OK else err])
```

- [ ] **Step 2: Re-run the generator in the editor**

Run again from the Godot editor. Verify:

```bash
ls assets/arenas/elite/ | wc -l
```
Expected: `15`.

- [ ] **Step 3: Commit**

```bash
git add tools/generate_arena_compositions.gd assets/arenas/elite/
git commit -m "feat(arenas): author 15 elite compositions"
```

---

## Task 13: Wire biome resources

**Files:**
- Modify: `assets/biomes/caves.tres`
- Modify: `assets/biomes/mines.tres`
- Modify: `assets/biomes/magma.tres`
- Modify: `assets/biomes/frozen.tres`
- Modify: `assets/biomes/vault.tres`

- [ ] **Step 1: Open each biome `.tres` in the Godot editor**

For each of the 5 biome files:

1. Open `assets/biomes/<biome>.tres` in the Godot Inspector.
2. Drop the now-stale `boss_templates` field (delete the array — saving the file rewrites without it).
3. Populate the new `boss_compositions` array with the 4 files from `assets/arenas/boss/<biome>_{a,b,c,d}.tres`.
4. In `room_templates`, add an elite RoomTemplate entry for each of the 3 elite compositions:
   - `weight = 1.0`
   - `is_elite_chest = true`
   - `cavern_carve = true`
   - `composition = load("res://assets/arenas/elite/<biome>_<variant>.tres")`
   - Other normal room templates stay as-is.
5. Save.

Alternatively, scripted via a second EditorScript:

```gdscript
@tool
extends EditorScript

const ArenaComposition = preload("res://src/core/arena_composition.gd")
const RoomTemplate = preload("res://src/core/room_template.gd")

func _run() -> void:
	for biome_name in ["caves", "mines", "magma", "frozen", "vault"]:
		var path := "res://assets/biomes/%s.tres" % biome_name
		var biome: Resource = load(path)
		biome.boss_compositions = []
		for v in ["a", "b", "c", "d"]:
			biome.boss_compositions.append(load("res://assets/arenas/boss/%s_%s.tres" % [biome_name, v]))
		# Append elite room templates (don't duplicate if already present)
		var elite_existing := 0
		for rt in biome.room_templates:
			if rt.is_elite_chest:
				elite_existing += 1
		if elite_existing == 0:
			for v in ["a", "b", "c"]:
				var rt := RoomTemplate.new()
				rt.weight = 1.0
				rt.is_elite_chest = true
				rt.cavern_carve = true
				rt.composition = load("res://assets/arenas/elite/%s_%s.tres" % [biome_name, v])
				biome.room_templates.append(rt)
		ResourceSaver.save(biome, path)
		print("Updated %s" % path)
```

Create as `tools/wire_arena_biomes.gd` and run once.

- [ ] **Step 2: Commit**

```bash
git add assets/biomes/ tools/wire_arena_biomes.gd
git commit -m "feat(arenas): wire boss/elite compositions into biome resources"
```

---

## Task 14: Manual smoke test

**Files:** none (verification only).

- [ ] **Step 1: Launch a level**

Open the project in Godot, run the main scene, start a new run.

- [ ] **Step 2: Cheat to a boss anchor**

Use the console (`~` or `\``) and teleport to a boss anchor. From spawn, the first anchor is at sector `(10, -10)` → world position `(10*384 + 192, -10*384 + 192) = (4032, -3648)`. If a cheat exists:

```
tp 4032 -3648
```

Otherwise walk there.

- [ ] **Step 3: Visual verification**

Expected observations:
- A large irregular open cavern centered at the anchor.
- Pillars (small solid blobs) scattered in a ring pattern.
- A boss enemy at the center.
- Enemies in outer regions.
- No hard rectangular outline.
- Cave-noise tunnels reach into the cavern as natural entrances.

If anything is missing or broken, capture a screenshot and add notes to a follow-up issue rather than blocking the merge.

- [ ] **Step 4: Run full test suite**

Run: `addons/gdUnit4/runtest.sh -a tests/unit/`
Expected: all tests pass.

- [ ] **Step 5: Final commit (notes-only, if any)**

If smoke test reveals copy-paste-fixable issues, fix and commit. Otherwise this task records that verification was performed.

```bash
git commit --allow-empty -m "chore(arenas): manual smoke verification passed"
```

---

## Out of scope (reminders)

These are deferred per spec §1.1 and §7:

- `MAT_OIL` and `MAT_EXPLODE_WAVE` materials. `FeaturePoolPatch` for oil and `FeatureBarrelCluster`/`FeatureVent` with oil-aware barrels remain as no-op stubs (null scene).
- Ambient prop dispatcher for normal cave chunks (Part 3 rewrite).
- World boundary (wardstone, void-stone) (Part 3 rewrite).
- Destruction debris tables (Part 3 rewrite).
- Authoring tooling — no replacement for the deleted `level_preview`.

---

## Self-review

- Spec §2.1 (footprint, claiming) → Task 6.
- Spec §2.2 (carve stage) → Tasks 7, 8.
- Spec §2.3 (composition schema) → Tasks 2, 3, 4.
- Spec §2.4 (4 variants per biome × 5 biomes) → Task 11.
- Spec §3 (elite room) → Tasks 5 (cavern_carve flag), 12 (compositions), 13 (biome wiring).
- Spec §4.1 (stage order) → Tasks 7, 8.
- Spec §4.2 (chunk_flags_tex) → Task 9.
- Spec §4.3 (CompositionDispatcher) → Task 10.
- Spec §5.3 (level_preview deletion) → Task 1.
- Spec §5.4 (manual work) → user-owned, not in plan tasks.
- Spec §7 testing — unit tests in Tasks 2, 4, 6; full-pipeline smoke in Task 14.
