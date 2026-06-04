# Status Effect System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Noita-style, stain-based status effect system shared by the player and enemies (six fire/cold statuses with cross-reactions and terrain sourcing), replace direct lava/fire contact damage with the On Fire status, and add a crit system that wires up caliburn, flame_sword, frost_sword, and heavenly_sword.

**Architecture:** A data-only `StatusRegistry` autoload owns every status definition and the reaction rules. A `StatusComponent` node (attached in code to both the player and every enemy) holds per-entity "stain" amounts, decays them, runs reactions, applies effects (burn DoT, movement block/slow), and tops up stains from the terrain the entity stands on. Owners expose only `apply_status_damage(int)` and read `is_movement_blocked()` / `get_move_speed_multiplier()`. Crit is data-driven via three new `weapons.csv` columns and a small `Weapon` API; on a crit, a weapon applies its configured status to the target's `StatusComponent`.

**Tech Stack:** Godot 4 / GDScript. Tests use gdUnit4 (`extends GdUnitTestSuite`, `assert_that(...).is_equal(...)`). Run a test with: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/<file>.gd`.

---

## Spec reference

`docs/superpowers/specs/2026-06-04-status-effect-system-design.md`

## File structure

**Create:**
- `src/status/status_def.gd` — `StatusDef` value object describing one status.
- `src/autoload/status_registry.gd` — `StatusRegistry` autoload: all defs + reaction rules + material→status mapping.
- `src/status/status_component.gd` — `StatusComponent` node: stains, decay, reactions dispatch, effects, terrain poll.
- `tests/unit/test_status_registry.gd` — registry getters + material mapping.
- `tests/unit/test_status_reactions.gd` — the six reaction rules.
- `tests/unit/test_status_component.gd` — stain/decay/threshold/move-mult/burn.
- `tests/unit/test_weapon_crit.gd` — crit API on `Weapon`.
- `tests/unit/test_weapon_crit_csv.gd` — crit CSV overlay on the four weapons.

**Modify:**
- `project.godot` — register `StatusRegistry` autoload.
- `src/player/player_controller.gd` — attach `StatusComponent`, add `apply_status_damage`, gate movement.
- `src/player/player_inventory.gd` — add `take_status_damage`.
- `src/enemies/enemy.gd` — attach `StatusComponent`, add `apply_status_damage`, gate movement.
- `src/player/lava_damage_checker.gd` — remove lava/fire direct damage.
- `src/enemies/terrain_damage_receiver.gd` — remove lava/fire direct damage.
- `src/weapons/weapon.gd` — crit fields + `get_effective_crit_chance`/`roll_crit`/`_on_crit`.
- `src/weapons/modifier.gd` — `modify_crit_chance` hook.
- `src/weapons/melee_weapon.gd` — crit resolution per hit.
- `src/weapons/ranged_weapon.gd` + `src/weapons/projectile.gd` — projectile crit + status.
- `docs/design_docs/weapons.csv` — add `crit_chance`, `crit_multiplier`, `crit_status` columns + values.
- `src/autoload/weapon_registry.gd` — overlay crit columns.
- `src/ui/hud.gd` — status-icon strip.

---

## Task 1: StatusDef value object

**Files:**
- Create: `src/status/status_def.gd`

- [ ] **Step 1: Create the StatusDef class**

```gdscript
class_name StatusDef
extends RefCounted

enum Category { HARMFUL, NEUTRAL, BENEFICIAL }

var id: String
var display_name: String
var tint_color: Color
var decay_rate: float       # stain lost per second
var active_threshold: float # active once stain >= this
var category: int
var burn_dps: float         # > 0 means deals burn damage while active
var blocks_movement: bool   # true => immobile while active
var slow_multiplier: float  # movement speed multiplier while active (1.0 = none)


func _init(
	p_id: String,
	p_display_name: String,
	p_tint_color: Color,
	p_decay_rate: float,
	p_active_threshold: float,
	p_category: int = Category.NEUTRAL,
	p_burn_dps: float = 0.0,
	p_blocks_movement: bool = false,
	p_slow_multiplier: float = 1.0,
) -> void:
	id = p_id
	display_name = p_display_name
	tint_color = p_tint_color
	decay_rate = p_decay_rate
	active_threshold = p_active_threshold
	category = p_category
	burn_dps = p_burn_dps
	blocks_movement = p_blocks_movement
	slow_multiplier = p_slow_multiplier
```

- [ ] **Step 2: Commit**

```bash
git add src/status/status_def.gd
git commit -m "feat: add StatusDef value object for status effects"
```

---

## Task 2: StatusRegistry definitions + getters

**Files:**
- Create: `src/autoload/status_registry.gd`
- Modify: `project.godot` (autoload section)
- Test: `tests/unit/test_status_registry.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_on_fire_def_values() -> void:
	assert_that(StatusRegistry.has_def("on_fire")).is_true()
	assert_float(StatusRegistry.get_threshold("on_fire")).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_burn_dps("on_fire")).is_equal_approx(4.0, 0.001)

func test_frozen_blocks_movement() -> void:
	assert_that(StatusRegistry.blocks_movement("frozen")).is_true()
	assert_float(StatusRegistry.get_threshold("frozen")).is_equal_approx(3.0, 0.001)

func test_chilly_slows() -> void:
	assert_that(StatusRegistry.blocks_movement("chilly")).is_false()
	assert_float(StatusRegistry.get_slow_multiplier("chilly")).is_equal_approx(0.6, 0.001)

func test_unknown_def_safe_defaults() -> void:
	assert_that(StatusRegistry.has_def("nope")).is_false()
	assert_float(StatusRegistry.get_threshold("nope")).is_equal_approx(1.0, 0.001)

