# Early-Floor Pacing & Risk/Reward Rooms — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the area near spawn gentler (fewer ambient enemies, no elites), and build the reusable substrate for procedural diegetic risk/reward rooms, proven end-to-end with a Treasure room.

> **⚠️ SUBAGENT HANDOFF (read first):** The room substrate and 6 rooms are **already built, tested, and committed** (see **Progress** below). Your remaining work is **Tasks 1–5** (the `CaveSpawner` / `SectorGrid` numeric changes — fully independent of the rooms) and then **Task 10** (in-game verification). **Tasks 6–9 are marked ✅ DONE — do not re-implement them.** Execute Tasks 1→5 in order (each is standalone), then Task 10.

**Architecture:** Three small, independent changes to existing systems (`CaveSpawner` density ramp, `SectorGrid` elite gating + room-weight tuning) plus a new interactable substrate (`RoomSign` info node + `InteractableShrine` base + `FeatureRoomSign` placer) that reuses the existing `PickupContext`/`WeaponInfoPopup` proximity-popup pipeline. A Treasure room composition wires it together and proves procedural placement of a room with a readable Sign.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 tests, `ArenaComposition`/`ArenaFeature` room system, `PickupContext` pickup pipeline.

## Global Constraints

- **Engine:** Godot 4, GDScript. Follow existing file conventions in `src/core/`, `src/core/features/`, `src/core/interactables/` (new dir).
- **Tests:** gdUnit4. Test files live in `tests/unit/`, `extends GdUnitTestSuite`, use `preload()` for scripts, `assert_that(...)` / `assert_bool(...)`.
- **Run tests:** `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd` — run in the foreground and wait ~30–60s for headless boot before output appears.
- **Fresh worktree:** run `godot --headless --path . --import` once before the first test run (generates the `.uid` cache).
- **Typed const arrays** must use typed-literal syntax or the script fails to parse.
- **Determinism:** `SectorGrid.resolve_sector()` is seeded and must stay reproducible — gate elite rooms by converting the roll to *empty*, never by re-rolling.
- **After code changes:** run `graphify update .` to keep the knowledge graph current (AST-only, no API cost).

## Scope note

This plan implements **Phase 1** of the spec (`docs/superpowers/specs/2026-07-10-early-floor-pacing-risk-reward-rooms-design.md`): the pacing/elite changes and the room substrate, ending with a working Treasure room. The 10 risk/reward rooms (Phases 2–3 of the spec) are a **roadmap at the end of this document** — each becomes its own bite-sized plan once this substrate lands and its interfaces (`InteractableShrine`, `FeatureRoomSign`, curse status) are real rather than speculative.

## Progress — already built & committed (as of 2026-07-10)

The **room layer** was hand-authored ahead of the numeric tasks (Godot resource/composition wiring is error-prone for automated implementers) and is committed & unit-tested:

- **Substrate** (`ba19278f`): `src/core/interactables/room_sign.gd` (`RoomSign`), `interactable_shrine.gd` (`InteractableShrine` base — one-shot `interact`→`_on_interact`, visible sprite, shared `_spawn_chest_here`/`_spawn_melee`/`_inventory` helpers), `src/core/features/feature_room_sign.gd` (`FeatureRoomSign`). Tests: `test_room_sign.gd`, `test_interactable_shrine.gd`, `test_feature_room_sign.gd`.
- **Treasure room** (`01f9e639`): `assets/arenas/reward/caves_treasure.tres`, wired into `assets/biomes/caves.tres`. Test: `test_treasure_room.gd`.
- **5 event rooms** (`fa26e305`): `src/core/interactables/{blood_altar,mimic_chest,greed_vault,trial_gauntlet}.gd`, placer features `src/core/features/{feature_interactable,feature_hazard_flood}.gd`, compositions in `assets/arenas/event/`, all wired into `caves.tres`. Tests: `test_blood_altar.gd`, `test_event_rooms.gd`.

**16 unit tests pass.** These correspond to **Tasks 6–9 (✅ DONE below)** plus the Phase-2 rooms from the roadmap. What remains for subagents: **Tasks 1–5** (numeric `CaveSpawner`/`SectorGrid` changes — do NOT touch the rooms) and **Task 10** (verification). The curse/forge/idol rooms (Phase 3) are still deferred.

---

### Task 1: CaveSpawner origin-distance density multiplier (pure math)

Add the ramp function and its member state. This task is just the pure, testable multiplier + the per-tick distance read; application to cap/prob/group comes in Task 2.

