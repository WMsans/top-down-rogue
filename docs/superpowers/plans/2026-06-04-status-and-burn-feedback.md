# Status Clarity & Burn Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make active statuses legible (icons above each entity's head, alpha = intensity) and make burning *feel* dangerous (flame particles, per-tick orange throb, player-only ember vignette).

**Architecture:** A new shared `StatusVisuals` `Node2D` is attached to the player and every enemy, driven by that entity's existing `StatusComponent`; it renders world-space status icons and a flame-particle emitter. `StatusComponent` gains a `burn_tick` signal that each entity folds into its existing per-frame `modulate` write as a decaying orange throb. `DamageVignette` gains an independent ember channel the player drives while on fire. The redundant HUD chip strip is removed.

**Tech Stack:** Godot 4.6 (GDScript), gdUnit4 for unit tests.

**Conventions:**
- Run a single test file with: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/<file>.gd`
- Status icon PNGs already exist in `textures/ui/status/` (60×60). Godot generates their `.import` files on the next editor/headless launch.

---

## File Structure

**New**
- `src/status/status_visuals.gd` — `StatusVisuals` node: above-head icons + flame particles. Shared by player & enemies.

**Modified**
- `src/status/status_def.gd` — add `icon_path` field/param.
- `src/autoload/status_registry.gd` — icon paths in defs, `get_icon()`, `get_icon_alpha()`, constants.
- `src/status/status_component.gd` — add `signal burn_tick`, emit on whole-damage tick.
- `src/player/player_controller.gd` — spawn `StatusVisuals`; burn throb; drive ember vignette.
- `src/enemies/enemy.gd` — spawn `StatusVisuals`; burn throb.
- `src/core/juice/damage_vignette.gd` — ember channel + `set_burn_intensity()` + `get_ember_intensity()`.
- `src/ui/hud.gd` — remove the status chip strip.

**Tests**
- `tests/unit/test_status_registry.gd` — icon + alpha-remap tests (append).
- `tests/unit/test_status_component.gd` — `burn_tick` test (append).
- `tests/unit/test_status_visuals.gd` — new, reconciliation + alpha tests.
- `tests/unit/test_damage_vignette.gd` — new, ember intensity test.

---

## Task 1: Status icon data + alpha-remap on the registry

**Files:**
- Modify: `src/status/status_def.gd`
- Modify: `src/autoload/status_registry.gd`
- Test: `tests/unit/test_status_registry.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_status_registry.gd`:

```gdscript
func test_get_icon_alpha_below_threshold_is_zero() -> void:
	assert_float(StatusRegistry.get_icon_alpha("on_fire", 0.5)).is_equal_approx(0.0, 0.001)

func test_get_icon_alpha_at_threshold_is_min() -> void:
	assert_float(StatusRegistry.get_icon_alpha("on_fire", 1.0)).is_equal_approx(StatusRegistry.ICON_MIN_ALPHA, 0.001)

func test_get_icon_alpha_saturates_at_one() -> void:
	var stain := 1.0 + StatusRegistry.ICON_ALPHA_RAMP
	assert_float(StatusRegistry.get_icon_alpha("on_fire", stain)).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_icon_alpha("on_fire", stain + 10.0)).is_equal_approx(1.0, 0.001)

func test_get_icon_alpha_midpoint_between_min_and_one() -> void:
	var mid := StatusRegistry.get_icon_alpha("on_fire", 1.0 + StatusRegistry.ICON_ALPHA_RAMP * 0.5)
	assert_float(mid).is_greater(StatusRegistry.ICON_MIN_ALPHA)
	assert_float(mid).is_less(1.0)

func test_get_icon_uses_per_status_threshold() -> void:
	# frozen threshold is 3.0; at 3.0 it should read min alpha, not saturated.
	assert_float(StatusRegistry.get_icon_alpha("frozen", 3.0)).is_equal_approx(StatusRegistry.ICON_MIN_ALPHA, 0.001)
	assert_float(StatusRegistry.get_icon_alpha("frozen", 2.0)).is_equal_approx(0.0, 0.001)