func test_material_mapping() -> void:
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_LAVA)).is_equal("on_fire")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_WATER)).is_equal("wet")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_OIL)).is_equal("oiled")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_BLOOD)).is_equal("bloody")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_STONE)).is_equal("")
```

- [ ] **Step 2: Create the registry (defs + getters + material map; reactions added in Task 3)**

```gdscript
extends Node

# Data-only registry: status definitions, reaction rules, and material->status
# mapping. Shared by every StatusComponent. Adding a status = one entry here.

const StatusDefScript = preload("res://src/status/status_def.gd")

# Terrain top-up: stain added per second while standing in a source material.
const TERRAIN_STAIN_RATE := 6.0

var _defs: Dictionary = {}  # id -> StatusDef


func _ready() -> void:
	_register_defs()


func _register_defs() -> void:
	_add(StatusDefScript.new(
		"on_fire", "On Fire", Color(1.0, 0.45, 0.1, 1.0),
		1.0, 1.0, StatusDef.Category.HARMFUL, 4.0))
	_add(StatusDefScript.new(
		"wet", "Wet", Color(0.35, 0.55, 0.95, 1.0),
		0.5, 1.0, StatusDef.Category.NEUTRAL))
	_add(StatusDefScript.new(
		"oiled", "Oiled", Color(0.25, 0.18, 0.1, 1.0),
		0.3, 1.0, StatusDef.Category.NEUTRAL))
	_add(StatusDefScript.new(
		"chilly", "Chilly", Color(0.6, 0.8, 0.95, 1.0),
		0.8, 1.0, StatusDef.Category.HARMFUL, 0.0, false, 0.6))
	_add(StatusDefScript.new(
		"frozen", "Frozen", Color(0.7, 0.9, 1.0, 1.0),
		0.4, 3.0, StatusDef.Category.HARMFUL, 0.0, true, 0.0))
	_add(StatusDefScript.new(
		"bloody", "Bloody", Color(0.75, 0.08, 0.08, 1.0),
		0.4, 1.0, StatusDef.Category.NEUTRAL))


func _add(def: StatusDef) -> void:
	_defs[def.id] = def


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> StatusDef:
	return _defs.get(id, null)


