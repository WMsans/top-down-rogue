# Weapon Modifier System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a weapon modifier system with slot-based modifiers that alter weapon behavior, plus a Lava Emitter modifier that spawns lava on weapon use.

**Architecture:** Event-hook pattern — `Modifier` base class (RefCounted) with `on_equip`, `on_use`, `on_tick` lifecycle hooks. `Weapon.use()` becomes a template method that iterates modifiers before calling `_use_impl()`. Existing weapons refactor their `use()`/`tick()` into `_use_impl()`/`_tick_impl()`. Cooldown handling moves to base class.

**Tech Stack:** GDScript 4, Godot 4.6, existing terrain modifier system (TerrainModifier.place_lava)

---

## File Structure

### New Files
- `src/weapons/modifier.gd` — Modifier base class (RefCounted)
- `src/weapons/lava_emitter_modifier.gd` — Lava Emitter concrete modifier
- `textures/Modifiers/lava_emitter.png` — Placeholder icon

### Modified Files
- `src/weapons/weapon.gd` — Add modifier_slot_count, modifiers array, _cooldown_timer, template method use/tick, add_modifier/get_modifier_at, get_stats
- `src/weapons/test_weapon.gd` — Rename use→_use_impl, tick→_tick_impl, remove _cooldown_timer and is_ready, set modifier_slot_count, resize modifiers
- `src/weapons/melee_weapon.gd` — Rename use→_use_impl, tick→_tick_impl, remove _cooldown_timer and is_ready, set modifier_slot_count, resize modifiers
- `src/weapons/weapon_manager.gd` — Add LavaEmitterModifier preload, add_modifier_to_weapon method, wire test modifier in _ready, use base class is_ready in _input
- `src/ui/weapon_popup.gd` — Add modifier slot icons with hover tooltips to weapon cards
- `src/ui/weapon_button.gd` — Add modifier icon row to tooltip

---

### Task 1: Create Modifier Base Class

**Files:**
- Create: `src/weapons/modifier.gd`

- [ ] **Step 1: Write the Modifier base class**

Create `src/weapons/modifier.gd`:

```gdscript
class_name Modifier
extends RefCounted

var name: String = "Modifier"
var description: String = ""
var icon_texture: Texture2D = null
var suppresses_base_use: bool = false


func on_equip(_weapon: Weapon) -> void:
	pass


func on_use(_weapon: Weapon, _user: Node) -> void:
	pass


func on_tick(_weapon: Weapon, _delta: float) -> void:
	pass


func get_description() -> String:
	return description
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/modifier.gd
git commit -m "feat: add Modifier base class with lifecycle hooks"
```

---

### Task 2: Update Weapon Base Class with Modifier Support

**Files:**
- Modify: `src/weapons/weapon.gd`

- [ ] **Step 1: Update weapon.gd with modifier system and template method pattern**

Replace the entire content of `src/weapons/weapon.gd` with:

```gdscript
class_name Weapon
extends RefCounted

var name: String = "Weapon"
var cooldown: float = 0.5
var damage: float = 0.0
var icon_texture: Texture2D = null
var visual: Node2D = null
var _sprite: Sprite2D = null
var modifier_slot_count: int = 3
var modifiers: Array = []
var _cooldown_timer: float = 0.0


func use(user: Node) -> void:
	if not is_ready():
		return
	for modifier in modifiers:
		if modifier != null:
			modifier.on_use(self, user)
	var suppress: bool = false
	for modifier in modifiers:
		if modifier != null and modifier.suppresses_base_use:
			suppress = true
			break
	if not suppress:
		_use_impl(user)
	_cooldown_timer = cooldown


func _use_impl(_user: Node) -> void:
	pass


func tick(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	for modifier in modifiers:
		if modifier != null:
			modifier.on_tick(self, delta)
	_tick_impl(delta)


func _tick_impl(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return _cooldown_timer <= 0.0


func has_visual() -> bool:
	return false


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	visual = container
	_sprite = sprite


func update_visual(_delta: float, _user: Node) -> void:
	pass


func add_modifier(slot_index: int, modifier: Modifier) -> void:
	if slot_index < 0 or slot_index >= modifier_slot_count:
		return
	modifiers[slot_index] = modifier
	modifier.on_equip(self)


func get_modifier_at(slot_index: int) -> Modifier:
	if slot_index < 0 or slot_index >= modifiers.size():
		return null
	return modifiers[slot_index]


func get_base_stats() -> Dictionary:
	return {
		"name": name,
		"cooldown": cooldown,
		"damage": damage
	}


func get_stats() -> Dictionary:
	return get_base_stats()
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/weapon.gd
git commit -m "feat: add modifier slots, template method use/tick, and cooldown to Weapon base"
```