func test_get_icon_returns_texture_for_each_status() -> void:
	for id in ["on_fire", "wet", "oiled", "chilly", "frozen", "bloody"]:
		assert_object(StatusRegistry.get_icon(id)).is_not_null()

func test_get_icon_unknown_is_null() -> void:
	assert_object(StatusRegistry.get_icon("nope")).is_null()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_registry.gd`
Expected: FAIL — `ICON_MIN_ALPHA` / `get_icon_alpha` / `get_icon` do not exist.

- [ ] **Step 3: Add `icon_path` to `StatusDef`**

In `src/status/status_def.gd`, add the field after `slow_multiplier` (line 14):

```gdscript
	var slow_multiplier: float  # movement speed multiplier while active (1.0 = none)
	var icon_path: String       # res:// path to the above-head status icon (or "")
```

Add the constructor parameter (after `p_slow_multiplier`) and assignment:

```gdscript
	p_slow_multiplier: float = 1.0,
	p_icon_path: String = "",
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
	icon_path = p_icon_path
```

- [ ] **Step 4: Pass icon paths + add accessors in `StatusRegistry`**

In `src/autoload/status_registry.gd`, add constants near the top (after `TERRAIN_STAIN_RATE`, line 9):

```gdscript
# Above-head icon intensity mapping: alpha ramps from ICON_MIN_ALPHA (at the
# active threshold) to 1.0 once stain reaches threshold + ICON_ALPHA_RAMP.
const ICON_MIN_ALPHA := 0.45
const ICON_ALPHA_RAMP := 4.0
```

Add an icon cache field beside `_defs` (line 11):

```gdscript
var _defs: Dictionary = {}  # id -> StatusDef
var _icon_cache: Dictionary = {}  # id -> Texture2D (lazy)
```

Replace `_register_defs()` (lines 18-36) with the icon-carrying version:

```gdscript
func _register_defs() -> void:
	_add(StatusDefScript.new(
		"on_fire", "On Fire", Color(1.0, 0.45, 0.1, 1.0),
		1.0, 1.0, StatusDef.Category.HARMFUL, 4.0, false, 1.0,
		"res://textures/ui/status/Effect_on_fire.png"))
	_add(StatusDefScript.new(
		"wet", "Wet", Color(0.35, 0.55, 0.95, 1.0),
		0.5, 1.0, StatusDef.Category.NEUTRAL, 0.0, false, 1.0,
		"res://textures/ui/status/Effect_wet.png"))
	_add(StatusDefScript.new(
		"oiled", "Oiled", Color(0.25, 0.18, 0.1, 1.0),
		0.3, 1.0, StatusDef.Category.NEUTRAL, 0.0, false, 1.0,
		"res://textures/ui/status/Effect_oiled.png"))
	_add(StatusDefScript.new(
		"chilly", "Chilly", Color(0.6, 0.8, 0.95, 1.0),
		0.8, 1.0, StatusDef.Category.HARMFUL, 0.0, false, 0.6,
		"res://textures/ui/status/Effect_ingestion_freezing.png"))
	_add(StatusDefScript.new(
		"frozen", "Frozen", Color(0.7, 0.9, 1.0, 1.0),
		0.4, 3.0, StatusDef.Category.HARMFUL, 0.0, true, 0.0,
		"res://textures/ui/status/Effect_frozen.png"))
	_add(StatusDefScript.new(
		"bloody", "Bloody", Color(0.75, 0.08, 0.08, 1.0),
		0.4, 1.0, StatusDef.Category.NEUTRAL, 0.0, false, 1.0,
		"res://textures/ui/status/Effect_bloody.png"))
```

Add the accessors (anywhere among the other getters, e.g. after `get_tint`, line 63):

```gdscript
func get_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var d: StatusDef = _defs.get(id, null)
	var tex: Texture2D = null
	if d != null and d.icon_path != "":
		tex = load(d.icon_path) as Texture2D
	_icon_cache[id] = tex
	return tex