func get_threshold(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.active_threshold if d != null else 1.0


func get_decay_rate(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.decay_rate if d != null else 1.0


func get_tint(id: String) -> Color:
	var d: StatusDef = _defs.get(id, null)
	return d.tint_color if d != null else Color(1, 1, 1, 1)


func get_burn_dps(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.burn_dps if d != null else 0.0


func blocks_movement(id: String) -> bool:
	var d: StatusDef = _defs.get(id, null)
	return d.blocks_movement if d != null else false


func get_slow_multiplier(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.slow_multiplier if d != null else 1.0


func stain_for_material(material_id: int) -> String:
	if material_id == MaterialRegistry.MAT_LAVA or material_id == MaterialRegistry.MAT_EXPLODE_WAVE:
		return "on_fire"
	if material_id == MaterialRegistry.MAT_WATER:
		return "wet"
	if material_id == MaterialRegistry.MAT_OIL:
		return "oiled"
	if material_id == MaterialRegistry.MAT_BLOOD:
		return "bloody"
	return ""
```

- [ ] **Step 3: Register the autoload**

In `project.godot`, inside the `[autoload]` section, add this line after the `MaterialRegistry=` line (StatusRegistry references MaterialRegistry, so it must load after it):

```
StatusRegistry="*res://src/autoload/status_registry.gd"
```

- [ ] **Step 4: Run the test**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_registry.gd`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/autoload/status_registry.gd project.godot tests/unit/test_status_registry.gd
git commit -m "feat: add StatusRegistry autoload with status defs and material mapping"
```

---

## Task 3: StatusRegistry reaction rules

**Files:**
- Modify: `src/autoload/status_registry.gd`
- Create: `tests/unit/test_status_reactions.gd`

The reactions operate on a `StatusComponent` (created in Task 4) via `get_stain`, `add_stain`, and `reduce_stain`. We write the rules now against that interface; the component implements the methods next task. The reaction test constructs a `StatusComponent` directly (it does not need the scene tree).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const StatusComponentScript = preload("res://src/status/status_component.gd")

func _make_comp() -> StatusComponent:
	return auto_free(StatusComponentScript.new())

func test_wet_extinguishes_fire() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 5.0)
	c.add_stain("wet", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# fire drained by WET_EXTINGUISH_RATE (4), wet by WET_EVAP_BONUS (1)
	assert_float(c.get_stain("on_fire")).is_equal_approx(1.0, 0.001)
	assert_float(c.get_stain("wet")).is_equal_approx(4.0, 0.001)

func test_bloody_dampens_fire() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 5.0)
	c.add_stain("bloody", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	assert_float(c.get_stain("on_fire")).is_equal_approx(3.5, 0.001)  # -1.5

func test_oiled_feeds_fire() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 1.0)
	c.add_stain("oiled", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# oiled consumed by OIL_FEED_RATE (2) -> 3; fire gains 2*OIL_FIRE_GAIN(1.5)=3 -> 4
	assert_float(c.get_stain("oiled")).is_equal_approx(3.0, 0.001)
	assert_float(c.get_stain("on_fire")).is_equal_approx(4.0, 0.001)

func test_wet_plus_chilly_makes_frozen() -> void:
	var c := _make_comp()
	c.add_stain("wet", 5.0)
	c.add_stain("chilly", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# conv = min(5,5, WET_FREEZE_RATE(2)) = 2
	assert_float(c.get_stain("wet")).is_equal_approx(3.0, 0.001)
	assert_float(c.get_stain("chilly")).is_equal_approx(3.0, 0.001)
	assert_float(c.get_stain("frozen")).is_equal_approx(2.0, 0.001)

func test_fire_melts_cold() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 5.0)
	c.add_stain("frozen", 5.0)
	c.add_stain("chilly", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# FIRE_MELT_RATE (3) drained from both
	assert_float(c.get_stain("frozen")).is_equal_approx(2.0, 0.001)
	assert_float(c.get_stain("chilly")).is_equal_approx(2.0, 0.001)

func test_chilly_ramps_to_frozen() -> void:
	var c := _make_comp()
	c.add_stain("chilly", 5.0)  # >= CHILLY_FREEZE_THRESHOLD (4)
	StatusRegistry.apply_reactions(c, 1.0)
	# CHILLY_RAMP_RATE (1) moved chilly->frozen
	assert_float(c.get_stain("chilly")).is_equal_approx(4.0, 0.001)
	assert_float(c.get_stain("frozen")).is_equal_approx(1.0, 0.001)
```

- [ ] **Step 2: Add reaction constants and `apply_reactions` to the registry**

Append to `src/autoload/status_registry.gd`:

```gdscript
# --- Reaction tuning constants ---
const WET_EXTINGUISH_RATE := 4.0   # fire stain drained/sec while wet
const WET_EVAP_BONUS := 1.0        # extra wet evaporation/sec while extinguishing
const BLOODY_DAMPEN_RATE := 1.5    # fire stain drained/sec while bloody
const OIL_FEED_RATE := 2.0         # oiled stain consumed/sec while burning
const OIL_FIRE_GAIN := 1.5         # fire gained per oiled consumed
const WET_FREEZE_RATE := 2.0       # wet+chilly converted to frozen/sec
const FIRE_MELT_RATE := 3.0        # chilly/frozen drained/sec while on fire
const CHILLY_FREEZE_THRESHOLD := 4.0
const CHILLY_RAMP_RATE := 1.0      # chilly->frozen conversion/sec past threshold


func apply_reactions(c: StatusComponent, delta: float) -> void:
	# 1. Wet extinguishes Fire.
	if c.get_stain("wet") > 0.0 and c.get_stain("on_fire") > 0.0:
		c.reduce_stain("on_fire", WET_EXTINGUISH_RATE * delta)
		c.reduce_stain("wet", WET_EVAP_BONUS * delta)
	# 2. Bloody dampens Fire (weaker than wet).
	if c.get_stain("bloody") > 0.0 and c.get_stain("on_fire") > 0.0:
		c.reduce_stain("on_fire", BLOODY_DAMPEN_RATE * delta)
	# 3. Oiled feeds Fire (only when not wet).
	if c.get_stain("oiled") > 0.0 and c.get_stain("on_fire") > 0.0 and c.get_stain("wet") <= 0.0:
		var conv: float = OIL_FEED_RATE * delta
		c.reduce_stain("oiled", conv)
		c.add_stain("on_fire", conv * OIL_FIRE_GAIN)
	# 4. Wet + Chilly -> Frozen.
	if c.get_stain("wet") > 0.0 and c.get_stain("chilly") > 0.0:
		var fconv: float = minf(minf(c.get_stain("wet"), c.get_stain("chilly")), WET_FREEZE_RATE * delta)
		if fconv > 0.0:
			c.reduce_stain("wet", fconv)
			c.reduce_stain("chilly", fconv)
			c.add_stain("frozen", fconv)
	# 5. Fire melts cold.
	if c.get_stain("on_fire") > 0.0:
		c.reduce_stain("chilly", FIRE_MELT_RATE * delta)
		c.reduce_stain("frozen", FIRE_MELT_RATE * delta)
	# 6. Sustained Chilly ramps into Frozen.
	if c.get_stain("chilly") >= CHILLY_FREEZE_THRESHOLD:
		var rconv: float = CHILLY_RAMP_RATE * delta
		c.reduce_stain("chilly", rconv)
		c.add_stain("frozen", rconv)
```

- [ ] **Step 3: Run the test (will fail to compile until Task 4 defines StatusComponent)**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_reactions.gd`
Expected: FAIL — `status_component.gd` does not exist yet. This is expected; Task 4 creates it, then we re-run.

- [ ] **Step 4: Commit (reactions only)**

```bash
git add src/autoload/status_registry.gd tests/unit/test_status_reactions.gd
git commit -m "feat: add status reaction rules to StatusRegistry"
```

---

## Task 4: StatusComponent

**Files:**
- Create: `src/status/status_component.gd`
- Test: `tests/unit/test_status_component.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const StatusComponentScript = preload("res://src/status/status_component.gd")

class FakeOwner extends Node:
	var taken: int = 0
	func apply_status_damage(amount: int) -> void:
		taken += amount

func _make_comp(owner: Node) -> StatusComponent:
	var c: StatusComponent = StatusComponentScript.new()
	owner.add_child(c)
	return c

func test_add_and_get_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 2.5)
	assert_float(c.get_stain("wet")).is_equal_approx(2.5, 0.001)

func test_has_status_threshold() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 0.5)
	assert_that(c.has_status("on_fire")).is_false()
	c.add_stain("on_fire", 1.0)  # total 1.5 >= 1.0
	assert_that(c.has_status("on_fire")).is_true()

func test_decay_reduces_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 5.0)  # decay_rate 0.5
	c.tick(1.0)
	assert_float(c.get_stain("wet")).is_equal_approx(4.5, 0.001)

func test_frozen_blocks_movement() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("frozen", 5.0)
	assert_that(c.is_movement_blocked()).is_true()
	assert_float(c.get_move_speed_multiplier()).is_equal_approx(0.0, 0.001)

func test_chilly_slows_movement() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("chilly", 2.0)
	assert_that(c.is_movement_blocked()).is_false()
	assert_float(c.get_move_speed_multiplier()).is_equal_approx(0.6, 0.001)

func test_burn_calls_owner_damage() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 5.0)  # burn_dps 4
	c.tick(1.0)  # decay -1 -> 4 (still active); burn 4*1=4 delivered
	assert_that(owner.taken).is_equal(4)