---

### Task 3: Refactor TestWeapon

**Files:**
- Modify: `src/weapons/test_weapon.gd`

- [ ] **Step 1: Refactor TestWeapon to use _use_impl and _tick_impl**

Replace the entire content of `src/weapons/test_weapon.gd` with:

```gdscript
class_name TestWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/Weapons/candy_02c.png")
const GAS_RADIUS: float = 6.0
const GAS_DENSITY: int = 200

const PIVOT_DISTANCE: float = 6.0
const BOUNCE_UP_DURATION: float = 0.1
const BOUNCE_DOWN_DURATION: float = 0.15
const BOUNCE_SCALE_UP: Vector2 = Vector2(1.4, 1.4)
const BOUNCE_SETTLE: Vector2 = Vector2(1.08, 1.08)
const LERP_SNAP: float = 16.0
const LERP_EASE: float = 6.0
const IDLE_ROTATION_SPEED: float = 10.0

enum Phase { NONE, UP, DOWN }

var _is_bouncing: bool = false
var _phase: int = Phase.NONE
var _phase_time: float = 0.0
var _visual_angle: float = NAN
var _bounce_scale: Vector2 = Vector2.ONE
var _facing_angle: float = 0.0


func _init() -> void:
	name = "Test Weapon"
	cooldown = 0.5
	damage = 1.0
	icon_texture = WEAPON_TEXTURE
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)


func has_visual() -> bool:
	return true


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	_sprite.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(0, -tex_size.y / 2.0)


func _use_impl(user: Node) -> void:
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	var pos: Vector2 = _sprite.global_position if _sprite else user.global_position
	world_manager.place_gas(pos, GAS_RADIUS, GAS_DENSITY)
	_start_bounce()


func _tick_impl(_delta: float) -> void:
	pass


func update_visual(delta: float, user: Node) -> void:
	if visual == null:
		return
	_facing_angle = _get_facing_direction(user).angle()
	if _visual_angle != _visual_angle:
		_visual_angle = _facing_angle
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, IDLE_ROTATION_SPEED * delta))
	if _is_bouncing:
		_process_bounce(delta)
	else:
		_process_idle()


func _start_bounce() -> void:
	_bounce_scale = Vector2.ONE
	_phase = Phase.UP
	_phase_time = 0.0
	_is_bouncing = true


func _process_idle() -> void:
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI * 3.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _process_bounce(delta: float) -> void:
	_phase_time += delta
	var target_scale: Vector2 = Vector2.ONE
	var scale_speed: float = LERP_EASE
	match _phase:
		Phase.UP:
			target_scale = BOUNCE_SCALE_UP
			scale_speed = LERP_SNAP
			if _phase_time >= BOUNCE_UP_DURATION:
				_phase = Phase.DOWN
				_phase_time = 0.0
		Phase.DOWN:
			var settle_decay := maxf(0.0, 1.0 - _phase_time / BOUNCE_DOWN_DURATION)
			target_scale = Vector2.ONE + (BOUNCE_SETTLE - Vector2.ONE) * settle_decay
			scale_speed = LERP_SNAP
			if _phase_time >= BOUNCE_DOWN_DURATION:
				_is_bouncing = false
				_bounce_scale = Vector2.ONE
				_process_idle()
				return
		_:
			_is_bouncing = false
			_bounce_scale = Vector2.ONE
			_process_idle()
			return
	var scale_factor: float = 1.0 - exp(-scale_speed * delta)
	_bounce_scale = _bounce_scale.lerp(target_scale, scale_factor)
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI * 3.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = _bounce_scale


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
```

Key changes from original:
- Removed `_cooldown_timer` (now on base class)
- Removed `is_ready()` override (now on base class)
- Removed cooldown check from `use()` (now in base class)
- Removed `_cooldown_timer = cooldown` from `use()` (now in base class)
- Renamed `use()` → `_use_impl()`
- Renamed `tick()` → `_tick_impl()`
- Added `modifier_slot_count = 3` and `modifiers.resize(modifier_slot_count)` in `_init()`