func get_icon_alpha(id: String, stain: float) -> float:
	var threshold := get_threshold(id)
	if stain < threshold:
		return 0.0
	var t: float = clampf((stain - threshold) / ICON_ALPHA_RAMP, 0.0, 1.0)
	return lerpf(ICON_MIN_ALPHA, 1.0, t)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_registry.gd`
Expected: PASS (all existing + new tests). If `get_icon` returns null, confirm the PNGs imported — re-run once (headless launch triggers import) and try again.

- [ ] **Step 6: Commit**

```bash
git add src/status/status_def.gd src/autoload/status_registry.gd tests/unit/test_status_registry.gd
git commit -m "feat: status icon paths and intensity->alpha remap on registry"
```

---

## Task 2: `burn_tick` signal on `StatusComponent`

**Files:**
- Modify: `src/status/status_component.gd:9` (signals) and `:121-128` (`_apply_effects`)
- Test: `tests/unit/test_status_component.gd`

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_status_component.gd` (reuses the existing `FakeOwner` + `_make_comp` helpers):

```gdscript
func test_burn_tick_emitted_on_whole_damage() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	var flag := [false]
	c.burn_tick.connect(func() -> void: flag[0] = true)
	c.add_stain("on_fire", 5.0)  # burn_dps 4
	c.tick(1.0)
	assert_bool(flag[0]).is_true()

func test_burn_tick_not_emitted_without_fire() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	var flag := [false]
	c.burn_tick.connect(func() -> void: flag[0] = true)
	c.add_stain("wet", 5.0)
	c.tick(1.0)
	assert_bool(flag[0]).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_component.gd`
Expected: FAIL — `burn_tick` signal does not exist.

- [ ] **Step 3: Add the signal and emit it**

In `src/status/status_component.gd`, add beside the existing `signal changed` (line 9):

```gdscript
signal changed
signal burn_tick  # emitted each time a whole point of burn damage lands
```

In `_apply_effects` (lines 121-128), emit before applying damage:

```gdscript
func _apply_effects(delta: float) -> void:
	if has_status("on_fire"):
		_burn_accum += StatusRegistry.get_burn_dps("on_fire") * delta
		var whole: int = int(_burn_accum)
		if whole >= 1:
			_burn_accum -= float(whole)
			burn_tick.emit()
			if _owner_node != null and _owner_node.has_method("apply_status_damage"):
				_owner_node.apply_status_damage(whole)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_component.gd`
Expected: PASS (existing `test_burn_calls_owner_damage` still passes too).

- [ ] **Step 5: Commit**

```bash
git add src/status/status_component.gd tests/unit/test_status_component.gd
git commit -m "feat: emit burn_tick signal on each whole burn-damage tick"
```

---

## Task 3: `StatusVisuals` node (icons + flame particles)

**Files:**
- Create: `src/status/status_visuals.gd`
- Test: `tests/unit/test_status_visuals.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_status_visuals.gd`:

```gdscript
extends GdUnitTestSuite

const StatusVisualsScript = preload("res://src/status/status_visuals.gd")
const StatusComponentScript = preload("res://src/status/status_component.gd")

func _sprite_children(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is Sprite2D:
			n += 1
	return n

func test_one_icon_per_active_status() -> void:
	var status: StatusComponent = auto_free(StatusComponentScript.new())
	status.add_stain("on_fire", 2.0)
	status.add_stain("wet", 2.0)
	status.add_stain("oiled", 0.2)  # below threshold -> no icon
	var sv: StatusVisuals = auto_free(StatusVisualsScript.new())
	sv.setup(status, Vector2.ZERO)
	assert_int(_sprite_children(sv)).is_equal(2)

func test_icon_removed_when_status_lapses() -> void:
	var status: StatusComponent = auto_free(StatusComponentScript.new())
	status.add_stain("on_fire", 2.0)
	var sv: StatusVisuals = auto_free(StatusVisualsScript.new())
	sv.setup(status, Vector2.ZERO)
	assert_int(_sprite_children(sv)).is_equal(1)
	status.clear("on_fire")  # emits changed -> refresh
	assert_int(_sprite_children(sv)).is_equal(0)

func test_alpha_is_min_at_threshold() -> void:
	var status: StatusComponent = auto_free(StatusComponentScript.new())
	status.add_stain("on_fire", 1.0)  # exactly threshold
	var sv: StatusVisuals = auto_free(StatusVisualsScript.new())
	sv.setup(status, Vector2.ZERO)
	var icon: Sprite2D = null
	for c in sv.get_children():
		if c is Sprite2D:
			icon = c
	assert_object(icon).is_not_null()
	assert_float(icon.modulate.a).is_equal_approx(StatusRegistry.ICON_MIN_ALPHA, 0.01)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_visuals.gd`