func test_active_ids_lists_active_only() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 2.0)
	c.add_stain("on_fire", 0.2)  # below threshold
	var ids: Array = c.get_active_ids()
	assert_that(ids.has("wet")).is_true()
	assert_that(ids.has("on_fire")).is_false()
```

- [ ] **Step 2: Create the StatusComponent**

```gdscript
class_name StatusComponent
extends Node

# Per-entity status holder. Attached as a child named "StatusComponent" to the
# player and every enemy. Holds "stain" amounts, decays them, runs reactions,
# applies effects (burn DoT, movement block/slow), and tops up stains from the
# terrain the owner stands on. Owner must implement apply_status_damage(int).

signal changed

const _EPSILON := 0.01

var _stains: Dictionary = {}      # id -> float amount
var _burn_accum: float = 0.0
var _owner_node: Node = null
var _terrain_physical: Node = null


func _ready() -> void:
	_owner_node = get_parent()
	var wm: Node = get_tree().get_first_node_in_group("world_manager")
	if wm != null:
		_terrain_physical = wm.get_node_or_null("TerrainPhysical")


# --- Stain access ---

func add_stain(id: String, amount: float) -> void:
	if amount == 0.0:
		return
	_stains[id] = maxf(0.0, get_stain(id) + amount)
	changed.emit()


func reduce_stain(id: String, amount: float) -> void:
	# Silent (no signal): used by reactions/decay which run every frame.
	if not _stains.has(id):
		return
	var v: float = _stains[id] - amount
	if v <= _EPSILON:
		_stains.erase(id)
	else:
		_stains[id] = v


func get_stain(id: String) -> float:
	return _stains.get(id, 0.0)


func has_status(id: String) -> bool:
	return get_stain(id) >= StatusRegistry.get_threshold(id)


func get_active_ids() -> Array:
	var result: Array = []
	for id in _stains.keys():
		if has_status(id):
			result.append(id)
	return result


func clear(id: String) -> void:
	if _stains.erase(id):
		changed.emit()


# --- Movement ---

func get_move_speed_multiplier() -> float:
	var mult: float = 1.0
	for id in _stains.keys():
		if not has_status(id):
			continue
		if StatusRegistry.blocks_movement(id):
			return 0.0
		mult = minf(mult, StatusRegistry.get_slow_multiplier(id))
	return mult


func is_movement_blocked() -> bool:
	return is_zero_approx(get_move_speed_multiplier())


# --- Per-frame update ---

func tick(delta: float) -> void:
	_decay(delta)
	StatusRegistry.apply_reactions(self, delta)
	_apply_effects(delta)
	changed.emit()


func _physics_process(delta: float) -> void:
	_poll_terrain(delta)
	tick(delta)


func _decay(delta: float) -> void:
	for id in _stains.keys():
		reduce_stain(id, StatusRegistry.get_decay_rate(id) * delta)


func _apply_effects(delta: float) -> void:
	if has_status("on_fire"):
		_burn_accum += StatusRegistry.get_burn_dps("on_fire") * delta
		var whole: int = int(_burn_accum)
		if whole >= 1:
			_burn_accum -= float(whole)
			if _owner_node != null and _owner_node.has_method("apply_status_damage"):
				_owner_node.apply_status_damage(whole)


func _poll_terrain(delta: float) -> void:
	if _terrain_physical == null or _owner_node == null:
		return
	if not (_owner_node is Node2D):
		return
	var cell = _terrain_physical.query((_owner_node as Node2D).global_position)
	if cell == null:
		return
	var id: String = StatusRegistry.stain_for_material(cell.material_id)
	if id != "":
		add_stain(id, StatusRegistry.TERRAIN_STAIN_RATE * delta)
```

- [ ] **Step 3: Run the component test**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: PASS (7 tests).

- [ ] **Step 4: Run the reaction test from Task 3 (now compiles)**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_reactions.gd`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/status/status_component.gd tests/unit/test_status_component.gd
git commit -m "feat: add StatusComponent (stains, decay, reactions, burn, movement)"
```

---

## Task 5: Attach StatusComponent to the player + damage + movement gating

**Files:**
- Modify: `src/player/player_inventory.gd` (add `take_status_damage`)
- Modify: `src/player/player_controller.gd` (attach component, `apply_status_damage`, gate movement)

`PlayerInventory.take_damage` sets invincibility frames, which would gate a per-frame DoT. Burn needs a quiet, i-frame-free path.

- [ ] **Step 1: Add `take_status_damage` to PlayerInventory**

In `src/player/player_inventory.gd`, add this method directly after the existing `take_damage` function:

```gdscript
func take_status_damage(amount: int) -> void:
	# Damage-over-time path: bypasses invincibility frames and the heavy hit
	# reaction so burn drains health smoothly. Still triggers death.
	if _is_dead or amount <= 0:
		return
	_current_health = maxi(_current_health - amount, 0)
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
		if GameModeManager.is_creative():
			_current_health = max_health
			health_changed.emit(_current_health, max_health)
		else:
			_is_dead = true
			if _color_rect:
				_color_rect.visible = true
			player_died.emit()