**Files:**
- Modify: `src/core/cave_spawner.gd`
- Test: `tests/unit/test_cave_spawner.gd`

**Interfaces:**
- Produces: `CaveSpawner.NEAR_ORIGIN_MULT: float`; static `CaveSpawner.origin_density_mult(sector_dist: int) -> float`; instance `_player_origin_dist() -> int`; member `_current_density_mult: float` (defaults `1.0`).

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_cave_spawner.gd`:

```gdscript
func test_origin_density_mult_is_low_at_origin() -> void:
	assert_float(_CaveSpawner.origin_density_mult(0)).is_equal_approx(0.45, 0.001)

func test_origin_density_mult_is_full_at_wall() -> void:
	assert_float(_CaveSpawner.origin_density_mult(8)).is_equal_approx(1.0, 0.001)

func test_origin_density_mult_is_monotonic() -> void:
	var prev := -1.0
	for d in range(0, 9):
		var m := _CaveSpawner.origin_density_mult(d)
		assert_bool(m >= prev).is_true()
		prev = m
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: FAIL — `origin_density_mult` not found on `_CaveSpawner`.

- [ ] **Step 3: Write minimal implementation**

In `src/core/cave_spawner.gd`, after the existing constants (near line 22), add:

```gdscript
const NEAR_ORIGIN_MULT: float = 0.45

var _current_density_mult: float = 1.0


static func origin_density_mult(sector_dist: int) -> float:
	var t := clampf(float(sector_dist) / float(SectorGrid.WALL_INNER_SECTORS), 0.0, 1.0)
	return lerpf(NEAR_ORIGIN_MULT, 1.0, t)


func _player_origin_dist() -> int:
	var grid: SectorGrid = LevelManager.get_grid()
	if grid == null or not is_instance_valid(_world_manager):
		return SectorGrid.WALL_INNER_SECTORS  # no grid in isolation → full density
	var sector := grid.world_to_sector(_world_manager.tracking_position)
	return grid.chebyshev_distance(sector, Vector2i.ZERO)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: PASS (new tests + all existing tests still green).

- [ ] **Step 5: Commit**

```bash
git add src/core/cave_spawner.gd tests/unit/test_cave_spawner.gd
git commit -m "feat(spawner): add origin-distance density multiplier"
```

---

### Task 2: Apply the density ramp to cap, spawn probability, and group size

**Files:**
- Modify: `src/core/cave_spawner.gd:14` (mob_cap default), `_on_spawn_tick`, `_validate_position`
- Test: `tests/unit/test_cave_spawner.gd`

**Interfaces:**
- Consumes: `origin_density_mult`, `_player_origin_dist`, `_current_density_mult` from Task 1.
- Produces: `_validate_position` now multiplies its spawn gate by `_current_density_mult`; `_on_spawn_tick` sets `_current_density_mult` and applies it to the effective cap and group size. `mob_cap` default is `50`.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_cave_spawner.gd`:

```gdscript
func test_density_mult_scales_validation_gate() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)
	spawner._world_manager = auto_free(_FakeWorldManager.new())
	spawner.spawn_min_dist = 0.0
	spawner.spawn_max_dist = 100000.0
	spawner.spawn_rate = 1.0  # gate = randf() > 0.5 * mult
	# Near origin: multiplier suppresses spawns hard.
	spawner._current_density_mult = 0.0
	var accepted := 0
	for _i in range(200):
		if spawner._validate_position(Vector2(500, 0)):
			accepted += 1
	assert_int(accepted).is_equal(0)

func test_mob_cap_default_is_trimmed() -> void:
	var spawner := auto_free(_CaveSpawner.new())
	assert_int(spawner.mob_cap).is_equal(50)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: FAIL — gate not yet multiplied (`accepted` > 0) and `mob_cap` still 70.

- [ ] **Step 3: Write minimal implementation**

In `src/core/cave_spawner.gd`:

Change line 14 from `@export var mob_cap: int = 70` to:

```gdscript
@export var mob_cap: int = 50
```

In `_validate_position`, change the spawn-chance gate (currently line 160):

```gdscript
	if randf() > spawn_rate * BASE_SPAWN_CHANCE * _current_density_mult:
		return false
```

At the top of `_on_spawn_tick` (right after the `func _on_spawn_tick() -> void:` line, before the cap check), add:

```gdscript
	_current_density_mult = origin_density_mult(_player_origin_dist())
	var effective_cap := int(mob_cap * _current_density_mult)