Expected: FAIL — `status_visuals.gd` does not exist (load error).

- [ ] **Step 3: Create `StatusVisuals`**

Create `src/status/status_visuals.gd`:

```gdscript
class_name StatusVisuals
extends Node2D

# World-space status feedback attached above an entity (player or enemy):
# one icon per active status (alpha = intensity) plus a flame-particle emitter
# while On Fire. Driven by the owner's existing StatusComponent. The owner
# creates this node, adds it as a child, and calls setup().

const ICON_SOURCE_PX := 60.0   # source PNG size
const ICON_DISPLAY_PX := 14.0  # on-screen size
const ICON_SPACING := 16.0     # horizontal gap between icons (local px)
const ICON_Z := 80             # render above terrain/entities

var _status: StatusComponent = null
var _head_offset: Vector2 = Vector2(0, -14)
var _icons: Dictionary = {}            # id -> Sprite2D
var _particles: CPUParticles2D = null


func setup(status: StatusComponent, head_offset: Vector2) -> void:
	_status = status
	_head_offset = head_offset
	if _status != null and not _status.changed.is_connected(refresh):
		_status.changed.connect(refresh)
	refresh()


func _ready() -> void:
	z_index = ICON_Z
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func refresh() -> void:
	if _status == null:
		return
	var active: Array = _status.get_active_ids()
	# Remove icons whose status lapsed.
	for id in _icons.keys():
		if not active.has(id):
			_icons[id].queue_free()
			_icons.erase(id)
	# Add icons for newly active statuses.
	for id in active:
		if not _icons.has(id):
			_icons[id] = _make_icon(id)
	# Layout (centered row) + alpha = intensity.
	var ordered: Array = _icons.keys()
	for i in ordered.size():
		var id: String = ordered[i]
		var spr: Sprite2D = _icons[id]
		var x := (float(i) - (ordered.size() - 1) * 0.5) * ICON_SPACING
		spr.position = _head_offset + Vector2(x, 0.0)
		var a := StatusRegistry.get_icon_alpha(id, _status.get_stain(id))
		spr.modulate = Color(1.0, 1.0, 1.0, a)
	# Flame particles while burning.
	if _particles != null:
		_particles.emitting = _status.has_status("on_fire")


func _make_icon(id: String) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = StatusRegistry.get_icon(id)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var s := ICON_DISPLAY_PX / ICON_SOURCE_PX
	spr.scale = Vector2(s, s)
	add_child(spr)
	return spr


func _build_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.5
	p.position = _head_offset * 0.4
	p.direction = Vector2(0.0, -1.0)
	p.spread = 25.0
	p.gravity = Vector2(0.0, -40.0)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(1.0, 0.55, 0.15, 0.9)
	p.z_as_relative = false
	p.z_index = ICON_Z - 1
	return p
```