```

- [ ] **Step 2: Attach the component and add `apply_status_damage` to the player**

In `src/player/player_controller.gd`, find `func _ready() -> void:` (line ~41) and add, at the end of that function, code to attach the component:

```gdscript
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	add_child(status)
```

Then add this method anywhere at top level in the same file (e.g. just after `on_hit_impact`):

```gdscript
func apply_status_damage(amount: int) -> void:
	var inventory := get_node_or_null("PlayerInventory")
	if inventory:
		inventory.take_status_damage(amount)
```

- [ ] **Step 3: Gate movement on status**

In `src/player/player_controller.gd` `_physics_process`, the movement is applied at the end via `_apply_movement(input_dir, delta)` then `move_and_slide()`. Replace the line:

```gdscript
	_apply_movement(input_dir, delta)
```

with:

```gdscript
	var status := get_node_or_null("StatusComponent")
	if status and status.is_movement_blocked():
		input_dir = Vector2.ZERO
		velocity = Vector2.ZERO
	elif status:
		input_dir *= status.get_move_speed_multiplier()
	_apply_movement(input_dir, delta)
```

- [ ] **Step 4: Manual verification (no automated test — requires full scene)**

Run the game: `GODOT_BIN=godot godot --path . scenes/game.tscn` (or launch via the editor). Walk the player into lava: confirm the player no longer takes a single chunk of damage but instead steadily loses health (On Fire) and keeps burning briefly after leaving the lava. Walk into water: confirm the burn stops quickly.

- [ ] **Step 5: Commit**

```bash
git add src/player/player_inventory.gd src/player/player_controller.gd
git commit -m "feat: player status component, status damage path, movement gating"
```

---

## Task 6: Attach StatusComponent to enemies + damage + movement gating

**Files:**
- Modify: `src/enemies/enemy.gd`

Enemy `hit(damage)` forces the HURT state — wrong for a per-frame DoT. Use a quiet direct-health path.

- [ ] **Step 1: Attach the component in `_ready`**

In `src/enemies/enemy.gd` `func _ready() -> void:` (line ~66), add at the end of the function:

```gdscript
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	add_child(status)
```

- [ ] **Step 2: Add `apply_status_damage` to the enemy**

Add this method to `src/enemies/enemy.gd` (e.g. just after the `hit` function):

```gdscript
func apply_status_damage(amount: int) -> void:
	# Quiet DoT path: drains health without forcing HURT state.
	if amount <= 0 or _state == State.DEATH:
		return
	if GameModeManager.is_creative():
		amount = max_health
	health -= amount
	health_changed.emit(health, max_health)
	_play_hit_flash()
	if health <= 0:
		_change_state(State.DEATH)
		die()
```

- [ ] **Step 3: Gate enemy movement on status**

In `src/enemies/enemy.gd`, `_get_effective_speed()` (line ~525) returns the base speed used by movement states. Multiply its result by the status multiplier. Replace the function body's `return` statements so every path is scaled — simplest is to wrap the existing result. Change the function to:

```gdscript
func _get_effective_speed() -> float:
	var base := _base_effective_speed()
	var status := get_node_or_null("StatusComponent")
	if status:
		base *= status.get_move_speed_multiplier()
	return base


func _base_effective_speed() -> float:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return speed
	var target = player.get("targeted_enemy")
	if target == null:
		return speed
	if target == self:
		return speed * TARGETED_SPEED_MULT
	return speed * PASSIVE_SPEED_MULT
```

(This renames the original body to `_base_effective_speed` and applies the multiplier in `_get_effective_speed`. A Frozen enemy gets multiplier 0.0 → speed 0 → immobile.)

- [ ] **Step 4: Manual verification**

Run the game and hit an enemy with frost_sword (after Task 9–10). On a freeze, the enemy should stop moving briefly. Lure an enemy onto lava: it should catch fire and lose health over time rather than taking one hit.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: enemy status component, status damage path, movement gating"
```

---

## Task 7: Remove direct lava/fire contact damage

**Files:**
- Modify: `src/player/lava_damage_checker.gd`
- Modify: `src/enemies/terrain_damage_receiver.gd`

Lava/fire now apply On Fire via `StatusComponent._poll_terrain`; the old direct-damage poll is redundant and must stop chipping health.

- [ ] **Step 1: Neutralize the player lava damage checker**

The component now handles lava/fire. Strip the damage application from `src/player/lava_damage_checker.gd` by replacing the body of `_physics_process` so it no longer deals damage. Replace the entire `func _physics_process(_delta: float) -> void:` function with:

```gdscript
func _physics_process(_delta: float) -> void:
	# Lava/fire damage is now handled as the On Fire status via StatusComponent.
	# This checker is retained as a no-op for any future non-fire terrain hazards.
	pass
```

- [ ] **Step 2: Read the enemy terrain damage receiver to confirm its shape**

Run: `cat src/enemies/terrain_damage_receiver.gd`
Confirm it polls `hazard_at(... HAZARD_LAVA | HAZARD_FIRE ...)` and applies damage, mirroring the player checker.

- [ ] **Step 3: Neutralize the enemy terrain damage receiver**

Replace its `_physics_process` function body with a no-op identical in spirit:

```gdscript
func _physics_process(_delta: float) -> void:
	# Lava/fire damage is now handled as the On Fire status via StatusComponent.
	pass
```

- [ ] **Step 4: Manual verification**

Run the game. Standing in lava must not instantly subtract health; only the On Fire DoT should. Confirm no errors in the Godot output panel.

- [ ] **Step 5: Commit**

```bash
git add src/player/lava_damage_checker.gd src/enemies/terrain_damage_receiver.gd
git commit -m "refactor: lava/fire deal On Fire status instead of direct damage"
```