- [ ] **Step 2: Commit**

```bash
git add src/weapons/test_weapon.gd
git commit -m "refactor: update TestWeapon for modifier system template method pattern"
```

---

### Task 4: Refactor MeleeWeapon

**Files:**
- Modify: `src/weapons/melee_weapon.gd`

- [ ] **Step 1: Refactor MeleeWeapon to use _use_impl and _tick_impl**

Replace the entire content of `src/weapons/melee_weapon.gd` with:

```gdscript
class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/Weapons/sword_01c.png")
const RANGE: float = 24.0
const ARC_ANGLE: float = PI / 2.0
const PUSH_SPEED: float = 60.0

const PIVOT_DISTANCE: float = 6.0
const HALF_ARC: float = PI / 3.5

const PREP_DURATION: float = 0.08
const ACTION_DURATION: float = 0.12
const SETTLE_DURATION: float = 0.18
const RETURN_DURATION: float = 0.22

const ANTICIPATION_PULLBACK: float = PI / 6.0
const OVERSHOOT_ANGLE: float = PI / 4.0
const SETTLE_BOUNCE_AMOUNT: float = PI / 12.0
const SETTLE_BOUNCE_FREQ: float = 28.0

const PREP_SCALE: Vector2 = Vector2(1.25, 0.75)
const ACTION_SCALE: Vector2 = Vector2(0.7, 1.35)
const SETTLE_SCALE: Vector2 = Vector2(1.1, 0.92)

const PUNCH_DISTANCE: float = 14.0

const LERP_SNAP: float = 16.0
const LERP_SMOOTH: float = 10.0
const LERP_EASE: float = 6.0

const TRAIL_ANGLE_STEP: float = PI / 32.0
const TRAIL_LIFETIME: float = 0.15
const TRAIL_COLOR: Color = Color(2.0, 6.0, 8.0, 0.6)

enum Phase { NONE, PREP, ACTION, SETTLE, RETURN }

var _is_swinging: bool = false
var _phase: int = Phase.NONE
var _phase_time: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _swing_dir: float = 1.0
var _facing_angle: float = 0.0
var _visual_angle: float = NAN
var _last_trail_angle: float = 0.0
var _swing_angle: float = 0.0
var _swing_dist: float = PIVOT_DISTANCE
var _swing_scale: Vector2 = Vector2.ONE

const IDLE_ROTATION_SPEED: float = 10.0


func _init() -> void:
	name = "Melee Weapon"
	cooldown = 0.5
	damage = 5.0
	icon_texture = WEAPON_TEXTURE
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)


func has_visual() -> bool:
	return true


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	_sprite.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(0, -tex_size.y / 2.0)


func _use_impl(user: Node) -> void:
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	var materials: Array[int] = MaterialRegistry.get_fluids()
	world_manager.clear_and_push_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, 0.25, materials)


func _tick_impl(_delta: float) -> void:
	pass


func update_visual(delta: float, user: Node) -> void:
	if visual == null:
		return
	_facing_angle = _get_facing_direction(user).angle()
	if _visual_angle != _visual_angle:
		_visual_angle = _facing_angle
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, IDLE_ROTATION_SPEED * delta))
	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _start_swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_start_angle = _facing_angle - HALF_ARC
	_end_angle = _facing_angle + HALF_ARC
	_swing_dir = signf(_end_angle - _start_angle)
	_swing_angle = _visual_angle
	_swing_dist = PIVOT_DISTANCE
	_swing_scale = Vector2.ONE
	_phase = Phase.PREP
	_phase_time = 0.0
	_last_trail_angle = _swing_angle
	_is_swinging = true


func _process_idle() -> void:
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI * 3.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _process_swing(delta: float) -> void:
	_phase_time += delta
	var target_angle: float = _facing_angle
	var target_dist: float = PIVOT_DISTANCE
	var target_scale: Vector2 = Vector2.ONE
	var angle_speed: float = LERP_SMOOTH
	var dist_speed: float = LERP_SMOOTH
	var scale_speed: float = LERP_SMOOTH
	match _phase:
		Phase.PREP:
			target_angle = _start_angle - ANTICIPATION_PULLBACK * _swing_dir
			target_dist = PIVOT_DISTANCE * 0.85
			target_scale = PREP_SCALE
			angle_speed = LERP_SMOOTH
			dist_speed = LERP_SMOOTH
			scale_speed = LERP_SMOOTH
			if _phase_time >= PREP_DURATION:
				_phase = Phase.ACTION
				_phase_time = 0.0
				_last_trail_angle = _swing_angle
		Phase.ACTION:
			target_angle = _end_angle + OVERSHOOT_ANGLE * _swing_dir
			target_dist = PUNCH_DISTANCE
			target_scale = ACTION_SCALE
			angle_speed = LERP_SNAP
			dist_speed = LERP_SNAP
			scale_speed = LERP_SNAP
			if _phase_time >= ACTION_DURATION:
				_phase = Phase.SETTLE
				_phase_time = 0.0
		Phase.SETTLE:
			var decay := maxf(0.0, 1.0 - _phase_time / SETTLE_DURATION)
			target_angle = _end_angle + sin(_phase_time * SETTLE_BOUNCE_FREQ) * SETTLE_BOUNCE_AMOUNT * decay * _swing_dir
			target_dist = PIVOT_DISTANCE
			target_scale = Vector2.ONE + (SETTLE_SCALE - Vector2.ONE) * decay
			angle_speed = LERP_SMOOTH
			dist_speed = LERP_SMOOTH
			scale_speed = LERP_SMOOTH
			if _phase_time >= SETTLE_DURATION:
				_phase = Phase.RETURN
				_phase_time = 0.0
		Phase.RETURN:
			target_angle = _facing_angle
			target_dist = PIVOT_DISTANCE
			target_scale = Vector2.ONE
			angle_speed = LERP_EASE
			dist_speed = LERP_EASE
			scale_speed = LERP_EASE
			if _phase_time >= RETURN_DURATION:
				_is_swinging = false
				_visual_angle = _swing_angle
				_process_idle()
				return
		_:
			_is_swinging = false
			_process_idle()
			return
	var angle_factor: float = 1.0 - exp(-angle_speed * delta)
	var dist_factor: float = 1.0 - exp(-dist_speed * delta)
	var scale_factor: float = 1.0 - exp(-scale_speed * delta)
	_swing_angle = lerp_angle(_swing_angle, target_angle, angle_factor)
	_swing_dist = lerpf(_swing_dist, target_dist, dist_factor)
	_swing_scale = _swing_scale.lerp(target_scale, scale_factor)
	visual.position = Vector2.ZERO
	visual.rotation = 0.0
	_sprite.position = Vector2(cos(_swing_angle), sin(_swing_angle)) * _swing_dist
	_sprite.rotation = _swing_angle + PI * 3.0 / 4.0
	_sprite.scale = _swing_scale
	if _phase == Phase.ACTION or _phase == Phase.SETTLE:
		var progress := angle_difference(_last_trail_angle, _swing_angle) * _swing_dir
		var max_spawns := 8
		while progress >= TRAIL_ANGLE_STEP and max_spawns > 0:
			_last_trail_angle += TRAIL_ANGLE_STEP * _swing_dir
			progress -= TRAIL_ANGLE_STEP
			max_spawns -= 1
			_spawn_trail_at_angle(_last_trail_angle)


func _spawn_trail_at_angle(angle: float) -> void:
	var trail := Sprite2D.new()
	trail.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	trail.offset = Vector2(0, -tex_size.y / 2.0)
	trail.modulate = TRAIL_COLOR
	trail.z_index = -1
	trail.z_as_relative = false
	visual.get_tree().current_scene.add_child(trail)
	var local_pos := Vector2(cos(angle), sin(angle)) * _swing_dist
	trail.global_position = visual.global_position + local_pos.rotated(visual.global_rotation)
	trail.global_rotation = visual.global_rotation + angle + PI * 3.0 / 4.0
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, TRAIL_LIFETIME)
	tween.tween_callback(trail.queue_free)


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
```