Note: `setup()` is safe whether or not `_ready` has run — `refresh()` guards on `_particles != null`, and icon sprites are created regardless. Tests instantiate the node outside the tree (so `_ready`/particles are skipped) and still get icon reconciliation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_visuals.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/status/status_visuals.gd tests/unit/test_status_visuals.gd
git commit -m "feat: StatusVisuals node - above-head icons and flame particles"
```

---

## Task 4: Wire `StatusVisuals` + burn throb into the player

**Files:**
- Modify: `src/player/player_controller.gd:25` (constants), `:34` (fields), `:67-69` (`_ready`), `:112-116` (tint write), and add `_on_burn_tick`.

This task is integration/visual — verified by launching the game (no unit test).

- [ ] **Step 1: Add constants and field**

In `src/player/player_controller.gd`, after `HIT_FLASH_COLOR` (line 25):

```gdscript
const HIT_FLASH_COLOR := Color(2.5, 0.3, 0.1)
const BURN_FLASH_COLOR := Color(1.0, 0.55, 0.15)
const BURN_FLASH_MAX := 0.7
const BURN_FLASH_DECAY := 6.0
```

After `_status_tint` (line 34):

```gdscript
var _status_tint: Color = Color.WHITE
var _burn_flash: float = 0.0
```

- [ ] **Step 2: Spawn `StatusVisuals` and connect the throb in `_ready`**

In `_ready`, replace the StatusComponent block (lines 67-69):

```gdscript
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	add_child(status)

	var visuals := StatusVisuals.new()
	visuals.name = "StatusVisuals"
	add_child(visuals)
	visuals.setup(status, Vector2(BODY_WIDTH / 2.0, -10.0))
	status.burn_tick.connect(_on_burn_tick)
```

- [ ] **Step 3: Fold the throb into the per-frame tint write + drive the ember vignette**

Replace the tint block (lines 112-116) with:

```gdscript
	var tint_status := get_node_or_null("StatusComponent")
	if tint_status and _color_rect:
		_status_tint = tint_status.get_blended_tint()
		if _burn_flash > 0.0:
			_burn_flash = maxf(0.0, _burn_flash - delta * BURN_FLASH_DECAY)
		if not (_flash_tween and _flash_tween.is_valid()):
			var m := _status_tint
			if _burn_flash > 0.0:
				m = m.lerp(BURN_FLASH_COLOR, _burn_flash * BURN_FLASH_MAX)
			_color_rect.modulate = m
		if HitReaction.vignette:
			HitReaction.vignette.set_burn_intensity(
				StatusRegistry.get_icon_alpha("on_fire", tint_status.get_stain("on_fire")))
```

(`set_burn_intensity` is added in Task 5; if running Task 4 before Task 5, this line will error at runtime — implement Task 5 in the same session, or temporarily comment the `HitReaction.vignette` block until Task 5 lands. Recommended: do Tasks 4 and 5 back-to-back before launching.)

- [ ] **Step 4: Add the burn-tick handler**

Add near `_play_hit_flash` (around line 305):

```gdscript
func _on_burn_tick() -> void:
	_burn_flash = 1.0
```

- [ ] **Step 5: Verify it parses**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_component.gd`
Expected: PASS — confirms the project still compiles (no parse errors introduced). Visual verification happens after Task 5.

- [ ] **Step 6: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: player above-head status icons and per-tick burn throb"
```

---

## Task 5: Ember vignette channel + player drive

**Files:**
- Modify: `src/core/juice/damage_vignette.gd`
- Test: `tests/unit/test_damage_vignette.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_damage_vignette.gd`:

```gdscript
extends GdUnitTestSuite

const DamageVignetteScript = preload("res://src/core/juice/damage_vignette.gd")

func test_set_burn_intensity_raises_ember() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	await get_tree().process_frame
	assert_float(v.get_ember_intensity()).is_equal_approx(0.0, 0.001)
	v.set_burn_intensity(1.0)
	for i in 30:
		await get_tree().process_frame
	assert_float(v.get_ember_intensity()).is_greater(0.1)