---

## Task 8: Crit API on Weapon + modifier hook

**Files:**
- Modify: `src/weapons/weapon.gd`
- Modify: `src/weapons/modifier.gd`
- Test: `tests/unit/test_weapon_crit.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const WeaponScript = preload("res://src/weapons/weapon.gd")
const ModifierScript = preload("res://src/weapons/modifier.gd")

class PlusCritModifier extends Modifier:
	func modify_crit_chance(_weapon, base: float) -> float:
		return base + 0.2

func test_default_crit_fields() -> void:
	var w: Weapon = WeaponScript.new()
	assert_float(w.crit_chance).is_equal_approx(0.0, 0.001)
	assert_float(w.crit_multiplier).is_equal_approx(2.0, 0.001)
	assert_that(w.crit_status).is_equal("")

func test_effective_crit_chance_base() -> void:
	var w: Weapon = WeaponScript.new()
	w.crit_chance = 0.3
	assert_float(w.get_effective_crit_chance()).is_equal_approx(0.3, 0.001)

func test_modifier_adjusts_crit_chance() -> void:
	var w: Weapon = WeaponScript.new()
	w.modifier_slot_count = 1
	w.modifiers.resize(1)
	w.crit_chance = 0.1
	w.add_modifier(0, PlusCritModifier.new())
	assert_float(w.get_effective_crit_chance()).is_equal_approx(0.3, 0.001)

func test_effective_crit_chance_clamped() -> void:
	var w: Weapon = WeaponScript.new()
	w.crit_chance = 2.0
	assert_float(w.get_effective_crit_chance()).is_equal_approx(1.0, 0.001)

func test_roll_crit_zero_and_one() -> void:
	var w: Weapon = WeaponScript.new()
	w.crit_chance = 0.0
	assert_that(w.roll_crit()).is_false()
	w.crit_chance = 1.0
	assert_that(w.roll_crit()).is_true()
```

- [ ] **Step 2: Add the modifier hook**

In `src/weapons/modifier.gd`, add this method after `on_tick`:

```gdscript
func modify_crit_chance(_weapon: Weapon, base: float) -> float:
	return base
```

- [ ] **Step 3: Add crit fields and API to Weapon**

In `src/weapons/weapon.gd`, add these exports/vars after the existing `damage` declaration (line ~8):

```gdscript
var crit_chance: float = 0.0
var crit_multiplier: float = 2.0
var crit_status: String = ""
```

Add this constant near the top of the class (after `extends Resource`):

```gdscript
const CRIT_STATUS_STAIN := 2.0
```

Add these methods at the end of `weapon.gd`:

```gdscript
func get_effective_crit_chance() -> float:
	var c: float = crit_chance
	for modifier in modifiers:
		if modifier != null and modifier.has_method("modify_crit_chance"):
			c = modifier.modify_crit_chance(self, c)
	return clampf(c, 0.0, 1.0)


func roll_crit() -> bool:
	return randf() < get_effective_crit_chance()


func _on_crit(target: Node) -> void:
	if crit_status == "":
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain(crit_status, CRIT_STATUS_STAIN)
```

- [ ] **Step 4: Run the test**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_crit.gd`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/weapons/weapon.gd src/weapons/modifier.gd tests/unit/test_weapon_crit.gd
git commit -m "feat: crit chance/multiplier/status API on Weapon + modifier hook"
```

---

## Task 9: Crit CSV columns + registry overlay

**Files:**
- Modify: `docs/design_docs/weapons.csv`
- Modify: `src/autoload/weapon_registry.gd`
- Test: `tests/unit/test_weapon_crit_csv.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_caliburn_high_crit_no_status() -> void:
	var w = WeaponRegistry.get_weapon_by_id("caliburn")
	assert_that(w).is_not_null()
	assert_float(w.crit_chance).is_equal_approx(0.35, 0.001)
	assert_float(w.crit_multiplier).is_equal_approx(2.0, 0.001)
	assert_that(w.crit_status).is_equal("")

func test_flame_sword_crit_on_fire() -> void:
	var w = WeaponRegistry.get_weapon_by_id("flame_sword")
	assert_float(w.crit_chance).is_equal_approx(0.15, 0.001)
	assert_that(w.crit_status).is_equal("on_fire")

func test_frost_sword_crit_chilly() -> void:
	var w = WeaponRegistry.get_weapon_by_id("frost_sword")
	assert_that(w.crit_status).is_equal("chilly")

func test_heavenly_sword_crit_chilly() -> void:
	var w = WeaponRegistry.get_weapon_by_id("heavenly_sword")
	assert_that(w.crit_status).is_equal("chilly")

func test_non_crit_weapon_defaults() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_float(w.crit_chance).is_equal_approx(0.0, 0.001)
	assert_float(w.crit_multiplier).is_equal_approx(2.0, 0.001)
	assert_that(w.crit_status).is_equal("")
```

- [ ] **Step 2: Add the CSV columns**

In `docs/design_docs/weapons.csv`, append `,crit_chance,crit_multiplier,crit_status` to the end of the header line (line 1). The `CsvTable` parser pads missing trailing columns with `""`, so only the four crit weapons' rows need values; other rows are left unchanged and read as defaults.

Append the following to the end of these specific rows (do not touch any other columns):
- `caliburn` row: append `,0.35,2.0,`
- `flame_sword` row: append `,0.15,2.0,on_fire`
- `frost_sword` row: append `,0.15,2.0,chilly`
- `heavenly_sword` row: append `,0.15,2.0,chilly`

- [ ] **Step 3: Overlay the columns in WeaponRegistry**

