# Guidance Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lit, hand-authored circular "safe-house" chamber at world origin `(0, 0)` that teaches new players the goal (go outward → boss → portal) and the basic controls (move/attack/interact) via pictographic plaques. Ship it as a reusable authored-room capability so future rooms (shops, vaults) reuse the same primitives.

**Architecture:** Add a `fixed_anchors` map (`Dictionary[Vector2i, RoomTemplate]`) to `BiomeDef` and a one-clause check at the top of `SectorGrid.resolve_sector()` that returns that template's slot for matching coords. Add three generic, data-driven `ArenaFeature` subclasses (`FeatureFloorOverlay`, `FeatureLanternCluster`, `FeaturePlaqueSet`) that any composition can compose. Add one tiny helper on `CompositionDispatcher` (`spawn_node`) so features can hand any Node2D to the spawn parent. Define the guidance room as data: one `RoomTemplate.tres` + one `ArenaComposition.tres` wiring those three features. No engine changes to the cave compute pipeline; the room is just a `cavern_carve` round pocket like elite/boss rooms already are.

**Tech Stack:** Godot 4, GDScript, GdUnit4 for tests.

**Spec:** `docs/superpowers/specs/2026-05-26-guidance-room-design.md`

**User-supplied assets:** This plan includes one explicit user-action task (Task 0) where the user provides PNG art before code touches the data resources.

**Audio:** Out of scope for this implementation. No audio nodes, ambient streams, or sound effects.

---

## File Structure

**Create (code):**

- `src/core/features/feature_floor_overlay.gd` — generic Sprite2D overlay feature (texture + size + offset).
- `src/core/features/feature_lantern_cluster.gd` — places N lanterns (prop scene + child `PointLight2D`) at configurable offsets.
- `src/core/features/lantern_spec.gd` — Resource holding one lantern's offset + light parameters (used as array elements on the cluster).
- `src/core/features/feature_plaque_set.gd` — places N wall plaques (Sprite2D with assigned texture) at configurable offsets.
- `src/core/features/plaque_spec.gd` — Resource holding one plaque's offset + texture + size.
- `scenes/props/lantern.tscn` — small Node2D scene: Sprite2D (lantern art) + child `PointLight2D`. Used by `FeatureLanternCluster`.

**Modify (code):**

- `src/core/biome_def.gd` — add `@export var fixed_anchors: Dictionary = {}`.
- `src/core/sector_grid.gd` — add `template_override: RoomTemplate` field on `RoomSlot`; add `fixed_anchors` check at top of `resolve_sector`; update `get_template_for_slot` to honor `template_override`.
- `src/core/chunk_manager.gd:349` — update the cavern-carve filter to honor `template_override` (so fixed-anchor rooms carve correctly).
- `src/core/composition_dispatcher.gd` — add `spawn_node(node, world_pos)` helper that parents the given Node2D to the spawn parent and sets `global_position`.

**Create (data — depends on user-supplied art):**

- `assets/arenas/guidance/guidance_room_composition.tres` — `ArenaComposition` wiring the three features with art paths.
- `assets/rooms/guidance/guidance_room_template.tres` — `RoomTemplate` (`cavern_carve = true`, points to the composition above).

**Modify (data):**

- `assets/biomes/caves.tres` — add the guidance template as a sub-resource and register it in `fixed_anchors` at `Vector2i(0, 0)`.

**Test:**

- `tests/unit/test_biome_fixed_anchors.gd` — `fixed_anchors` default + lookup.
- `tests/unit/test_sector_grid_fixed_anchors.gd` — `resolve_sector` returns the fixed-anchor template's slot; `get_template_for_slot` returns the override.
- `tests/unit/test_feature_floor_overlay.gd` — spawns a Sprite2D with the configured texture at the configured offset.
- `tests/unit/test_feature_lantern_cluster.gd` — spawns N lanterns at configured offsets.
- `tests/unit/test_feature_plaque_set.gd` — spawns N plaques with configured textures at configured offsets.
- `tests/unit/test_composition_dispatcher_spawn_node.gd` — `spawn_node` parents and positions a given Node2D.

---

## Task 0: User provides art assets

**This task is a user action, not a code task. Do not proceed past it until the user confirms the files are in place.**

**Files (user creates these PNGs):**