Key changes from original:
- Removed `_cooldown_timer` (now on base class)
- Removed `is_ready()` override (now on base class)
- Removed cooldown check from `use()` (now in base class)
- Removed `_cooldown_timer = cooldown` from `use()` (now in base class)
- Renamed `use()` → `_use_impl()`
- Renamed `tick()` → `_tick_impl()`
- Added `modifier_slot_count = 3` and `modifiers.resize(modifier_slot_count)` in `_init()`

- [ ] **Step 2: Commit**

```bash
git add src/weapons/melee_weapon.gd
git commit -m "refactor: update MeleeWeapon for modifier system template method pattern"
```

---

### Task 5: Create Lava Emitter Modifier

**Files:**
- Create: `src/weapons/lava_emitter_modifier.gd`

- [ ] **Step 1: Create a placeholder icon texture**

We need a small icon for the lava emitter. Create a simple 16x16 PNG. You can create this programmatically or use an existing texture as a placeholder. For now, copy an existing weapon texture as a stand-in:

```bash
mkdir -p textures/Modifiers
cp textures/Weapons/candy_02c.png textures/Modifiers/lava_emitter.png
```

This is a temporary placeholder — the icon will be replaced with a proper lava-themed icon later.

- [ ] **Step 2: Write the LavaEmitterModifier class**