In `src/autoload/weapon_registry.gd`, in `_apply_csv_fields` (after the `weapon.damage = ...` line, line ~76), add:

```gdscript
	var cc: String = row.get("crit_chance", "")
	if cc != "":
		weapon.crit_chance = float(cc)
	var cm: String = row.get("crit_multiplier", "")
	if cm != "":
		weapon.crit_multiplier = float(cm)
	weapon.crit_status = row.get("crit_status", "")
```

- [ ] **Step 4: Run the test**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_crit_csv.gd`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the existing CSV test to confirm no regression**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_csv_weapon_data.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add docs/design_docs/weapons.csv src/autoload/weapon_registry.gd tests/unit/test_weapon_crit_csv.gd
git commit -m "feat: crit columns in weapons.csv overlaid by WeaponRegistry"
```

---

## Task 10: Melee crit resolution

**Files:**
- Modify: `src/weapons/melee_weapon.gd`

Apply crit per target inside `_hit_attackables_in_arc`: roll once per enemy hit, multiply damage, and fire `_on_crit`.

- [ ] **Step 1: Update the hit loop**

In `src/weapons/melee_weapon.gd` `_hit_attackables_in_arc`, the current loop computes `var dmg: int = int(damage)` once before the loop and passes `dmg` to `on_hit_impact`. Change it so the crit roll happens per hit. Replace the early line:

```gdscript
	var dmg: int = int(damage)
	if dmg <= 0:
		return
```

with:

```gdscript
	if int(damage) <= 0:
		return
```

Then, in the same function, find the parry/hit block that ends with:

```gdscript
			node.on_hit_impact(node2d.global_position, hit_dir, dmg)
```

Replace that single line with:

```gdscript
			var is_crit: bool = roll_crit()
			var dmg: int = int(damage * crit_multiplier) if is_crit else int(damage)
			node.on_hit_impact(node2d.global_position, hit_dir, dmg)
			if is_crit:
				_on_crit(node)
```

- [ ] **Step 2: Run all weapon unit tests to confirm nothing breaks**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_resources.gd`
Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_weapon_crit.gd`
Expected: PASS.

- [ ] **Step 3: Manual verification**

Run the game, equip flame_sword (via console/spawn), and strike an enemy repeatedly. On a crit the enemy should catch On Fire (orange tint, ticking damage). frost_sword crits should slow/freeze. caliburn crits should deal extra damage with no status.

- [ ] **Step 4: Commit**

```bash
git add src/weapons/melee_weapon.gd
git commit -m "feat: melee weapons roll crits and apply on-crit status"
```

---

## Task 11: Ranged/projectile crit resolution

**Files:**
- Modify: `src/weapons/ranged_weapon.gd`
- Modify: `src/weapons/projectile.gd`

Projectiles carry a snapshot of the firing weapon's crit values so ranged crits work and apply status on hit.

- [ ] **Step 1: Add crit fields to the projectile and apply them on hit**

In `src/weapons/projectile.gd`, add these exports after the existing `is_enemy_projectile` field:

```gdscript
@export var crit_chance: float = 0.0
@export var crit_multiplier: float = 2.0
@export var crit_status: String = ""

const CRIT_STATUS_STAIN := 2.0
```

In `_handle_hit`, the non-enemy branch currently does:

```gdscript
			if target != source_node and target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
				queue_free()
```

Replace those three lines with:

```gdscript
			if target != source_node and target.has_method("on_hit_impact"):
				var is_crit: bool = randf() < clampf(crit_chance, 0.0, 1.0)
				var dmg: int = int(damage * crit_multiplier) if is_crit else int(damage)
				target.on_hit_impact(global_position, direction, dmg)
				if is_crit and crit_status != "":
					var sc = target.get_node_or_null("StatusComponent")
					if sc != null:
						sc.add_stain(crit_status, CRIT_STATUS_STAIN)
				queue_free()
```

- [ ] **Step 2: Pass crit snapshot from the ranged weapon to spawned projectiles**

In `src/weapons/ranged_weapon.gd` `_spawn_projectile`, after the existing `proj.damage = damage` line, add:

```gdscript
	proj.crit_chance = get_effective_crit_chance()
	proj.crit_multiplier = crit_multiplier
	proj.crit_status = crit_status
```

- [ ] **Step 3: Run the ranged weapon test to confirm no regression**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_ranged_weapon.gd`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/weapons/ranged_weapon.gd src/weapons/projectile.gd
git commit -m "feat: projectiles carry crit values and apply on-crit status"
```

---

## Task 12: Status HUD strip

**Files:**
- Modify: `src/ui/hud.gd`

A minimal horizontal strip of color chips near the health bar, one per active status, driven by the player's `StatusComponent.changed` signal. Uses status tint colors (no new art).

- [ ] **Step 1: Add strip fields and build it in `_ready`**

In `src/ui/hud.gd`, add these member vars near the other `var _...` declarations:

```gdscript
var _status: StatusComponent = null
var _status_strip: HBoxContainer = null
```

In `_ready`, inside the `if player:` block (after the `_weapon_manager` wiring), add:

```gdscript
		_status = player.get_node_or_null("StatusComponent")
		_build_status_strip()
		if _status:
			_status.changed.connect(_refresh_status_strip)
			_refresh_status_strip()
```

- [ ] **Step 2: Add the build/refresh methods**

Add to `src/ui/hud.gd`:

```gdscript
func _build_status_strip() -> void:
	_status_strip = HBoxContainer.new()
	_status_strip.add_theme_constant_override("separation", 2)
	# BarFill -> HealthBar -> VBox: add the strip under the health bar.
	var vbox := _health_bar_fill.get_parent().get_parent()
	vbox.add_child(_status_strip)


func _refresh_status_strip() -> void:
	if _status_strip == null:
		return
	for child in _status_strip.get_children():
		child.queue_free()
	if _status == null:
		return
	for id in _status.get_active_ids():
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(10, 10)
		chip.color = StatusRegistry.get_tint(id)
		_status_strip.add_child(chip)
```