func test_set_burn_intensity_zero_decays_ember() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	v.set_burn_intensity(1.0)
	for i in 30:
		await get_tree().process_frame
	v.set_burn_intensity(0.0)
	for i in 60:
		await get_tree().process_frame
	assert_float(v.get_ember_intensity()).is_less(0.05)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_damage_vignette.gd`
Expected: FAIL — `set_burn_intensity` / `get_ember_intensity` do not exist.

- [ ] **Step 3: Add the ember channel**

In `src/core/juice/damage_vignette.gd`, add constants near the existing ones (after `LOW_HEALTH_TRANSITION`):

```gdscript
const EMBER_COLOR := Color(1.0, 0.4, 0.05, 1.0)
const EMBER_MAX_STRENGTH := 0.5
const EMBER_SMOOTH := 6.0
```

Add fields beside the existing vars:

```gdscript
var _ember_material: ShaderMaterial
var _ember_target: float = 0.0
```

At the end of `_ready()`, after the existing `call_deferred("_connect_to_player")` line, build the second rect/material:

```gdscript
	var ember_rect := ColorRect.new()
	ember_rect.anchor_right = 1.0
	ember_rect.anchor_bottom = 1.0
	ember_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ember_rect)

	_ember_material = ShaderMaterial.new()
	_ember_material.shader = preload("res://shaders/ui/damage_vignette.gdshader")
	_ember_material.set_shader_parameter("intensity", 0.0)
	_ember_material.set_shader_parameter("vignette_color", EMBER_COLOR)
	ember_rect.material = _ember_material
```

Add the public API (anywhere at file scope):

```gdscript
func set_burn_intensity(t: float) -> void:
	_ember_target = clampf(t, 0.0, 1.0) * EMBER_MAX_STRENGTH


func get_ember_intensity() -> float:
	return _ember_material.get_shader_parameter("intensity") if _ember_material else 0.0
```

Replace `_process` (the existing low-health-only version) so the ember channel smooths *before* the low-health early returns:

```gdscript
func _process(_delta: float) -> void:
	if _ember_material:
		var cur: float = _ember_material.get_shader_parameter("intensity")
		var step := clampf(_delta * EMBER_SMOOTH, 0.0, 1.0)
		_ember_material.set_shader_parameter("intensity", lerpf(cur, _ember_target, step))

	if not _is_low_health:
		return
	if _pulse_tween and _pulse_tween.is_valid():
		return
	var oscillation := _current_baseline * (1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.001 * LOW_HEALTH_PULSE_SPEED * TAU))
	_shader_material.set_shader_parameter("intensity", oscillation)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_damage_vignette.gd`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/juice/damage_vignette.gd tests/unit/test_damage_vignette.gd
git commit -m "feat: ember burn channel on DamageVignette driven by player fire"
```

---

## Task 6: Wire `StatusVisuals` + burn throb into enemies

**Files:**
- Modify: `src/enemies/enemy.gd:25` (constants), `:39` (fields), `:110-112` (`_ready`), `:184-190` (tint write), and add `_on_burn_tick`.

Integration/visual — verified by launching the game.

- [ ] **Step 1: Add constants and field**

In `src/enemies/enemy.gd`, after `FLASH_DECAY` (line 26):

```gdscript
const FLASH_DECAY: float = 0.12
const BURN_FLASH_COLOR := Color(1.0, 0.55, 0.15)
const BURN_FLASH_MAX := 0.7
const BURN_FLASH_DECAY := 6.0
```

After `_base_modulate` (line 39):

```gdscript
var _base_modulate: Color = Color.WHITE
var _burn_flash: float = 0.0
```

- [ ] **Step 2: Spawn `StatusVisuals` and connect the throb in `_ready`**

Replace the StatusComponent block (lines 110-112):

```gdscript
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	add_child(status)

	var visuals := StatusVisuals.new()
	visuals.name = "StatusVisuals"
	add_child(visuals)
	visuals.setup(status, Vector2(0.0, -14.0))
	status.burn_tick.connect(_on_burn_tick)
```

- [ ] **Step 3: Fold the throb into the enemy tint write**

Replace the tint block (lines 184-190) with:

```gdscript
	var tint_status := get_node_or_null("StatusComponent")
	if tint_status:
		_base_modulate = tint_status.get_blended_tint()
		if _burn_flash > 0.0:
			_burn_flash = maxf(0.0, _burn_flash - _delta * BURN_FLASH_DECAY)
		if not (_flash_tween and _flash_tween.is_valid()):
			var sprite := get_node_or_null("Sprite2D")
			if sprite:
				var m := _base_modulate
				if _burn_flash > 0.0:
					m = m.lerp(BURN_FLASH_COLOR, _burn_flash * BURN_FLASH_MAX)
				sprite.modulate = m
```