Create `src/weapons/lava_emitter_modifier.gd`:

```gdscript
class_name LavaEmitterModifier
extends Modifier

const LAVA_RADIUS: float = 6.0


func _init() -> void:
	name = "Lava Emitter"
	description = "Spawns lava around the user when the weapon is used."
	icon_texture = preload("res://textures/Modifiers/lava_emitter.png")


func on_use(_weapon: Weapon, user: Node) -> void:
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	var pos: Vector2 = _weapon._sprite.global_position if _weapon._sprite else user.global_position
	world_manager.place_lava(pos, LAVA_RADIUS)


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null
```

- [ ] **Step 3: Commit**

```bash
git add src/weapons/lava_emitter_modifier.gd textures/Modifiers/lava_emitter.png
git commit -m "feat: add LavaEmitterModifier that spawns lava on weapon use"
```

---

### Task 6: Update WeaponManager to Wire Modifiers

**Files:**
- Modify: `src/weapons/weapon_manager.gd`

- [ ] **Step 1: Update WeaponManager with modifier preloads and helper method**

Replace the entire content of `src/weapons/weapon_manager.gd` with:

```gdscript
class_name WeaponManager
extends Node

const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/lava_emitter_modifier.gd")

signal weapon_activated(slot_index: int)

var weapons: Array[Weapon] = []
var active_slot: int = 0
var _player: Node = null
var _visual: Node2D = null
var _sprite: Sprite2D = null
var _active_weapon: Weapon = null


func _ready() -> void:
	_player = get_parent()
	weapons.resize(3)
	var test_weapon := TestWeaponScript.new()
	test_weapon.add_modifier(0, LavaEmitterModifierScript.new())
	weapons[0] = test_weapon
	weapons[1] = MeleeWeaponScript.new()
	_setup_visual.call_deferred()


func _setup_visual() -> void:
	_visual = Node2D.new()
	_visual.name = "WeaponVisual"
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_visual.add_child(_sprite)
	_player.add_child(_visual)
	_visual.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			var weapon := weapons[slot]
			if weapon.is_ready():
				_activate_weapon(weapon)
				weapon.use(_player)
				active_slot = slot
				weapon_activated.emit(slot)


func _activate_weapon(weapon: Weapon) -> void:
	if weapon.has_visual():
		weapon.setup_visual(_visual, _sprite)
		_visual.visible = true
	else:
		_visual.visible = false
	_active_weapon = weapon


func _process(delta: float) -> void:
	if _active_weapon != null and _active_weapon.has_visual():
		_active_weapon.update_visual(delta, _player)


func _physics_process(delta: float) -> void:
	for weapon in weapons:
		if weapon != null:
			weapon.tick(delta)


func swap_weapons(slot_a: int, slot_b: int) -> void:
	var temp := weapons[slot_a]
	weapons[slot_a] = weapons[slot_b]
	weapons[slot_b] = temp


func try_add_weapon(weapon: Weapon) -> bool:
	for i in range(weapons.size()):
		if weapons[i] == null:
			weapons[i] = weapon
			return true
	return false


func swap_weapon(slot_index: int, new_weapon: Weapon) -> Weapon:
	if slot_index < 0 or slot_index >= weapons.size():
		return null
	var old_weapon: Weapon = weapons[slot_index]
	weapons[slot_index] = new_weapon
	return old_weapon


func has_empty_slot() -> bool:
	for weapon in weapons:
		if weapon == null:
			return true
	return false


func add_modifier_to_weapon(weapon_slot: int, modifier_slot: int, modifier: Modifier) -> void:
	if weapon_slot < 0 or weapon_slot >= weapons.size():
		return
	var weapon := weapons[weapon_slot]
	if weapon == null:
		return
	weapon.add_modifier(modifier_slot, modifier)
```