```

Change the cap check (currently `if _count_live_enemies() >= mob_cap:`) to use `effective_cap`, and change the later `mob_cap` references inside the group-size clamp (currently lines 139–140) to `effective_cap`. Change the group-size draw (currently line 138 `var size := randi_range(group_size_min, group_size_max)`) to:

```gdscript
				var gmin := maxi(1, int(group_size_min * _current_density_mult))
				var gmax := maxi(gmin, int(group_size_max * _current_density_mult))
				var size := randi_range(gmin, gmax)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: PASS (including existing `test_mob_cap_enforcement`, which sets `mob_cap = 3` explicitly and is unaffected).

- [ ] **Step 5: Commit**

```bash
git add src/core/cave_spawner.gd tests/unit/test_cave_spawner.gd
git commit -m "feat(spawner): ramp ambient density down near origin, trim mob cap"
```

---

### Task 3: Scale ambient elite chance by density near origin

**Files:**
- Modify: `src/core/cave_spawner.gd:201` (`_spawn_enemy` elite roll)
- Test: `tests/unit/test_cave_spawner.gd`

**Interfaces:**
- Consumes: `_current_density_mult` from Task 1/2.
- Produces: `_spawn_enemy` rolls elite against `elite_chance * _current_density_mult`.

- [ ] **Step 1: Write the failing test**

The elite roll is buried inside `_spawn_enemy`, which also needs a spawn parent. Extract the probability into a tiny pure helper so it is directly testable. Add to `tests/unit/test_cave_spawner.gd`:

```gdscript
func test_effective_elite_chance_scales_with_density() -> void:
	var spawner := auto_free(_CaveSpawner.new())
	spawner.elite_chance = 0.4
	spawner._current_density_mult = 0.5
	assert_float(spawner._effective_elite_chance()).is_equal_approx(0.2, 0.001)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: FAIL — `_effective_elite_chance` not defined.

- [ ] **Step 3: Write minimal implementation**

In `src/core/cave_spawner.gd`, add the helper (near `_pick_enemy_scene`):

```gdscript
func _effective_elite_chance() -> float:
	return elite_chance * _current_density_mult
```

In `_spawn_enemy`, change the elite roll (currently line 201) to:

```gdscript
	var is_elite_roll := randf() < _effective_elite_chance()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_cave_spawner.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/cave_spawner.gd tests/unit/test_cave_spawner.gd
git commit -m "feat(spawner): scale ambient elite chance by origin density"
```

---

### Task 4: Gate elite rooms out of the early zone in SectorGrid

**Files:**
- Modify: `src/core/sector_grid.gd` (add `ELITE_MIN_DIST`, gate in `resolve_sector`)
- Test: `tests/unit/test_sector_grid.gd`

**Interfaces:**
- Produces: `SectorGrid.ELITE_MIN_DIST: int = 3`; `resolve_sector` returns an empty slot when a rolled template has `is_elite_chest == true` and the sector's Chebyshev distance from origin is `< ELITE_MIN_DIST`.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_sector_grid.gd` a biome helper whose only room template is an elite room, then assert gating:

```gdscript
func _make_elite_biome() -> Resource:
	var b := _BiomeDef.new()
	var elite := _RoomTemplate.new()
	elite.png_path = "elite"
	elite.weight = 50.0          # dominate the roll so non-empty ≈ always elite
	elite.is_elite_chest = true
	var templates: Array[RoomTemplate] = [elite]
	b.room_templates = templates
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b

func test_elite_room_gated_near_origin() -> void:
	var grid := _SectorGrid.new(4242, _make_elite_biome())
	for x in range(-2, 3):
		for y in range(-2, 3):
			var c := Vector2i(x, y)
			if grid.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.ELITE_MIN_DIST:
				continue
			var slot := grid.resolve_sector(c)
			var tmpl := grid.get_template_for_slot(slot)
			assert_bool(tmpl != null and tmpl.is_elite_chest).is_false()

func test_elite_room_allowed_beyond_min_dist() -> void:
	var grid := _SectorGrid.new(4242, _make_elite_biome())
	var found_elite := false
	for x in range(-7, 8):
		for y in range(-7, 8):
			var c := Vector2i(x, y)
			var d := grid.chebyshev_distance(c, Vector2i.ZERO)
			if d < _SectorGrid.ELITE_MIN_DIST or d >= _SectorGrid.WALL_INNER_SECTORS:
				continue
			var slot := grid.resolve_sector(c)
			var tmpl := grid.get_template_for_slot(slot)
			if tmpl != null and tmpl.is_elite_chest:
				found_elite = true
	assert_bool(found_elite).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd`