- [ ] **Step 4: Add the burn-tick handler**

Add near the other flash helpers (around line 486):

```gdscript
func _on_burn_tick() -> void:
	_burn_flash = 1.0
```

- [ ] **Step 5: Verify it parses**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_component.gd`
Expected: PASS — confirms the project still compiles.

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: enemy above-head status icons and per-tick burn throb"
```

---

## Task 7: Remove the HUD status chip strip

**Files:**
- Modify: `src/ui/hud.gd:22-23` (fields), `:45-49` (`_ready` wiring), `:153-172` (the two strip methods).

- [ ] **Step 1: Remove the strip fields**

In `src/ui/hud.gd`, delete these two field lines (22-23):

```gdscript
var _status: StatusComponent = null
var _status_strip: HBoxContainer = null
```

- [ ] **Step 2: Remove the `_ready` wiring**

In `_ready`, delete the status block (lines 45-49) so the weapon-manager block flows straight into `_outline_panel`:

```gdscript
		_weapon_manager = player.get_node_or_null("WeaponManager")
		if _weapon_manager:
			_weapon_manager.weapon_activated.connect(_on_weapon_activated)
			_update_weapon_display(_inventory.active_weapon_slot if _inventory else 0)
	_outline_panel = _create_outline_panel()
```

- [ ] **Step 3: Remove the strip methods**

Delete `_build_status_strip()` and `_refresh_status_strip()` in their entirety (lines 153-172).

- [ ] **Step 4: Verify no dangling references**

Run: `grep -n "_status_strip\|_refresh_status_strip\|_build_status_strip\|_status\b" src/ui/hud.gd`
Expected: no output (all references removed).

- [ ] **Step 5: Verify it parses**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit/test_status_registry.gd`
Expected: PASS — confirms the project compiles with the HUD change.

- [ ] **Step 6: Commit**

```bash
git add src/ui/hud.gd
git commit -m "refactor: remove redundant HUD status chip strip"
```

---

## Task 8: Full-suite run + in-game verification

- [ ] **Step 1: Run the whole unit suite**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests/unit`
Expected: PASS — all suites green, including the new icon/burn/visuals/vignette tests.

- [ ] **Step 2: Launch the game and verify visually**

Launch the project (editor play, or the `run` skill). Confirm:
- Standing in lava/fire: an `on_fire` icon appears above the player, brightening (alpha) as the stain builds and fading as it decays; it vanishes when the status lapses.
- While burning, the player emits rising flame particles, the sprite throbs orange in time with the damage ticks, and an ember vignette glows at the screen edges and fades out when the fire ends.
- A burning/frozen/wet enemy shows the matching icon(s) above its head and (when on fire) flame particles + orange throb. No ember vignette from enemies.
- Standing in water → `wet` icon; oil → `oiled`; etc. The old colored chip strip under the health bar is gone.

- [ ] **Step 3: Final commit (if any tuning tweaks were made)**

```bash
git add -A
git commit -m "chore: tune status icon offsets and burn feedback constants"
```

---

## Self-Review Notes

- **Spec coverage:** icons/alpha (Tasks 1, 3), player+enemy icon scope (Tasks 4, 6), burn_tick (Task 2), flame particles (Task 3), burn throb (Tasks 4, 6), ember vignette player-only (Tasks 4, 5), HUD strip removal (Task 7), unit + visual tests (all tasks + Task 8). All spec sections map to a task.
- **Type/name consistency:** `get_icon`, `get_icon_alpha`, `ICON_MIN_ALPHA`, `ICON_ALPHA_RAMP`, `burn_tick`, `StatusVisuals.setup(status, head_offset)`, `set_burn_intensity`, `get_ember_intensity`, `BURN_FLASH_COLOR/MAX/DECAY` are used identically across tasks.
- **Cross-task dependency:** Task 4 step 3 references `set_burn_intensity` from Task 5 — flagged inline; do Tasks 4+5 in the same session before launching.
- **Tuning values** (`head_offset`, icon size/spacing, `BURN_FLASH_*`, `EMBER_*`) are visual and adjusted by eye in Task 8.