Key changes:
- Added `LavaEmitterModifierScript` preload
- Wired a `LavaEmitterModifier` into slot 0 of the TestWeapon in `_ready()`
- Moved `is_ready()` check to before `_activate_weapon()` and `weapon.use()` in `_input()` — this is necessary because the base `use()` now handles cooldown internally, so we need to check readiness in WeaponManager before calling `use()`. Previously weapons checked cooldown inside their own `use()`, but now cooldown is in the base class `use()` which also fires modifiers — we don't want to activate visuals if the weapon isn't ready.

- [ ] **Step 2: Commit**

```bash
git add src/weapons/weapon_manager.gd
git commit -m "feat: wire LavaEmitterModifier on TestWeapon and add modifier helper"
```

---

### Task 7: Update Weapon Popup with Modifier Slots and Tooltips

**Files:**
- Modify: `src/ui/weapon_popup.gd`

- [ ] **Step 1: Update weapon_popup.gd with modifier display and hover tooltips**

Replace the entire content of `src/ui/weapon_popup.gd` with:

```gdscript
extends CanvasLayer

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")
const CARD_MIN_SIZE := Vector2(160, 200)
const ICON_SIZE := Vector2(96, 96)
const MODIFIER_ICON_SIZE := Vector2(32, 32)

@onready var _overlay: ColorRect = %Overlay
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _title_label: Label = %TitleLabel

var _weapon_manager: WeaponManager = null
var _selected_slot: int = -1
var _pickup_mode: bool = false
var _pickup_weapon: Weapon = null
var _pickup_callback: Callable
var _modifier_tooltip: PanelContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	visible = false
	_overlay.gui_input.connect(_on_overlay_input)


func open(weapon_manager: WeaponManager) -> void:
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_pickup(weapon_manager: WeaponManager, new_weapon: Weapon, callback: Callable) -> void:
	_pickup_mode = true
	_pickup_weapon = new_weapon
	_pickup_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_build_cards()
	_title_label.text = "Replace a slot:"
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_cancel_modifier_tooltip()
	visible = false
	_weapon_manager = null
	_pickup_mode = false
	_pickup_weapon = null
	_pickup_callback = Callable()
	_selected_slot = -1
	_clear_cards()
	SceneManager.set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _build_cards() -> void:
	_clear_cards()
	for i in range(3):
		var weapon: Weapon = null
		if i < _weapon_manager.weapons.size():
			weapon = _weapon_manager.weapons[i]
		var card := _create_card(weapon, i)
		_cards_container.add_child(card)


func _clear_cards() -> void:
	for child in _cards_container.get_children():
		child.queue_free()


func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_card_input.bind(slot_index))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon == null:
		var label := Label.new()
		label.text = "EMPTY"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)
	else:
		_add_icon(vbox, weapon)
		var name_label := Label.new()
		name_label.text = weapon.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_label)

		var stats := weapon.get_base_stats()
		var cooldown_label := Label.new()
		cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(cooldown_label)

		var damage_label := Label.new()
		damage_label.text = "Damage: %.0f" % stats["damage"]
		damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(damage_label)

		_add_modifier_slots(vbox, weapon)

	return card


func _add_icon(parent: VBoxContainer, weapon: Weapon) -> void:
	if weapon.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = weapon.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		parent.add_child(icon)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = ICON_SIZE
		fallback.color = Color(0.3, 0.3, 0.3, 1)
		parent.add_child(fallback)
		var q_label := Label.new()
		q_label.text = "?"
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_label.anchors_preset = Control.PRESET_FULL_RECT
		fallback.add_child(q_label)


func _add_modifier_slots(parent: VBoxContainer, weapon: Weapon) -> void:
	var slot_container := HBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 4)
	slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(slot_container)

	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			else:
				icon.texture = null
			icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			icon.gui_input.connect(_on_modifier_icon_input.bind(modifier, icon))
			icon.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, icon))
			icon.mouse_exited.connect(_on_modifier_icon_mouse_exited)
			slot_container.add_child(icon)
		else:
			var empty_slot := ColorRect.new()
			empty_slot.custom_minimum_size = MODIFIER_ICON_SIZE
			empty_slot.color = Color(0.2, 0.2, 0.2, 1)
			slot_container.add_child(empty_slot)


func _on_modifier_icon_mouse_entered(modifier: Modifier, icon: Control) -> void:
	_cancel_modifier_tooltip()
	_modifier_tooltip = PanelContainer.new()
	_modifier_tooltip.add_theme_constant_override("margin_left", 6)
	_modifier_tooltip.add_theme_constant_override("margin_right", 6)
	_modifier_tooltip.add_theme_constant_override("margin_top", 4)
	_modifier_tooltip.add_theme_constant_override("margin_bottom", 4)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_modifier_tooltip.add_child(vbox)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = modifier.get_description()
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_label)

	_apply_tooltip_theme(_modifier_tooltip, name_label, desc_label)

	add_child(_modifier_tooltip)
	_position_tooltip_near(icon)


func _on_modifier_icon_mouse_exited() -> void:
	_cancel_modifier_tooltip()


func _on_modifier_icon_input(event: InputEvent, _modifier: Modifier, _icon: Control) -> void:
	pass


func _position_tooltip_near(icon: Control) -> void:
	if _modifier_tooltip == null:
		return
	await get_tree().process_frame
	var icon_rect := icon.get_global_rect()
	var tooltip_size := _modifier_tooltip.get_combined_minimum_size()
	_modifier_tooltip.global_position = Vector2(
		icon_rect.position.x + icon_rect.size.x / 2.0 - tooltip_size.x / 2.0,
		icon_rect.position.y - tooltip_size.y - 4.0
	)
	_modifier_tooltip.size = tooltip_size


func _cancel_modifier_tooltip() -> void:
	if _modifier_tooltip != null:
		_modifier_tooltip.queue_free()
		_modifier_tooltip = null


func _apply_tooltip_theme(tooltip: PanelContainer, name_label: Label, desc_label: Label) -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 14)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	name_label.theme = t
	desc_label.theme = t


func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			_pickup_callback.call(slot_index)
			close()
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()


func _highlight_slot(slot_index: int) -> void:
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var card: Control = cards[slot_index]
		card.modulate = Color(1.0, 1.0, 0.7, 1.0)


func _swap_weapons(slot_a: int, slot_b: int) -> void:
	if _weapon_manager != null:
		_weapon_manager.swap_weapons(slot_a, slot_b)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			close()


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	_title_label.theme = t
```