Expected: FAIL — `ELITE_MIN_DIST` not defined and near-origin elite rooms still appear.

- [ ] **Step 3: Write minimal implementation**

In `src/core/sector_grid.gd`, after `const ELITE_CLAIM_RADIUS := 1` (line 11) add:

```gdscript
const ELITE_MIN_DIST := 3   # elite rooms only appear at Chebyshev sector dist >= this
```

In `resolve_sector`, inside the weighted-selection loop, change the `if roll < cumulative:` body (currently starting line 135) so the template is fetched first and elite rooms near origin become empty:

```gdscript
		if roll < cumulative:
			var tmpl: RoomTemplate = _biome.room_templates[i]
			if tmpl.is_elite_chest and dist < ELITE_MIN_DIST:
				slot.is_empty = true
				return slot
			slot.template_index = i
			slot.rotation = (rng2.randi() % 4) * 90 if tmpl.rotatable else 0
			slot.template_size = tmpl.size_class
			if tmpl.cavern_carve:
				slot.composition = tmpl.composition
			return slot
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd`
Expected: PASS (existing determinism tests still green — gating only affects near-origin elite rolls).

- [ ] **Step 5: Commit**

```bash
git add src/core/sector_grid.gd tests/unit/test_sector_grid.gd
git commit -m "feat(grid): gate elite rooms out of the early zone (dist < 3)"
```

---

### Task 5: Lower EMPTY_WEIGHT and pin room density with a test

**Files:**
- Modify: `src/core/sector_grid.gd:12` (`EMPTY_WEIGHT`)
- Test: `tests/unit/test_sector_grid.gd`

**Interfaces:**
- Produces: `SectorGrid.EMPTY_WEIGHT = 1.0` (was `1.5`), raising room frequency.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_sector_grid.gd`. With one template of weight 2.0 and `EMPTY_WEIGHT = 1.0`, `P(empty) = 1.0 / (1.0 + 2.0) ≈ 0.333`:

```gdscript
func test_empty_fraction_matches_lowered_weight() -> void:
	var b := _BiomeDef.new()
	var rt := _RoomTemplate.new()
	rt.png_path = "rt"
	rt.weight = 2.0
	var templates: Array[RoomTemplate] = [rt]
	b.room_templates = templates
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	var grid := _SectorGrid.new(777, b)
	var empty := 0
	var total := 0
	for x in range(-6, 7):
		for y in range(-6, 7):
			var c := Vector2i(x, y)
			if grid.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.WALL_INNER_SECTORS:
				continue
			total += 1
			if grid.resolve_sector(c).is_empty:
				empty += 1
	var frac := float(empty) / float(total)
	assert_float(frac).is_equal_approx(0.333, 0.08)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd`
Expected: FAIL — with `EMPTY_WEIGHT = 1.5`, `P(empty) ≈ 0.428`, outside the tolerance band.

- [ ] **Step 3: Write minimal implementation**

In `src/core/sector_grid.gd`, change line 12:

```gdscript
const EMPTY_WEIGHT := 1.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_sector_grid.gd`
Expected: PASS. (Existing `test_resolve_sector_seed_changes` counts diffs > 30 and stays green.)

- [ ] **Step 5: Commit**

```bash
git add src/core/sector_grid.gd tests/unit/test_sector_grid.gd
git commit -m "feat(grid): lower empty weight to raise room frequency"
```

---

### Task 6: RoomSign — proximity info node reusing PickupContext ✅ DONE

> **✅ COMPLETE — committed in `ba19278f`. Do NOT re-implement.** `src/core/interactables/room_sign.gd` exists and `test_room_sign.gd` passes. Steps below are kept as reference only.

A script-only node (builds its own `CollisionShape2D` in `_ready`, like `PickupContext`) that the player can stand near to read a room's risk/reward in the existing `WeaponInfoPopup`. It implements the pickup contract but has **no** `interact()`, so the interact key does nothing on it.

**Files:**
- Create: `src/core/interactables/room_sign.gd`
- Test: `tests/unit/test_room_sign.gd`

**Interfaces:**
- Produces: `class_name RoomSign extends Area2D` with `@export var title: String`, `@export_multiline var body: String`; methods `get_pickup_type() -> int` (returns `Drop.PickupType.PORTAL` as a neutral non-weapon value), `should_auto_pickup() -> bool` (false), `set_highlighted(enabled: bool)`, `populate_info_card(card: Card)`. Detected by `PickupContext` because it exposes `get_pickup_type` + `should_auto_pickup` on collision layer 2.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_room_sign.gd`:

```gdscript
extends GdUnitTestSuite

const _RoomSign = preload("res://src/core/interactables/room_sign.gd")

func test_sign_is_not_auto_pickup() -> void:
	var sign := auto_free(_RoomSign.new())
	assert_bool(sign.should_auto_pickup()).is_false()

func test_sign_has_no_interact() -> void:
	var sign := auto_free(_RoomSign.new())
	assert_bool(sign.has_method("interact")).is_false()

func test_sign_exposes_pickup_contract() -> void:
	var sign := auto_free(_RoomSign.new())
	assert_bool(sign.has_method("get_pickup_type")).is_true()
	assert_bool(sign.has_method("populate_info_card")).is_true()

func test_sign_builds_collision_shape_on_ready() -> void:
	var sign := _RoomSign.new()
	add_child(sign)          # triggers _ready
	assert_int(sign.collision_layer).is_equal(2)
	var shapes := sign.get_children().filter(func(n): return n is CollisionShape2D)
	assert_int(shapes.size()).is_equal(1)
	sign.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_room_sign.gd`
Expected: FAIL — `room_sign.gd` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `src/core/interactables/room_sign.gd`:

```gdscript
class_name RoomSign
extends Area2D

## A readable in-world sign. Standing near it shows the room's risk/reward in the
## shared WeaponInfoPopup (via PickupContext). Informational only — no interact().

const DETECTION_RADIUS: float = 20.0

@export var title: String = ""
@export_multiline var body: String = ""


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)


func get_pickup_type() -> int:
	return Drop.PickupType.PORTAL


func should_auto_pickup() -> bool:
	return false


func set_highlighted(enabled: bool) -> void:
	modulate = Color(1.3, 1.3, 1.0) if enabled else Color.WHITE


func populate_info_card(card: Card) -> void:
	var lines: Array[String] = []
	for line in body.split("\n", false):
		lines.append(line)
	card.populate(null, title, lines, [])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_room_sign.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/interactables/room_sign.gd tests/unit/test_room_sign.gd
git commit -m "feat(rooms): add RoomSign proximity info node"
```

---

### Task 7: InteractableShrine — base for room interactables ✅ DONE

> **✅ COMPLETE — committed in `ba19278f` (extended in `fa26e305` with a visible sprite + shared `_spawn_chest_here`/`_spawn_melee`/`_inventory` helpers). Do NOT re-implement.** `test_interactable_shrine.gd` passes. Steps below are kept as reference only.

The base every risk/reward interactable (Phase 2/3) subclasses: it wires the pickup contract and turns the interact key into a virtual `_on_interact(player)` hook. Not placed in any room yet — this task delivers the reusable base + its contract test so later room plans reference a real type.

**Files:**
- Create: `src/core/interactables/interactable_shrine.gd`
- Test: `tests/unit/test_interactable_shrine.gd`

**Interfaces:**
- Produces: `class_name InteractableShrine extends Area2D` with `@export var title: String`, `@export_multiline var body: String`, `var consumed: bool`; methods `get_pickup_type()`, `should_auto_pickup()` (false), `set_highlighted(enabled)`, `populate_info_card(card)`, `interact(player)` (guards on `consumed`, calls `_on_interact(player)`, sets `consumed = true`), and virtual `_on_interact(_player) -> void` (override point for subclasses).

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_interactable_shrine.gd`:

```gdscript
extends GdUnitTestSuite

const _Shrine = preload("res://src/core/interactables/interactable_shrine.gd")

class _SpyShrine extends "res://src/core/interactables/interactable_shrine.gd":
	var interacts: int = 0
	func _on_interact(_player) -> void:
		interacts += 1

func test_interact_invokes_hook_once_then_consumes() -> void:
	var shrine := auto_free(_SpyShrine.new())
	shrine.interact(null)
	shrine.interact(null)   # second call ignored — already consumed
	assert_int(shrine.interacts).is_equal(1)
	assert_bool(shrine.consumed).is_true()

func test_shrine_is_not_auto_pickup() -> void:
	var shrine := auto_free(_Shrine.new())
	assert_bool(shrine.should_auto_pickup()).is_false()

func test_shrine_builds_collision_shape_on_ready() -> void:
	var shrine := _Shrine.new()
	add_child(shrine)
	assert_int(shrine.collision_layer).is_equal(2)
	sign_free(shrine)

func sign_free(n: Node) -> void:
	n.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_interactable_shrine.gd`
Expected: FAIL — `interactable_shrine.gd` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `src/core/interactables/interactable_shrine.gd`:

```gdscript
class_name InteractableShrine
extends Area2D