- [ ] **Step 3: Manual verification**

Run the game. Walk into lava — a small orange chip should appear near the health bar and disappear shortly after leaving (as On Fire decays). Walk into water — a blue chip appears.

- [ ] **Step 4: Commit**

```bash
git add src/ui/hud.gd
git commit -m "feat: minimal status-effect HUD strip"
```

---

## Task 13: On-entity status tint

**Files:**
- Modify: `src/status/status_component.gd` (add `get_blended_tint`)
- Modify: `src/player/player_controller.gd` (tint `_color_rect`, redirect flash restore)
- Modify: `src/enemies/enemy.gd` (tint `Sprite2D` without fighting the hit-flash)
- Test: `tests/unit/test_status_component.gd` (extend)

Tint the entity sprite by its active statuses, integrating with the existing hit-flash so the flash restores to the status tint rather than plain white.

- [ ] **Step 1: Add the failing test (extend the component suite)**

Add these two tests to `tests/unit/test_status_component.gd`:

```gdscript
func test_blended_tint_white_when_none() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	assert_that(c.get_blended_tint()).is_equal(Color.WHITE)

func test_blended_tint_shifts_with_status() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 5.0)  # active, orange tint
	var tint: Color = c.get_blended_tint()
	assert_that(tint).is_not_equal(Color.WHITE)
	assert_bool(tint.r > tint.b).is_true()  # warm tint
```

- [ ] **Step 2: Add `get_blended_tint` to StatusComponent**

Add to `src/status/status_component.gd`:

```gdscript
func get_blended_tint() -> Color:
	var ids: Array = get_active_ids()
	if ids.is_empty():
		return Color.WHITE
	var c: Color = Color.WHITE
	for id in ids:
		c = c.lerp(StatusRegistry.get_tint(id), 0.5)
	return c
```

- [ ] **Step 3: Run the component test**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_status_component.gd`
Expected: PASS (9 tests).

- [ ] **Step 4: Drive the player tint**

In `src/player/player_controller.gd`, add a member var near the other `var _...` declarations:

```gdscript
var _status_tint: Color = Color.WHITE
```

In `_physics_process`, just before the final `move_and_slide()`, add:

```gdscript
	var tint_status := get_node_or_null("StatusComponent")
	if tint_status and _color_rect:
		_status_tint = tint_status.get_blended_tint()
		if not (_flash_tween and _flash_tween.is_valid()):
			_color_rect.modulate = _status_tint
```

Then in `_play_hit_flash`, change the restore target from white to the status tint. Replace:

```gdscript
	_flash_tween.tween_property(_color_rect, "modulate", Color.WHITE, 0.12)
```

with:

```gdscript
	_flash_tween.tween_property(_color_rect, "modulate", _status_tint, 0.12)
```

- [ ] **Step 5: Drive the enemy tint**

In `src/enemies/enemy.gd` `_physics_process` (line ~177), add at the top of the function (after the `if _state == State.DEATH: return` guard):

```gdscript
	var tint_status := get_node_or_null("StatusComponent")
	if tint_status:
		_base_modulate = tint_status.get_blended_tint()
		if not (_flash_tween and _flash_tween.is_valid()):
			var sprite := get_node_or_null("Sprite2D")
			if sprite:
				sprite.modulate = _base_modulate
```

(The enemy hit-flash already restores to `_base_modulate`, so a flash now fades back to the status tint automatically.)

- [ ] **Step 6: Manual verification**

Run the game. An On Fire entity glows orange; a Frozen entity turns icy blue; the tint fades as the status decays. Hitting a burning enemy flashes white then settles back to orange (not plain white).

- [ ] **Step 7: Commit**

```bash
git add src/status/status_component.gd src/player/player_controller.gd src/enemies/enemy.gd tests/unit/test_status_component.gd
git commit -m "feat: tint entities by active status, integrate with hit-flash"
```

---

## Task 14: Full suite + integration sanity

**Files:** none (verification only)

- [ ] **Step 1: Run the entire unit suite**

Run: `GODOT_BIN=godot ./addons/gdUnit4/runtest.sh -a tests/unit`
Expected: all tests PASS, including the new status and crit suites and the existing weapon/CSV suites.

- [ ] **Step 2: Manual integration checklist**

Run the game and confirm:
- Standing in lava applies On Fire (steady DoT), not a single damage hit; burning persists briefly after leaving.
- Standing in water applies Wet and quickly extinguishes On Fire.
- flame_sword crit ignites an enemy; frost_sword crit slows then (with repeated crits) freezes; caliburn crit deals extra damage with no status.
- A frozen enemy stops moving; a chilly enemy moves slower.
- HUD chips appear/disappear matching active statuses.
- No errors in the Godot output panel.

- [ ] **Step 3: Final commit (if any tuning changes were made)**

```bash
git add -A
git commit -m "test: status effect system integration pass"
```

---

## Self-review notes (for the implementer)

- Reaction tuning constants (Task 3) and the `TERRAIN_STAIN_RATE`, burn dps, and `CRIT_STATUS_STAIN` values are deliberate starting points — tune during the Task 13 playtest.
- `StatusComponent` is attached in code (not in scenes) so all five enemy scenes and the player scene work without `.tscn` edits.
- The reaction rules read/write stains only through `get_stain`/`add_stain`/`reduce_stain`, so they stay unit-testable without the scene tree.