Key additions:
- `_add_modifier_slots()` — renders modifier icons in an HBoxContainer per weapon card
- `_on_modifier_icon_mouse_entered()` — creates a floating tooltip PanelContainer with modifier name + description
- `_on_modifier_icon_mouse_exited()` — hides tooltip
- `_position_tooltip_near()` — positions tooltip above the hovered icon
- `_cancel_modifier_tooltip()` — cleans up tooltip on close or mouse exit
- `MODIFIER_ICON_SIZE` constant (32x32)

- [ ] **Step 2: Commit**

```bash
git add src/ui/weapon_popup.gd
git commit -m "feat: add modifier slot icons and hover tooltips to weapon popup"
```

---

### Task 8: Update Weapon Button Tooltip with Modifier Icons

**Files:**
- Modify: `src/ui/weapon_button.gd`
- Modify: `scenes/ui/weapon_button.tscn` (add ModifierRow container)

- [ ] **Step 1: Update weapon_button.gd to show modifier icons in tooltip**

Replace the entire content of `src/ui/weapon_button.gd` with:

```gdscript
extends CanvasLayer

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")
const MODIFIER_ICON_SIZE := Vector2(16, 16)

@export var weapon_popup: NodePath

@onready var _icon_button: TextureButton = %IconButton
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_name: Label = %TooltipName
@onready var _tooltip_cooldown: Label = %TooltipCooldown
@onready var _tooltip_damage: Label = %TooltipDamage
@onready var _fallback_icon: ColorRect = %FallbackIcon

var _weapon_manager: WeaponManager = null
var _current_weapon: Weapon = null


func _ready() -> void:
	_apply_theme()
	_tooltip.visible = false
	_fallback_icon.visible = false
	_icon_button.texture_normal = null
	_icon_button.pressed.connect(_on_button_pressed)
	_icon_button.mouse_entered.connect(_on_mouse_entered)
	_icon_button.mouse_exited.connect(_on_mouse_exited)
	_find_weapon_manager()
	if _weapon_manager != null:
		_weapon_manager.weapon_activated.connect(_on_weapon_activated)
		_update_display(_weapon_manager.active_slot)


func _find_weapon_manager() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_weapon_manager = player.get_node("WeaponManager")


func _on_weapon_activated(slot_index: int) -> void:
	_update_display(slot_index)


func _update_display(slot_index: int) -> void:
	if _weapon_manager == null:
		return
	if slot_index < 0 or slot_index >= _weapon_manager.weapons.size():
		return
	var weapon: Weapon = _weapon_manager.weapons[slot_index]
	if weapon == null:
		return
	_current_weapon = weapon
	if weapon.icon_texture != null:
		_icon_button.texture_normal = weapon.icon_texture
		_icon_button.visible = true
		_fallback_icon.visible = false
	else:
		_icon_button.visible = false
		_fallback_icon.visible = true
	_tooltip.visible = false


func _on_button_pressed() -> void:
	if _weapon_manager != null:
		var popup := get_node_or_null(weapon_popup)
		if popup and popup.has_method("open"):
			popup.open(_weapon_manager)


func _on_mouse_entered() -> void:
	if _current_weapon != null:
		_update_tooltip()
		_tooltip.visible = true


func _on_mouse_exited() -> void:
	_tooltip.visible = false


func _update_tooltip() -> void:
	if _current_weapon == null:
		return
	var stats := _current_weapon.get_base_stats()
	_tooltip_name.text = str(stats["name"])
	_tooltip_cooldown.text = "Cooldown: %.1fs" % stats["cooldown"]
	_tooltip_damage.text = "Damage: %.0f" % stats["damage"]
	_clear_modifier_icons()
	_add_modifier_icons()


func _clear_modifier_icons() -> void:
	var row := _tooltip.get_node_or_null("VBoxContainer/ModifierRow")
	if row != null:
		for child in row.get_children():
			child.queue_free()


func _add_modifier_icons() -> void:
	var vbox := _tooltip.get_node("VBoxContainer")
	var row := vbox.get_node_or_null("ModifierRow")
	if row == null:
		row = HBoxContainer.new()
		row.name = "ModifierRow"
		row.add_theme_constant_override("separation", 2)
		vbox.add_child(row)
	for i in range(_current_weapon.modifier_slot_count):
		var modifier: Modifier = _current_weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			row.add_child(icon)
		else:
			var empty := ColorRect.new()
			empty.custom_minimum_size = MODIFIER_ICON_SIZE
			empty.color = Color(0.2, 0.2, 0.2, 1)
			row.add_child(empty)


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	_tooltip_name.theme = t
	_tooltip_cooldown.theme = t
	_tooltip_damage.theme = t
```