## Base for diegetic risk/reward interactables. PickupContext highlights it and shows
## its info card; pressing interact fires _on_interact(player) exactly once, then the
## shrine is consumed. Subclasses override _on_interact.

const DETECTION_RADIUS: float = 20.0

@export var title: String = ""
@export_multiline var body: String = ""

var consumed: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)


func get_pickup_type() -> int:
	return Drop.PickupType.PORTAL


func should_auto_pickup() -> bool:
	return false


func set_highlighted(enabled: bool) -> void:
	modulate = Color(1.3, 1.3, 1.0) if enabled else Color.WHITE


func populate_info_card(card: Card) -> void:
	var lines: Array[String] = []
	for line in body.split("\n", false):
		lines.append(line)
	card.populate(null, title, lines, [])


func interact(player: Node) -> void:
	if consumed:
		return
	consumed = true
	_on_interact(player)


func _on_interact(_player) -> void:
	pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_interactable_shrine.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/interactables/interactable_shrine.gd tests/unit/test_interactable_shrine.gd
git commit -m "feat(rooms): add InteractableShrine base for room interactables"
```

---

### Task 8: FeatureRoomSign — ArenaFeature that places a RoomSign ✅ DONE

> **✅ COMPLETE — committed in `ba19278f`. Do NOT re-implement.** `src/core/features/feature_room_sign.gd` exists and `test_feature_room_sign.gd` passes. Also built: `feature_interactable.gd` (places an `InteractableShrine` subclass by script) and `feature_hazard_flood.gd`. Steps below are kept as reference only.

An `ArenaFeature` (like `FeatureChestSpawn`) that spawns a configured `RoomSign` at the room anchor via the dispatcher.

**Files:**
- Create: `src/core/features/feature_room_sign.gd`
- Test: `tests/unit/test_feature_room_sign.gd`

**Interfaces:**
- Consumes: `RoomSign` (Task 6); `ctx.dispatcher.spawn_node(node, world_pos)`, `ctx.anchor_world_pos` (existing `CompositionContext`).
- Produces: `class_name FeatureRoomSign extends ArenaFeature` with `@export var title: String`, `@export_multiline var body: String`, `@export var offset: Vector2`; `apply(ctx)` builds a `RoomSign`, sets `title`/`body`, and calls `ctx.dispatcher.spawn_node(sign, ctx.anchor_world_pos + offset)`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_feature_room_sign.gd`. Use a fake dispatcher capturing `spawn_node`:

```gdscript
extends GdUnitTestSuite

const _Feature = preload("res://src/core/features/feature_room_sign.gd")

class _FakeCtx:
	var anchor_world_pos: Vector2 = Vector2(100, 200)
	var dispatcher

class _FakeDispatcher:
	var spawned: Node = null
	var spawned_pos: Vector2 = Vector2.ZERO
	func spawn_node(node, world_pos: Vector2) -> void:
		spawned = node
		spawned_pos = world_pos

func test_feature_places_sign_with_text_at_offset() -> void:
	var feat := _Feature.new()
	feat.title = "Treasure"
	feat.body = "A safe chest."
	feat.offset = Vector2(0, -8)
	var ctx := _FakeCtx.new()
	var disp := _FakeDispatcher.new()
	ctx.dispatcher = disp
	feat.apply(ctx)
	assert_object(disp.spawned).is_not_null()
	assert_str(disp.spawned.title).is_equal("Treasure")
	assert_vector(disp.spawned_pos).is_equal(Vector2(100, 192))
	disp.spawned.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_feature_room_sign.gd`
Expected: FAIL — `feature_room_sign.gd` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `src/core/features/feature_room_sign.gd`:

```gdscript
class_name FeatureRoomSign
extends ArenaFeature

@export var title: String = ""
@export_multiline var body: String = ""
@export var offset: Vector2 = Vector2.ZERO


func apply(ctx) -> void:
	var sign := RoomSign.new()
	sign.title = title
	sign.body = body
	ctx.dispatcher.spawn_node(sign, ctx.anchor_world_pos + offset)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_feature_room_sign.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/features/feature_room_sign.gd tests/unit/test_feature_room_sign.gd
git commit -m "feat(rooms): add FeatureRoomSign placer"
```

---

### Task 9: Treasure room composition + wire into the Caves biome ✅ DONE