- Create: `textures/Guidance/sign_goal.png` — pictogram for the goal sign (player → radial outward arrows → boss skull → portal). ~64×64 px.
- Create: `textures/Guidance/sign_move.png` — WASD glyph pictogram. ~64×64 px.
- Create: `textures/Guidance/sign_attack.png` — mouse + swing arc pictogram. ~64×64 px.
- Create: `textures/Guidance/sign_interact.png` — E key + hand/pickup pictogram. ~64×64 px.
- Create: `textures/Guidance/lantern.png` — lantern prop sprite. ~32×48 px.
- Create: `textures/Guidance/wooden_planks.png` — tileable wooden-plank floor texture. 256×256 px (it'll be drawn at a larger size via Sprite2D scaling or region; tileable so it scales cleanly).

- [ ] **Step 1: Confirm art is present**

Verify each path exists:

```bash
ls -la textures/Guidance/sign_goal.png textures/Guidance/sign_move.png textures/Guidance/sign_attack.png textures/Guidance/sign_interact.png textures/Guidance/lantern.png textures/Guidance/wooden_planks.png
```

Expected: all six files listed, non-zero sizes. If any are missing, **stop** and ask the user to provide them before proceeding to Task 1.

- [ ] **Step 2: Let Godot import the assets**

Open the project in the Godot editor at least once so the `.import` sidecars get generated for the new PNGs. Verify:

```bash
ls textures/Guidance/*.import
```

Expected: six `.import` files alongside the PNGs.

- [ ] **Step 3: Commit the assets**

```bash
git add textures/Guidance/
git commit -m "assets: add guidance room sign and prop textures"
```

---

## Task 1: Add `spawn_node` helper to `CompositionDispatcher`

**Files:**

- Modify: `src/core/composition_dispatcher.gd` (append a method after `spawn_prop`, ~line 132)
- Test: `tests/unit/test_composition_dispatcher_spawn_node.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_composition_dispatcher_spawn_node.gd`:

```gdscript
extends GdUnitTestSuite

const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")

func test_spawn_node_parents_and_positions() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var sprite := Sprite2D.new()
	dispatcher.spawn_node(sprite, Vector2(120, -40))

	assert_that(sprite.get_parent()).is_equal(parent)
	assert_that(sprite.global_position).is_equal(Vector2(120, -40))

func test_spawn_node_with_null_does_nothing() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	dispatcher.spawn_node(null, Vector2.ZERO)

	assert_that(parent.get_child_count()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run via the Godot editor's GdUnit panel or CLI:

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_composition_dispatcher_spawn_node.gd
```

Expected: FAIL with "Invalid call. Nonexistent function 'spawn_node'" (or similar).

- [ ] **Step 3: Add the method**

Open `src/core/composition_dispatcher.gd`. After the `spawn_prop` method (around line 131), add:

```gdscript
func spawn_node(node: Node2D, world_pos: Vector2) -> void:
	if node == null or _spawn_parent == null:
		return
	_spawn_parent.add_child(node)
	node.global_position = world_pos
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command. Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/composition_dispatcher.gd tests/unit/test_composition_dispatcher_spawn_node.gd
git commit -m "feat(core): add spawn_node helper for generic features"
```

---

## Task 2: Add `fixed_anchors` field to `BiomeDef`

**Files:**

- Modify: `src/core/biome_def.gd:23` (append after `boss_scene`)
- Test: `tests/unit/test_biome_fixed_anchors.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_biome_fixed_anchors.gd`:

```gdscript
extends GdUnitTestSuite

const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func test_fixed_anchors_default_empty() -> void:
	var b := _BiomeDef.new()
	assert_that(b.fixed_anchors).is_equal({})

func test_fixed_anchors_holds_template_by_sector() -> void:
	var b := _BiomeDef.new()
	var tmpl := _RoomTemplate.new()
	b.fixed_anchors[Vector2i(0, 0)] = tmpl
	assert_that(b.fixed_anchors.has(Vector2i(0, 0))).is_true()
	assert_that(b.fixed_anchors[Vector2i(0, 0)]).is_equal(tmpl)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_biome_fixed_anchors.gd
```
Expected: FAIL with "Invalid get index 'fixed_anchors'".

- [ ] **Step 3: Add the field**

Open `src/core/biome_def.gd`. At the end of the class (after `boss_scene` on line 23), add:

```gdscript
@export var fixed_anchors: Dictionary = {}  # Vector2i sector -> RoomTemplate
```

- [ ] **Step 4: Run test to verify it passes**

Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/biome_def.gd tests/unit/test_biome_fixed_anchors.gd
git commit -m "feat(biome): add fixed_anchors map for hand-placed rooms"
```

---

## Task 3: Extend `RoomSlot` and `resolve_sector` for fixed anchors

**Files:**

- Modify: `src/core/sector_grid.gd:10-17` (add `template_override` to `RoomSlot`)
- Modify: `src/core/sector_grid.gd:68-119` (`resolve_sector`) — add fixed-anchor check at top
- Modify: `src/core/sector_grid.gd:122-125` (`get_template_for_slot`) — honor override
- Test: `tests/unit/test_sector_grid_fixed_anchors.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_sector_grid_fixed_anchors.gd`:

```gdscript
extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

func _make_biome_with_anchor(coord: Vector2i, cavern_carve: bool) -> _BiomeDef:
	var b := _BiomeDef.new()
	var comp := _ArenaComposition.new()
	var tmpl := _RoomTemplate.new()
	tmpl.cavern_carve = cavern_carve
	tmpl.composition = comp
	tmpl.size_class = 96
	b.fixed_anchors[coord] = tmpl
	return b

func test_resolve_sector_returns_fixed_anchor_template() -> void:
	var biome := _make_biome_with_anchor(Vector2i(0, 0), true)
	var grid := _SectorGrid.new(12345, biome)
	var slot = grid.resolve_sector(Vector2i(0, 0))
	assert_that(slot.template_override).is_equal(biome.fixed_anchors[Vector2i(0, 0)])
	assert_that(slot.composition).is_equal(biome.fixed_anchors[Vector2i(0, 0)].composition)
	assert_that(slot.is_empty).is_false()
	assert_that(slot.is_boss).is_false()
	assert_that(slot.template_size).is_equal(96)

func test_resolve_sector_non_anchor_unchanged() -> void:
	var biome := _make_biome_with_anchor(Vector2i(0, 0), true)
	var grid := _SectorGrid.new(12345, biome)
	# A coord far from origin and not the boss ring; with no room_templates,
	# the random path returns an empty slot. The important assertion is that
	# template_override is null for non-anchor coords.
	var slot = grid.resolve_sector(Vector2i(3, 2))
	assert_that(slot.template_override).is_null()

func test_get_template_for_slot_returns_override() -> void:
	var biome := _make_biome_with_anchor(Vector2i(0, 0), true)
	var grid := _SectorGrid.new(12345, biome)
	var slot = grid.resolve_sector(Vector2i(0, 0))
	var tmpl = grid.get_template_for_slot(slot)
	assert_that(tmpl).is_equal(biome.fixed_anchors[Vector2i(0, 0)])
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `RoomSlot` has no `template_override` property.

- [ ] **Step 3: Add `template_override` to `RoomSlot`**

Open `src/core/sector_grid.gd`. Update the `RoomSlot` class (lines 10-17):

```gdscript
class RoomSlot:
	var is_empty: bool = false
	var is_boss: bool = false
	var is_claimed: bool = false
	var template_index: int = -1
	var rotation: int = 0
	var template_size: int = 0
	var composition: Resource = null
	var template_override: RoomTemplate = null
```

- [ ] **Step 4: Add fixed-anchor check at top of `resolve_sector`**

Still in `src/core/sector_grid.gd`. At the start of `resolve_sector` (after the `var slot := RoomSlot.new()` line, around line 69), add the fixed-anchor branch:

```gdscript
func resolve_sector(coord: Vector2i) -> RoomSlot:
	var slot := RoomSlot.new()

	if _biome != null and _biome.fixed_anchors.has(coord):
		var tmpl: RoomTemplate = _biome.fixed_anchors[coord]
		slot.template_override = tmpl
		slot.template_size = tmpl.size_class
		if tmpl.cavern_carve:
			slot.composition = tmpl.composition
		return slot

	var dist := chebyshev_distance(coord, Vector2i.ZERO)
	# ... rest of method unchanged
```

(Leave the rest of the method body — boss ring + random selection — exactly as it was.)

- [ ] **Step 5: Update `get_template_for_slot` to honor override**

Still in `src/core/sector_grid.gd`. Replace the body of `get_template_for_slot`:

```gdscript
func get_template_for_slot(slot: RoomSlot) -> RoomTemplate:
	if slot.is_empty or slot.is_boss:
		return null
	if slot.template_override != null:
		return slot.template_override
	return _biome.room_templates[slot.template_index]
```

- [ ] **Step 6: Run test to verify it passes**

Run the new test file. Expected: all three tests PASS.

- [ ] **Step 7: Run the full sector-grid suite to ensure no regressions**

Run the existing sector-grid tests (find them with `grep -l "SectorGrid" tests/unit/*.gd`) plus the new file. Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add src/core/sector_grid.gd tests/unit/test_sector_grid_fixed_anchors.gd
git commit -m "feat(sector-grid): support fixed-anchor templates via template_override"
```

---

## Task 4: Include fixed-anchor templates in cavern-carve filter

**Files:**

- Modify: `src/core/chunk_manager.gd:349`

The current filter on line 349 skips any slot where `slot.template_index < 0`. Our fixed-anchor slots have `template_index = -1` but a `template_override` set, so they'd be skipped. Fix the filter to use `get_template_for_slot` directly.

- [ ] **Step 1: Read the existing condition**

Open `src/core/chunk_manager.gd`. Line 349 currently reads:

```gdscript
if not slot.is_boss and not (slot.template_index >= 0 and (grid.get_template_for_slot(slot) as RoomTemplate).cavern_carve):
	continue
```

- [ ] **Step 2: Rewrite the condition to use get_template_for_slot uniformly**

Replace lines 348-350 (the `if` and `continue`) with:

```gdscript
		if not slot.is_boss:
			var tmpl := grid.get_template_for_slot(slot) as RoomTemplate
			if tmpl == null or not tmpl.cavern_carve:
				continue
```

Verify by re-reading the surrounding loop — the `continue` still belongs to the outer `for sx`/`for sy` loop, and `slot` is still in scope.

- [ ] **Step 3: Manual sanity check (no new test)**

This change is a refactor of an existing condition. There is no easy unit test for `_build_cavern_bytes` without the full compute pipeline. Verify by inspection:

- Boss slots still bypass the template check (`if not slot.is_boss`).
- Non-boss slots with `cavern_carve` templates (either random elites or fixed anchors) are kept.
- Non-boss slots with no template, or templates with `cavern_carve = false`, are skipped (`continue`).

- [ ] **Step 4: Run all existing unit tests**

Run the full unit test suite to confirm no regressions:

```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/
```

Expected: all existing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/chunk_manager.gd
git commit -m "fix(chunks): include fixed-anchor cavern_carve rooms in carve buffer"
```

---

## Task 5: `FeatureFloorOverlay`

**Files:**

- Create: `src/core/features/feature_floor_overlay.gd`
- Test: `tests/unit/test_feature_floor_overlay.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_feature_floor_overlay.gd`:

```gdscript
extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_floor_overlay.gd")
const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")

func _make_ctx(dispatcher: Node, anchor: Vector2) -> _Dispatcher.CompositionContext:
	var ctx := _Dispatcher.CompositionContext.new()
	ctx.anchor_world_pos = anchor
	ctx.rng = RandomNumberGenerator.new()
	ctx.dispatcher = dispatcher
	ctx.mask_air = func(_p: Vector2) -> bool: return true
	return ctx

func test_floor_overlay_spawns_sprite_at_offset() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var feature := _Feature.new()
	feature.texture = PlaceholderTexture2D.new()
	feature.size = Vector2(1024, 1024)
	feature.offset = Vector2(0, 0)
	feature.z_index_value = -5

	feature.apply(_make_ctx(dispatcher, Vector2(200, 300)))

	assert_that(parent.get_child_count()).is_equal(1)
	var spr := parent.get_child(0) as Sprite2D
	assert_that(spr).is_not_null()
	assert_that(spr.global_position).is_equal(Vector2(200, 300))
	assert_that(spr.z_index).is_equal(-5)
	assert_that(spr.texture).is_not_null()
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — script does not exist.

- [ ] **Step 3: Create the feature script**

Create `src/core/features/feature_floor_overlay.gd`:

```gdscript
class_name FeatureFloorOverlay
extends ArenaFeature

@export var texture: Texture2D
@export var size: Vector2 = Vector2(1024, 1024)
@export var offset: Vector2 = Vector2.ZERO
@export var z_index_value: int = -5

func apply(ctx) -> void:
	if texture == null:
		return
	var spr := Sprite2D.new()
	spr.texture = texture
	spr.centered = true
	spr.z_index = z_index_value
	# Stretch the texture to the configured size.
	var tex_size: Vector2 = texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		spr.scale = Vector2(size.x / tex_size.x, size.y / tex_size.y)
	ctx.dispatcher.spawn_node(spr, ctx.anchor_world_pos + offset)
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/features/feature_floor_overlay.gd tests/unit/test_feature_floor_overlay.gd
git commit -m "feat(features): add FeatureFloorOverlay for authored room floors"
```

---

## Task 6: `LanternSpec` + `FeatureLanternCluster` + `lantern.tscn`

**Files:**

- Create: `src/core/features/lantern_spec.gd`
- Create: `src/core/features/feature_lantern_cluster.gd`
- Create: `scenes/props/lantern.tscn`
- Test: `tests/unit/test_feature_lantern_cluster.gd`

- [ ] **Step 1: Create the `lantern.tscn` scene (editor task)**

Open the Godot editor. Create a new scene rooted at a `Node2D` named `Lantern`. Add:

- Child `Sprite2D` named `Sprite`, texture = `textures/Guidance/lantern.png`, centered = true.
- Child `PointLight2D` named `Light`, default energy = 1.2, default texture_scale = 4.0 (will be overridden per-spec at runtime), color = `Color(1.0, 0.85, 0.6, 1.0)`.

Save as `scenes/props/lantern.tscn`. Then in a terminal:

```bash
ls scenes/props/lantern.tscn
```

Expected: file exists.

- [ ] **Step 2: Write the failing test**

Create `tests/unit/test_feature_lantern_cluster.gd`:

```gdscript
extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_lantern_cluster.gd")
const _Spec = preload("res://src/core/features/lantern_spec.gd")
const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")
const _LanternScene = preload("res://scenes/props/lantern.tscn")

func _make_ctx(dispatcher: Node, anchor: Vector2) -> _Dispatcher.CompositionContext:
	var ctx := _Dispatcher.CompositionContext.new()
	ctx.anchor_world_pos = anchor
	ctx.rng = RandomNumberGenerator.new()
	ctx.dispatcher = dispatcher
	ctx.mask_air = func(_p: Vector2) -> bool: return true
	return ctx

func test_lantern_cluster_spawns_one_per_spec_at_offsets() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var s1 := _Spec.new()
	s1.offset = Vector2(-200, -200)
	s1.prop_scene = _LanternScene
	s1.light_color = Color(1, 0.8, 0.5, 1)
	s1.light_energy = 1.5
	s1.light_radius = 400.0
	s1.flicker_amplitude = 0.1

	var s2 := _Spec.new()
	s2.offset = Vector2(200, 200)
	s2.prop_scene = _LanternScene
	s2.light_color = Color(1, 0.8, 0.5, 1)
	s2.light_energy = 1.5
	s2.light_radius = 400.0
	s2.flicker_amplitude = 0.1

	var feature := _Feature.new()
	feature.lanterns = [s1, s2]
	feature.apply(_make_ctx(dispatcher, Vector2(100, 100)))

	assert_that(parent.get_child_count()).is_equal(2)
	var first := parent.get_child(0) as Node2D
	var second := parent.get_child(1) as Node2D
	assert_that(first.global_position).is_equal(Vector2(-100, -100))
	assert_that(second.global_position).is_equal(Vector2(300, 300))

func test_lantern_cluster_empty_array_spawns_nothing() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var feature := _Feature.new()
	feature.lanterns = []
	feature.apply(_make_ctx(dispatcher, Vector2.ZERO))

	assert_that(parent.get_child_count()).is_equal(0)
```

- [ ] **Step 3: Run test to verify it fails**

Expected: FAIL — scripts do not exist.

- [ ] **Step 4: Create `LanternSpec`**

Create `src/core/features/lantern_spec.gd`:

```gdscript
class_name LanternSpec
extends Resource

@export var offset: Vector2 = Vector2.ZERO
@export var prop_scene: PackedScene
@export var light_color: Color = Color(1.0, 0.85, 0.6, 1.0)
@export var light_energy: float = 1.2
@export var light_radius: float = 384.0
@export var flicker_amplitude: float = 0.08
```

- [ ] **Step 5: Create `FeatureLanternCluster`**

Create `src/core/features/feature_lantern_cluster.gd`:

```gdscript
class_name FeatureLanternCluster
extends ArenaFeature

@export var lanterns: Array[LanternSpec] = []

func apply(ctx) -> void:
	for spec in lanterns:
		if spec == null or spec.prop_scene == null:
			continue
		var inst: Node2D = spec.prop_scene.instantiate()
		var light := inst.get_node_or_null("Light") as PointLight2D
		if light != null:
			light.color = spec.light_color
			light.energy = spec.light_energy
			# texture_scale maps the lantern's PointLight2D texture to a radius.
			# Approximate: light_radius / 64 (the default texture is 128 px, so scale ≈ radius/64).
			light.texture_scale = max(spec.light_radius / 64.0, 0.1)
			inst.set_meta("flicker_base_energy", spec.light_energy)
			inst.set_meta("flicker_amplitude", spec.flicker_amplitude)
		ctx.dispatcher.spawn_node(inst, ctx.anchor_world_pos + spec.offset)
```

- [ ] **Step 6: Run test to verify it passes**

Expected: both tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/core/features/lantern_spec.gd src/core/features/feature_lantern_cluster.gd scenes/props/lantern.tscn tests/unit/test_feature_lantern_cluster.gd
git commit -m "feat(features): add FeatureLanternCluster + lantern.tscn"
```

---

## Task 7: Add flicker animation to lantern scene

Lantern flicker is small enough to live in the prop scene itself rather than a global system.

**Files:**

- Create: `src/props/lantern.gd` (new script attached to `lantern.tscn`)
- Modify: `scenes/props/lantern.tscn` (attach the script to the root node)

- [ ] **Step 1: Create the lantern script**

Create `src/props/lantern.gd`:

```gdscript
extends Node2D

@onready var _light: PointLight2D = $Light
var _base_energy: float = 1.2
var _amplitude: float = 0.08
var _phase: float = 0.0

func _ready() -> void:
	if has_meta("flicker_base_energy"):
		_base_energy = get_meta("flicker_base_energy")
	if has_meta("flicker_amplitude"):
		_amplitude = get_meta("flicker_amplitude")
	_phase = randf() * TAU

func _process(delta: float) -> void:
	if _light == null:
		return
	_phase += delta * 8.0
	var jitter: float = sin(_phase) * 0.6 + sin(_phase * 2.3) * 0.4
	_light.energy = _base_energy + jitter * _amplitude
```

- [ ] **Step 2: Attach the script to `lantern.tscn` (editor task)**

Open `scenes/props/lantern.tscn` in the Godot editor. Select the root `Lantern` node. In the Inspector → Script, attach `res://src/props/lantern.gd`. Save the scene.

- [ ] **Step 3: Verify the scene parses**

```bash
godot --headless --path . --check-only scenes/props/lantern.tscn
```

(Or, more simply, re-run the unit test from Task 6 — it instantiates the scene and will fail if the script errors at load.)

Run:
```
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_feature_lantern_cluster.gd
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/props/lantern.gd scenes/props/lantern.tscn
git commit -m "feat(props): add flicker animation to lantern"
```

---

## Task 8: `PlaqueSpec` + `FeaturePlaqueSet`

**Files:**

- Create: `src/core/features/plaque_spec.gd`
- Create: `src/core/features/feature_plaque_set.gd`
- Test: `tests/unit/test_feature_plaque_set.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_feature_plaque_set.gd`:

```gdscript
extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_plaque_set.gd")
const _Spec = preload("res://src/core/features/plaque_spec.gd")
const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")

func _make_ctx(dispatcher: Node, anchor: Vector2) -> _Dispatcher.CompositionContext:
	var ctx := _Dispatcher.CompositionContext.new()
	ctx.anchor_world_pos = anchor
	ctx.rng = RandomNumberGenerator.new()
	ctx.dispatcher = dispatcher
	ctx.mask_air = func(_p: Vector2) -> bool: return true
	return ctx

func test_plaque_set_spawns_sprite_per_spec() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var s1 := _Spec.new()
	s1.offset = Vector2(0, -300)
	s1.texture = PlaceholderTexture2D.new()
	s1.size = Vector2(64, 64)

	var s2 := _Spec.new()
	s2.offset = Vector2(-300, 0)
	s2.texture = PlaceholderTexture2D.new()
	s2.size = Vector2(64, 64)

	var feature := _Feature.new()
	feature.plaques = [s1, s2]
	feature.apply(_make_ctx(dispatcher, Vector2(50, 50)))

	assert_that(parent.get_child_count()).is_equal(2)
	var first := parent.get_child(0) as Sprite2D
	var second := parent.get_child(1) as Sprite2D
	assert_that(first.global_position).is_equal(Vector2(50, -250))
	assert_that(second.global_position).is_equal(Vector2(-250, 50))
	assert_that(first.texture).is_not_null()
	assert_that(second.texture).is_not_null()

func test_plaque_set_skips_spec_with_null_texture() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var s := _Spec.new()
	s.offset = Vector2.ZERO
	s.texture = null
	s.size = Vector2(64, 64)

	var feature := _Feature.new()
	feature.plaques = [s]
	feature.apply(_make_ctx(dispatcher, Vector2.ZERO))

	assert_that(parent.get_child_count()).is_equal(0)
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — scripts do not exist.

- [ ] **Step 3: Create `PlaqueSpec`**

Create `src/core/features/plaque_spec.gd`:

```gdscript
class_name PlaqueSpec
extends Resource

@export var offset: Vector2 = Vector2.ZERO
@export var texture: Texture2D
@export var size: Vector2 = Vector2(64, 64)
@export var z_index_value: int = 5
```

- [ ] **Step 4: Create `FeaturePlaqueSet`**

Create `src/core/features/feature_plaque_set.gd`:

```gdscript
class_name FeaturePlaqueSet
extends ArenaFeature

@export var plaques: Array[PlaqueSpec] = []

func apply(ctx) -> void:
	for spec in plaques:
		if spec == null or spec.texture == null:
			continue
		var spr := Sprite2D.new()
		spr.texture = spec.texture
		spr.centered = true
		spr.z_index = spec.z_index_value
		var tex_size: Vector2 = spec.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			spr.scale = Vector2(spec.size.x / tex_size.x, spec.size.y / tex_size.y)
		ctx.dispatcher.spawn_node(spr, ctx.anchor_world_pos + spec.offset)
```

- [ ] **Step 5: Run test to verify it passes**

Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/core/features/plaque_spec.gd src/core/features/feature_plaque_set.gd tests/unit/test_feature_plaque_set.gd
git commit -m "feat(features): add FeaturePlaqueSet for authored room signs"
```

---

## Task 9: Author `guidance_room_composition.tres` (editor task)

**Files:**

- Create: `assets/arenas/guidance/guidance_room_composition.tres`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p assets/arenas/guidance
```

- [ ] **Step 2: Create the composition in the editor**

Open the Godot editor. In the FileSystem dock, right-click `assets/arenas/guidance/` → "New Resource" → choose `ArenaComposition`. Save as `guidance_room_composition.tres`.

Set properties on the composition resource:

- `arena_kind = "guidance"`
- `biome = "caves"`
- `variant_id = "a"`
- `nominal_radius = 500`
- `lobing_amplitude = 30`
- `inner_disc_radius = 240`
- `features = [ ... ]` — populate with three feature sub-resources below.

**Feature 1 — `FeatureFloorOverlay` (wooden planks):**

- `texture = res://textures/Guidance/wooden_planks.png`
- `size = Vector2(1024, 1024)`
- `offset = Vector2(0, 0)`
- `z_index_value = -5`
- `region = null` (region is unused by this feature; leave the inherited field null)

**Feature 2 — `FeatureLanternCluster`:**

- `lanterns = [ ... ]` — four `LanternSpec` sub-resources:
  - NW: `offset = Vector2(-300, -300)`, `prop_scene = res://scenes/props/lantern.tscn`, `light_color = Color(1.0, 0.85, 0.6, 1.0)`, `light_energy = 1.2`, `light_radius = 450.0`, `flicker_amplitude = 0.08`
  - NE: `offset = Vector2(300, -300)`, same other params
  - SW: `offset = Vector2(-300, 300)`, same other params
  - SE: `offset = Vector2(300, 300)`, same other params

**Feature 3 — `FeaturePlaqueSet`:**

- `plaques = [ ... ]` — four `PlaqueSpec` sub-resources:
  - North (goal): `offset = Vector2(0, -360)`, `texture = res://textures/Guidance/sign_goal.png`, `size = Vector2(96, 96)`, `z_index_value = 5`
  - West (move): `offset = Vector2(-360, 0)`, `texture = res://textures/Guidance/sign_move.png`, `size = Vector2(64, 64)`, `z_index_value = 5`
  - East (attack): `offset = Vector2(360, 0)`, `texture = res://textures/Guidance/sign_attack.png`, `size = Vector2(64, 64)`, `z_index_value = 5`
  - South (interact): `offset = Vector2(0, 360)`, `texture = res://textures/Guidance/sign_interact.png`, `size = Vector2(64, 64)`, `z_index_value = 5`

Save the composition.

- [ ] **Step 3: Verify the file is on disk**

```bash
ls assets/arenas/guidance/guidance_room_composition.tres
```

Expected: file exists, non-zero size.

- [ ] **Step 4: Commit**

```bash
git add assets/arenas/guidance/
git commit -m "data: add guidance room arena composition"
```

---

## Task 10: Author `guidance_room_template.tres` (editor task)

**Files:**

- Create: `assets/rooms/guidance/guidance_room_template.tres`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p assets/rooms/guidance
```

- [ ] **Step 2: Create the template in the editor**

In the FileSystem dock, right-click `assets/rooms/guidance/` → "New Resource" → `RoomTemplate`. Save as `guidance_room_template.tres`.

Set properties:

- `png_path = ""` (not used — cavern_carve rooms don't read a PNG stamp)
- `weight = 0.0` (never picked by weighted random; only ever placed via `fixed_anchors`)
- `size_class = 128`
- `is_secret = false`
- `is_boss = false`
- `is_elite_chest = false`
- `rotatable = false`
- `cavern_carve = true`
- `composition = res://assets/arenas/guidance/guidance_room_composition.tres`

Save the template.

- [ ] **Step 3: Verify the file is on disk**

```bash
ls assets/rooms/guidance/guidance_room_template.tres
```

Expected: file exists.

- [ ] **Step 4: Commit**

```bash
git add assets/rooms/guidance/
git commit -m "data: add guidance room template"
```

---

## Task 11: Register the guidance room on the caves biome (editor task)

**Files:**

- Modify: `assets/biomes/caves.tres`

- [ ] **Step 1: Open the caves biome**

In the Godot editor, open `assets/biomes/caves.tres` for editing.

- [ ] **Step 2: Add the guidance template to `fixed_anchors`**

In the Inspector, find the new `fixed_anchors` `Dictionary` field. Add an entry:

- Key: `Vector2i(0, 0)`
- Value: load `res://assets/rooms/guidance/guidance_room_template.tres`

Save the biome resource.

- [ ] **Step 3: Verify by inspecting the .tres file**

```bash
grep -A2 "fixed_anchors" assets/biomes/caves.tres
```

Expected: output shows a Dictionary with `Vector2i(0, 0)` mapping to an ext_resource pointing at the guidance template.

- [ ] **Step 4: Commit**

```bash
git add assets/biomes/caves.tres
git commit -m "data: register guidance room at (0,0) on caves biome"
```

---

## Task 12: Manual playtest

This is a manual verification task — the previous tasks all have automated tests, but the end-to-end experience needs a human eye.

- [ ] **Step 1: Launch the game**

Run the project from the Godot editor (F5) or:

```bash
godot --path .
```

- [ ] **Step 2: Verify the guidance room appears**

On a fresh run:

- Player spawns inside a circular, brightly-lit chamber.
- A wooden-plank floor is visible underneath the player and across the chamber footprint.
- Four lantern sprites are visible near the corners, lights flicker subtly.
- Four sign plaques are visible at N/W/E/S of spawn with the four pictograms.
- The surrounding cave is visibly darker; cave terrain forms the chamber's walls.
- No enemies, chests, or hazards spawn inside the chamber.

- [ ] **Step 3: Verify destructibility**

Swing at one of the chamber walls. Confirm cave stone carves normally — no special "indestructible" behavior in this area.

- [ ] **Step 4: Verify exit and gameplay continuity**

Walk out of the chamber (through any natural opening or by carving). Confirm the rest of the level plays as normal — enemies spawn, the boss ring still functions, defeating a boss still spawns a portal.

- [ ] **Step 5: Verify reset**

Take a portal to the next level. Confirm the guidance room spawns again at the new level's origin.

- [ ] **Step 6: If any of the above fails**

Diagnose by checking:

- If signs are missing or wrong size: Task 9 plaque offsets/sizes or Task 0 PNG paths.
- If the room isn't carved: Task 4 (`chunk_manager` filter) or Task 9 `nominal_radius`.
- If the floor overlay doesn't appear: Task 5 z-index or texture loading.
- If lanterns don't light: Task 6 `light_radius` / `texture_scale` math; Task 7 script attachment.
- If the room appears at the wrong sector: Task 11 `fixed_anchors` key.

- [ ] **Step 7: Final commit (only if any small fixes were made above)**

```bash
git status
# if anything changed:
git add -A
git commit -m "fix: guidance room playtest tweaks"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** every spec section maps to a task — concept/style (Tasks 9–11 data), walls (existing cave-stone, no special handling needed), signs (Tasks 0/8/9), lighting (Tasks 6/7), floor (Tasks 5/9), integration via fixed-anchor + 3 features + spawn_node helper (Tasks 1–4), shop/vault generalization (the same Tasks 5/6/8 features are reusable). Audio explicitly excluded per user constraint.
- [x] **Placeholders:** none. Every step has either complete code, a complete command, or an explicit editor instruction with all values.
- [x] **Type consistency:** method names match across tasks (`spawn_node`, `apply(ctx)`, `template_override`, `get_template_for_slot`). Field names on Specs are consistent (`offset`, `texture`, `size`, `light_radius`, etc.).
- [x] **User art step:** Task 0 is explicit and gates the rest of the plan.
- [x] **No audio:** confirmed — no `AudioStreamPlayer`, no `.wav`/`.ogg` references anywhere in this plan.