Key additions:
- `MODIFIER_ICON_SIZE` constant (16x16)
- `_add_modifier_icons()` — adds modifier icon row to tooltip VBoxContainer
- `_clear_modifier_icons()` — removes old modifier icons when tooltip refreshes
- Dynamically creates a `ModifierRow` HBoxContainer if it doesn't exist

No changes to the .tscn file are needed — the `ModifierRow` HBoxContainer is created dynamically in code and added to the existing `VBoxContainer` inside the tooltip.

- [ ] **Step 2: Commit**

```bash
git add src/ui/weapon_button.gd
git commit -m "feat: add modifier icon row to weapon button tooltip"
```

---

### Task 9: Integration Test — Run the Game

- [ ] **Step 1: Launch the game and verify the following**

1. Game starts without errors (check Godot output console)
2. Press Z — Test Weapon should fire (spawn gas) AND also spawn lava (Lava Emitter modifier)
3. Press X — Melee Weapon should swing normally (no modifiers equipped)
4. Open weapon popup — each weapon card should show modifier slot icons beneath the stats
5. Test Weapon slot 0 should show the Lava Emitter icon (the placeholder candy texture)
6. Hover over the Lava Emitter icon — should show a tooltip with "Lava Emitter" and description
7. Move mouse away from the icon — tooltip should disappear
8. The weapon button tooltip (HUD) should show modifier icons when hovering over the weapon icon

If any of these fail, debug and fix before proceeding.

- [ ] **Step 2: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address integration issues from testing"
```