> **✅ COMPLETE — committed in `01f9e639`. Do NOT re-implement.** `assets/arenas/reward/caves_treasure.tres` exists, wired into `caves.tres`, `test_treasure_room.gd` passes. The 5 event rooms (Blood Altar, Mimic Chest, Greed Vault, Trial Gauntlet, Reactor Chamber) were also authored on this same pattern (`fa26e305`) and wired into `caves.tres`. Steps below are kept as reference only.

Author a Treasure `ArenaComposition` (chest + sign) as a `.tres`, add it as a `cavern_carve` room template in `caves.tres`, and prove it loads with both features. This is the end-to-end substrate proof.

**Files:**
- Create: `assets/arenas/reward/caves_treasure.tres`
- Modify: `assets/biomes/caves.tres` (add ext_resource + sub_resource template + append to `room_templates`)
- Test: `tests/unit/test_treasure_room.gd`

**Interfaces:**
- Consumes: `FeatureChestSpawn` (existing), `FeatureRoomSign` (Task 8), `ArenaComposition` schema.
- Produces: a loadable Caves room template whose composition contains a `FeatureChestSpawn` and a `FeatureRoomSign`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_treasure_room.gd`:

```gdscript
extends GdUnitTestSuite

func test_caves_has_treasure_room_with_chest_and_sign() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_object(biome).is_not_null()
	var found := false
	for tmpl in biome.room_templates:
		var rt := tmpl as RoomTemplate
		if rt.composition == null:
			continue
		var comp := rt.composition as ArenaComposition
		if comp.arena_kind != &"reward":
			continue
		var has_chest := false
		var has_sign := false
		for f in comp.features:
			if f is FeatureChestSpawn:
				has_chest = true
			if f is FeatureRoomSign:
				has_sign = true
		if has_chest and has_sign:
			found = true
	assert_bool(found).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_treasure_room.gd`
Expected: FAIL — no `reward` composition in `caves.tres`.

- [ ] **Step 3: Write minimal implementation**

Create `assets/arenas/reward/caves_treasure.tres` (mirror an existing arena `.tres` in `assets/arenas/elite/`; confirm the `FeatureChestSpawn` / `FeatureRoomSign` script `uid://` values against those files):

```
[gd_resource type="Resource" script_class="ArenaComposition" format=3]

[ext_resource type="Script" path="res://src/core/arena_composition.gd" id="1_comp"]
[ext_resource type="Script" path="res://src/core/features/feature_chest_spawn.gd" id="2_chest"]
[ext_resource type="Script" path="res://src/core/features/feature_room_sign.gd" id="3_sign"]

[sub_resource type="Resource" id="Res_chest"]
script = ExtResource("2_chest")
rare = false

[sub_resource type="Resource" id="Res_sign"]
script = ExtResource("3_sign")
title = "Treasure"
body = "A safe chest. No catch."
offset = Vector2(0, -24)

[resource]
script = ExtResource("1_comp")
arena_kind = &"reward"
nominal_radius = 256
features = [SubResource("Res_chest"), SubResource("Res_sign")]
```

In `assets/biomes/caves.tres`: add an `ext_resource` pointing at the new file, add a `sub_resource` `RoomTemplate` with `cavern_carve = true`, `weight = 2.5`, `composition = ExtResource(<treasure>)`, and append that sub-resource to the `room_templates` array (follow the exact pattern of the existing `Resource_elite_*` entries and the `room_templates = Array[...]([...])` line).

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_treasure_room.gd`
Expected: PASS. If it fails to load, re-run `godot --headless --path . --import` and check the `uid://` values in the `.tres` match the scripts.

- [ ] **Step 5: Commit**

```bash
git add assets/arenas/reward/caves_treasure.tres assets/biomes/caves.tres tests/unit/test_treasure_room.gd
git commit -m "feat(rooms): add Treasure room to Caves biome"
```

---

### Task 10: In-editor verification + graph refresh

- [ ] **Step 1: Full unit-test sweep**

Run the whole suite to confirm no regressions:

```bash
GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit
```
Expected: all green.

- [ ] **Step 2: Manual smoke test in-game — pacing (Tasks 1–5)**

Launch the project (`mcp__godot__run_project` or the editor). Confirm, near spawn: noticeably fewer ambient enemies and no elites; walking outward increases density and elites reappear.

- [ ] **Step 3: Manual smoke test in-game — rooms (already built; verifies carve + runtime paths)**

The rooms are committed and unit-tested, but their **in-game behaviour is not yet verified**. Confirm each:
- **Carving:** `arena_kind = &"event"` templates carve open cavern space (not embedded in rock). If they don't carve, inspect how the shader/generator selects carve templates for compositions (`shaders/include/cavern_carve_stage.glslinc`, `LevelManager.build_stamp_bytes`) — the `nominal_radius`/`inner_disc_radius` on each `assets/arenas/event/*.tres` drive the carve.
- **Signs:** standing by a room's Sign shows its description in the info popup.
- **Treasure:** chest present, no catch.
- **Blood Altar:** interacting drops ~25% current HP and spawns a rich chest.
- **Mimic Chest:** interacting either opens a chest or triggers an ambush.
- **Greed Vault:** interacting spawns a chest and then waves of enemies.
- **Trial Gauntlet:** interacting spawns 5 elites; clearing them spawns a chest.
- **Reactor Chamber:** floor is flooded with lava hazard; a rare chest is present.

Report any room that fails; fixes to a room are content edits (`.tres` radius, interactable script), independent of Tasks 1–5.

- [ ] **Step 4: Refresh the knowledge graph**

```bash
graphify update .
```

- [ ] **Step 5: Commit any doc/graph updates**

```bash
git add -A && git commit -m "chore: refresh graph after early-floor pacing + room substrate" || echo "nothing to commit"
```

---

## Roadmap — Phases 2 & 3 (separate plans)

Once this plan lands, each room below becomes its own short bite-sized plan built on the substrate above (`InteractableShrine`, `FeatureRoomSign`, chest/enemy dispatcher APIs). Expand these in dependency order; the interfaces they need now exist and can be referenced concretely.

**Phase 2 — easy diegetic rooms (no new subsystems): ✅ ALL DONE (`fa26e305`, `01f9e639`)**
- **Treasure** ✅ — `caves_treasure.tres`; plain HARD-less chest.
- **Mimic Chest** ✅ — `mimic_chest.gd`; interact → 60% HARD chest / 40% 6-enemy ambush.
- **Greed Vault** ✅ — `greed_vault.gd`; interact → HARD chest + 3 waves × 4 melee (1.5s apart).
- **Reactor Chamber** ✅ — `caves_reactor_chamber.tres`; `feature_hazard_flood.gd` floods lava + rare chest.
- **Trial Gauntlet** ✅ — `trial_gauntlet.gd`; interact → 5 elite melee, HARD chest on clear.
- **Blood Altar** ✅ — `blood_altar.gd`; interact → −25% current HP (min 5) → HARD chest.

Balance values above are first-pass; tune in the `.tres`/interactable scripts. Remaining polish (not blocking): replace placeholder RPG-pack icons with bespoke art; confirm in-game carve (Task 10, Step 3).

**Phase 3 — subsystem rooms (still to build):**
- **Curse status** (shared) — a lasting negative status on the existing status system; cleared on cure and in `LevelManager.advance_floor()`. Prerequisite for the next three.
- **Devil's Bargain** — a `ModifierDrop` that also applies a curse on pickup.
- **Wheel of Fortune** — `InteractableShrine` spending gold → weighted jackpot / nothing / spawn-elite (may apply a curse on backfire).
- **Purge Font** — `InteractableShrine` spending gold → remove one active curse (else heal).
- **Transmutation Forge** — drop-item-on-machine interaction consuming a held item to reroll another.
- **Whispering Idol** — `InteractableShrine` applying a floor-long buff + floor-long hex pact.

---

## Self-Review

**Spec coverage:** Pillar 1 (density ramp + mob_cap trim) → Tasks 1–2 (TODO); ambient elite scaling → Task 3 (TODO). Pillar 2 (elite room gating dist ≥ 3) → Task 4 (TODO). Pillar 3 placement/frequency (EMPTY_WEIGHT + boosted weight) → Task 5 (TODO) & Task 9 (✅); Sign → Task 6 (✅); InteractableShrine substrate → Task 7 (✅); FeatureRoomSign → Task 8 (✅); procedural room proof + 5 event rooms → Task 9 & roadmap Phase 2 (✅). Curse status + the 4 Phase-3 rooms remain deferred. **Subagent scope = Tasks 1–5 + Task 10.**

**Placeholder scan:** none — every code step shows full code; the one `.tres` step names the exact pattern file to mirror and the exact fields.

**Type consistency:** `origin_density_mult`/`_current_density_mult`/`_player_origin_dist` consistent across Tasks 1–3; `ELITE_MIN_DIST`/`EMPTY_WEIGHT` consistent in Tasks 4–5; `RoomSign` (Task 6) consumed by `FeatureRoomSign` (Task 8) and asserted in Task 9; `InteractableShrine._on_interact` defined once (Task 7) and referenced by the roadmap.
