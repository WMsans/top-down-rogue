# Parry & Projectile Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Hollow Knight-style parry on the player's melee swing for enemy melee attacks, and Soul Knight-style projectile destruction during the swing, with two-tier feedback (dramatic clash, lightweight block).

**Architecture:** Extend `MeleeWeapon` with swing-phase getters and a per-frame in-arc projectile scan. Add `try_parry` on `PlayerController` called from the enemy's `MeleeWeapon._hit_attackables_in_arc`. Two static FX helpers (`NailClashFX`, `ProjectileBlockFX`) instantiate scene-tree effects from one-line call sites. Enemy gains a stun gate field consumed by AI ticks.

**Tech Stack:** Godot 4 / GDScript, GdUnit4 test framework, existing GPUParticles2D + shader patterns.

Spec: `docs/superpowers/specs/2026-05-12-parry-and-projectile-block-design.md`

---

## File map

**Create:**
- `src/player/feedback/nail_clash_fx.gd` — static `play(pos, normal)` helper that instantiates the nail-clash scene and drives hitstop + camera shake.
- `src/player/feedback/projectile_block_fx.gd` — static `play(pos, dir)` helper that instantiates the block scene.
- `scenes/fx/nail_clash.tscn` — particles + flash sprite + shockwave-ring quad; self-frees after lifetime.
- `scenes/fx/projectile_block.tscn` — sparks + flash sprite; self-frees after lifetime.
- `shaders/fx/shockwave_ring.gdshader` — expanding-ring shader driven by `radius`, `alpha` uniforms.
- `tests/unit/test_parry_window.gd` — phase getter timing.
- `tests/unit/test_projectile_block.gd` — projectile-in-arc destruction.
- `tests/unit/test_parry_intercept.gd` — `try_parry` skipping damage and stunning attacker.
- `tests/unit/test_unparryable.gd` — `parryable=false` enemy not parried.

**Modify:**
- `src/weapons/melee_weapon.gd` — exports, phase tracking, projectile scan, parry call hook.
- `src/weapons/projectile.gd` — group add in `_ready`.
- `src/player/player_controller.gd` — `try_parry` method.
- `src/enemies/enemy.gd` — `_parry_stun_remaining` field, AI gate, cooldown extension.

---

### Task 1: `MeleeWeapon` swing-phase exposure

**Files:**
- Modify: `src/weapons/melee_weapon.gd`
- Test: `tests/unit/test_parry_window.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_parry_window.gd`:

```gdscript
extends GdUnitTestSuite

func _make_user() -> Node2D:
	var n := auto_free(Node2D.new())
	add_child(n)
	return n

func test_parry_active_only_during_window() -> void:
	var w := MeleeWeapon.new()
	w.parry_window = 0.1
	var user := _make_user()
	assert_that(w.is_parry_active()).is_false()
	assert_that(w.is_swing_active()).is_false()
	w.use(user)
	assert_that(w.is_parry_active()).is_true()
	assert_that(w.is_swing_active()).is_true()
	# Advance past parry window but still inside swing
	for i in range(3):
		w.update_visual(0.04, user)  # 0.12s elapsed
	assert_that(w.is_parry_active()).is_false()
	assert_that(w.is_swing_active()).is_true()

func test_swing_inactive_during_return_phase() -> void:
	var w := MeleeWeapon.new()
	var user := _make_user()
	w.use(user)
	# PREP 0.06 + ACTION 0.09 + HOLD 0.025 = 0.175 — advance past that
	for i in range(6):
		w.update_visual(0.04, user)  # 0.24s elapsed → in RETURN
	assert_that(w.is_swing_active()).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_parry_window.gd`
Expected: FAIL — `is_parry_active` / `is_swing_active` not defined.

- [ ] **Step 3: Implement phase getters and elapsed tracking**

Modify `src/weapons/melee_weapon.gd`. Add exports near the other tunables (after `return_duration`):

```gdscript
@export var parry_window: float = 0.1
@export var parryable: bool = true
```

Add an elapsed-time field with the other phase fields (after `_phase_time`):

```gdscript
var _swing_elapsed: float = 0.0
```

In `_start_swing`, after `_is_swinging = true`, add:

```gdscript
_swing_elapsed = 0.0
```

In `_process_swing`, at the very top (before `_phase_time += _delta`), add:

```gdscript
_swing_elapsed += _delta
```

Append two public methods near the end of the file (after `_get_facing_direction`):

```gdscript
func is_swing_active() -> bool:
	if not _is_swinging:
		return false
	return _phase == Phase.PREP or _phase == Phase.ACTION or _phase == Phase.HOLD


func is_parry_active() -> bool:
	if not _is_swinging:
		return false
	return _swing_elapsed <= parry_window
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_parry_window.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/melee_weapon.gd tests/unit/test_parry_window.gd
git commit -m "feat(weapons): expose swing phase getters for parry and block"
```

---

### Task 2: Register projectiles in `"projectile"` group

**Files:**
- Modify: `src/weapons/projectile.gd`
- Test: `tests/unit/test_projectile.gd` (extend existing)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_projectile.gd`:

```gdscript
func test_projectile_registers_in_group() -> void:
	var p := auto_free(Projectile.new())
	add_child(p)
	assert_that(p.is_in_group("projectile")).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_projectile.gd`
Expected: FAIL — group missing.

- [ ] **Step 3: Add group registration**

Modify `src/weapons/projectile.gd:14-17`. Replace the existing `_ready`:

```gdscript
func _ready() -> void:
	add_to_group("projectile")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_projectile.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/projectile.gd tests/unit/test_projectile.gd
git commit -m "feat(projectile): register in \"projectile\" group for arc scans"
```

---

### Task 3: `ProjectileBlockFX` helper + scene

**Files:**
- Create: `src/player/feedback/projectile_block_fx.gd`
- Create: `scenes/fx/projectile_block.tscn`

- [ ] **Step 1: Create the FX scene**

Create `scenes/fx/projectile_block.tscn` with this content (Godot 4 text scene format):

```
[gd_scene load_steps=2 format=3]

[sub_resource type="Gradient" id="Gradient_block"]
colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture_block"]
gradient = SubResource("Gradient_block")

[sub_resource type="ParticleProcessMaterial" id="ParticleProcess_block"]
emission_shape = 0
direction = Vector3(1, 0, 0)
spread = 30.0
initial_velocity_min = 80.0
initial_velocity_max = 140.0
gravity = Vector3(0, 0, 0)
scale_min = 0.6
scale_max = 1.2
color_ramp = SubResource("GradientTexture_block")

[node name="ProjectileBlockFX" type="Node2D"]

[node name="Sparks" type="GPUParticles2D" parent="."]
emitting = false
amount = 10
lifetime = 0.12
one_shot = true
explosiveness = 1.0
process_material = SubResource("ParticleProcess_block")

[node name="Flash" type="Sprite2D" parent="."]
modulate = Color(1, 1, 1, 1)
scale = Vector2(0, 0)

[node name="LifetimeTimer" type="Timer" parent="."]
wait_time = 0.3
one_shot = true
autostart = true
```

- [ ] **Step 2: Write the FX helper**

Create `src/player/feedback/projectile_block_fx.gd`:

```gdscript
class_name ProjectileBlockFX
extends RefCounted

const SCENE: PackedScene = preload("res://scenes/fx/projectile_block.tscn")


static func play(pos: Vector2, dir: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var fx := SCENE.instantiate() as Node2D
	fx.global_position = pos
	if dir.length_squared() > 0.0001:
		fx.rotation = dir.angle()
	tree.current_scene.add_child(fx)
	var sparks := fx.get_node_or_null("Sparks") as GPUParticles2D
	if sparks:
		sparks.restart()
		sparks.emitting = true
	var flash := fx.get_node_or_null("Flash") as Sprite2D
	if flash:
		var tw := flash.create_tween()
		tw.tween_property(flash, "scale", Vector2.ONE, 0.03)
		tw.tween_property(flash, "modulate:a", 0.0, 0.08)
	var timer := fx.get_node_or_null("LifetimeTimer") as Timer
	if timer:
		timer.timeout.connect(fx.queue_free)
```

- [ ] **Step 3: Sanity-check the scene loads**

Run: `godot --headless --path . --check-only scenes/fx/projectile_block.tscn 2>&1 | head -5`
Expected: no parse errors.

- [ ] **Step 4: Commit**

```bash
git add src/player/feedback/projectile_block_fx.gd scenes/fx/projectile_block.tscn
git commit -m "feat(fx): add ProjectileBlockFX helper and scene"
```

---

### Task 4: `MeleeWeapon` per-frame projectile-in-arc destruction

**Files:**
- Modify: `src/weapons/melee_weapon.gd`
- Test: `tests/unit/test_projectile_block.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_projectile_block.gd`:

```gdscript
extends GdUnitTestSuite

func _make_user() -> Node2D:
	var n := auto_free(Node2D.new())
	add_child(n)
	n.global_position = Vector2.ZERO
	# user.get_facing_direction() default fallback returns DOWN; we override here:
	n.set_script(GDScript.new())
	return n

func test_enemy_projectile_in_arc_is_destroyed_during_swing() -> void:
	var w := MeleeWeapon.new()
	var user := auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	# Spawn an enemy projectile in front of the user, well inside weapon_reach.
	var p := Projectile.new()
	p.is_enemy_projectile = true
	p.direction = Vector2.LEFT
	add_child(p)
	auto_free(p)
	p.global_position = Vector2(10, 0)  # within reach (36) and within default arc

	w.use(user)
	w.update_visual(0.02, user)  # one swing tick within active phase
	assert_that(is_instance_valid(p)).is_false()

func test_player_projectile_is_ignored() -> void:
	var w := MeleeWeapon.new()
	var user := auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var p := auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.direction = Vector2.LEFT
	add_child(p)
	p.global_position = Vector2(10, 0)

	w.use(user)
	w.update_visual(0.02, user)
	assert_that(is_instance_valid(p)).is_true()

func test_projectile_outside_arc_survives() -> void:
	var w := MeleeWeapon.new()
	var user := auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var p := auto_free(Projectile.new())
	p.is_enemy_projectile = true
	p.direction = Vector2.LEFT
	add_child(p)
	# User default-facing is DOWN; place projectile to the LEFT (out of front arc).
	p.global_position = Vector2(-30, 0)

	w.use(user)
	w.update_visual(0.02, user)
	assert_that(is_instance_valid(p)).is_true()
```

Note: `MeleeWeapon._get_facing_direction` returns `Vector2.DOWN` when the user has no facing method or velocity. The "in front" test placements above assume DOWN-facing — projectile at `(10, 0)` is `90°` from DOWN, but `arc_angle = PI/2` means half-arc is `PI/4`, so `(10, 0)` is OUTSIDE the arc. Use `(0, 10)` instead (directly in front when facing DOWN). Update the test placements:

Replace `p.global_position = Vector2(10, 0)` with `p.global_position = Vector2(0, 10)` in both `test_enemy_projectile_in_arc_is_destroyed_during_swing` and `test_player_projectile_is_ignored`. Keep `Vector2(-30, 0)` for the outside-arc test (it's behind the user when facing down — actually `(-30, 0)` is to the side, ~90° from DOWN, outside the PI/4 half-arc — good).

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_projectile_block.gd`
Expected: FAIL — projectile not destroyed (scan not implemented).

- [ ] **Step 3: Add the projectile arc scan**

Modify `src/weapons/melee_weapon.gd`. At the top of `_process_swing` (right after `_swing_elapsed += _delta` added in Task 1), call the scan when active:

```gdscript
	if is_swing_active():
		_destroy_projectiles_in_arc(_current_user, _current_user.global_position if _current_user else Vector2.ZERO, _get_facing_direction(_current_user) if _current_user else Vector2.DOWN)
```

We need a `_current_user` reference. Add the field near `_is_swinging`:

```gdscript
var _current_user: Node = null
```

In `_use_impl`, set it at the top:

```gdscript
	_current_user = user
```

Also set it at the top of `update_visual` so swings driven via `update_visual` (tests) have a user:

```gdscript
	_current_user = user
```

Add the helper method at the bottom of the file (next to `_hit_attackables_in_arc`):

```gdscript
func _destroy_projectiles_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	if user == null:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc_angle / 2.0
	var destroyed: int = 0
	for node in user.get_tree().get_nodes_in_group("projectile"):
		if destroyed >= 8:
			return
		if not (node is Projectile):
			continue
		var p: Projectile = node
		if not p.is_enemy_projectile:
			continue
		var to_target: Vector2 = p.global_position - origin
		var dist: float = to_target.length()
		if dist > weapon_reach or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc_angle:
			continue
		ProjectileBlockFX.play(p.global_position, -p.direction)
		p.queue_free()
		destroyed += 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_projectile_block.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/melee_weapon.gd tests/unit/test_projectile_block.gd
git commit -m "feat(weapons): destroy enemy projectiles in melee swing arc"
```

---

### Task 5: `NailClashFX` helper + scene + shockwave shader

**Files:**
- Create: `shaders/fx/shockwave_ring.gdshader`
- Create: `scenes/fx/nail_clash.tscn`
- Create: `src/player/feedback/nail_clash_fx.gd`

- [ ] **Step 1: Write the shockwave shader**

Create `shaders/fx/shockwave_ring.gdshader`:

```glsl
shader_type canvas_item;

uniform float radius : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.0, 0.5) = 0.08;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float d = length(centered) * 2.0; // 0 at center, 1 at edge
	float ring = smoothstep(thickness, 0.0, abs(d - radius));
	COLOR = vec4(ring_color.rgb, ring * alpha * ring_color.a);
}
```

- [ ] **Step 2: Write the FX scene**

Create `scenes/fx/nail_clash.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Shader" path="res://shaders/fx/shockwave_ring.gdshader" id="1_ring"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_ring"]
shader = ExtResource("1_ring")
shader_parameter/radius = 0.0
shader_parameter/thickness = 0.08
shader_parameter/alpha = 1.0
shader_parameter/ring_color = Color(1, 1, 1, 1)

[sub_resource type="Gradient" id="Gradient_clash"]
colors = PackedColorArray(1, 1, 1, 1, 0.6, 0.95, 1, 1, 0.6, 0.95, 1, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture_clash"]
gradient = SubResource("Gradient_clash")

[sub_resource type="ParticleProcessMaterial" id="ParticleProcess_clash"]
emission_shape = 0
direction = Vector3(1, 0, 0)
spread = 180.0
initial_velocity_min = 120.0
initial_velocity_max = 220.0
gravity = Vector3(0, 0, 0)
scale_min = 0.8
scale_max = 1.6
color_ramp = SubResource("GradientTexture_clash")

[node name="NailClashFX" type="Node2D"]

[node name="Sparks" type="GPUParticles2D" parent="."]
emitting = false
amount = 22
lifetime = 0.25
one_shot = true
explosiveness = 1.0
process_material = SubResource("ParticleProcess_clash")

[node name="Flash" type="Sprite2D" parent="."]
modulate = Color(1, 1, 1, 1)
scale = Vector2(0, 0)

[node name="Ring" type="ColorRect" parent="."]
material = SubResource("ShaderMaterial_ring")
offset_left = -64.0
offset_top = -64.0
offset_right = 64.0
offset_bottom = 64.0

[node name="LifetimeTimer" type="Timer" parent="."]
wait_time = 0.6
one_shot = true
autostart = true
```

- [ ] **Step 3: Write the FX helper**

Create `src/player/feedback/nail_clash_fx.gd`:

```gdscript
class_name NailClashFX
extends RefCounted

const SCENE: PackedScene = preload("res://scenes/fx/nail_clash.tscn")

const HITSTOP_DURATION: float = 0.12
const FLASH_SCALE_DURATION: float = 0.06
const FLASH_FADE_DURATION: float = 0.18
const RING_DURATION: float = 0.20
const SHAKE_AMPLITUDE: float = 6.0
const SHAKE_DURATION: float = 0.18


static func play(pos: Vector2, normal: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return

	var fx := SCENE.instantiate() as Node2D
	fx.global_position = pos
	tree.current_scene.add_child(fx)

	var sparks := fx.get_node_or_null("Sparks") as GPUParticles2D
	if sparks:
		sparks.restart()
		sparks.emitting = true

	var flash := fx.get_node_or_null("Flash") as Sprite2D
	if flash:
		var tw := flash.create_tween()
		tw.tween_property(flash, "scale", Vector2(1.6, 1.6), FLASH_SCALE_DURATION)
		tw.tween_property(flash, "modulate:a", 0.0, FLASH_FADE_DURATION)

	var ring := fx.get_node_or_null("Ring") as ColorRect
	if ring and ring.material is ShaderMaterial:
		var mat: ShaderMaterial = ring.material
		mat.set_shader_parameter("radius", 0.0)
		mat.set_shader_parameter("alpha", 1.0)
		var rtw := ring.create_tween().set_parallel(true)
		rtw.tween_method(func(v: float) -> void: mat.set_shader_parameter("radius", v), 0.0, 1.0, RING_DURATION)
		rtw.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v), 1.0, 0.0, RING_DURATION)

	var timer := fx.get_node_or_null("LifetimeTimer") as Timer
	if timer:
		timer.timeout.connect(fx.queue_free)

	_apply_hitstop(tree)
	_apply_shake(tree)


static func _apply_hitstop(tree: SceneTree) -> void:
	Engine.time_scale = 0.0
	# Real-time timer ignores time_scale.
	var t := tree.create_timer(HITSTOP_DURATION, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)


static func _apply_shake(tree: SceneTree) -> void:
	var cam := tree.get_first_node_in_group("camera")
	if cam == null:
		return
	if not (cam is Camera2D):
		return
	var camera: Camera2D = cam
	var base_offset: Vector2 = camera.offset
	var elapsed: float = 0.0
	var tw := camera.create_tween()
	# Approximate decaying shake by tweening to randomized offsets.
	var steps := 6
	for i in range(steps):
		var remaining := 1.0 - float(i) / float(steps)
		var amp := SHAKE_AMPLITUDE * remaining
		var off := base_offset + Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		tw.tween_property(camera, "offset", off, SHAKE_DURATION / float(steps))
	tw.tween_property(camera, "offset", base_offset, 0.03)
```

Note: the shake hook expects the active camera to be in a `"camera"` group. The next task adds it.

- [ ] **Step 4: Register the player camera in the `"camera"` group**

Modify `src/player/player_controller.gd`. In `_ready`, after `add_to_group("player")`, add:

```gdscript
	var cam_node := get_node_or_null("Camera2D")
	if cam_node:
		cam_node.add_to_group("camera")
```

- [ ] **Step 5: Sanity-check assets load**

Run: `godot --headless --path . --check-only scenes/fx/nail_clash.tscn 2>&1 | head -5`
Expected: no parse errors.

- [ ] **Step 6: Commit**

```bash
git add shaders/fx/shockwave_ring.gdshader scenes/fx/nail_clash.tscn src/player/feedback/nail_clash_fx.gd src/player/player_controller.gd
git commit -m "feat(fx): add NailClashFX scene, shader, and helper"
```

---

### Task 6: `PlayerController.try_parry`

**Files:**
- Modify: `src/player/player_controller.gd`
- Test: `tests/unit/test_parry_intercept.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_parry_intercept.gd`:

```gdscript
extends GdUnitTestSuite

func _attach_player_weapon(player: PlayerController, parry_active: bool) -> MeleeWeapon:
	var w := MeleeWeapon.new()
	var inv: PlayerInventory = player.get_node("PlayerInventory")
	inv.set("primary_weapon", w) if "primary_weapon" in inv else null
	# Drive the swing so parry window is open.
	if parry_active:
		w.use(player)
	return w

func test_try_parry_returns_false_when_no_weapon() -> void:
	var player := auto_free(PlayerController.new())
	add_child(player)
	await get_tree().process_frame
	var attacker := auto_free(Node2D.new())
	add_child(attacker)
	assert_that(player.try_parry(attacker, Vector2.ZERO, Vector2.RIGHT)).is_false()

func test_try_parry_succeeds_in_window() -> void:
	var player := auto_free(PlayerController.new())
	add_child(player)
	await get_tree().process_frame
	var w := MeleeWeapon.new()
	var inv: PlayerInventory = player.get_node("PlayerInventory")
	inv.equip_weapon(w) if inv.has_method("equip_weapon") else inv.set("primary_weapon", w)
	w.use(player)

	var attacker := auto_free(Enemy.new())
	add_child(attacker)
	var enemy_weapon := MeleeWeapon.new()
	enemy_weapon.parryable = true
	attacker.weapon = enemy_weapon

	var parried := player.try_parry(attacker, player.global_position, Vector2.RIGHT)
	assert_that(parried).is_true()
	assert_that(attacker._parry_stun_remaining).is_greater(0.0)

func test_try_parry_fails_for_unparryable_attacker() -> void:
	var player := auto_free(PlayerController.new())
	add_child(player)
	await get_tree().process_frame
	var w := MeleeWeapon.new()
	var inv: PlayerInventory = player.get_node("PlayerInventory")
	inv.equip_weapon(w) if inv.has_method("equip_weapon") else inv.set("primary_weapon", w)
	w.use(player)

	var attacker := auto_free(Enemy.new())
	add_child(attacker)
	var enemy_weapon := MeleeWeapon.new()
	enemy_weapon.parryable = false
	attacker.weapon = enemy_weapon

	var parried := player.try_parry(attacker, player.global_position, Vector2.RIGHT)
	assert_that(parried).is_false()
```

Note for the implementer: `PlayerInventory`'s exact API for equipping a weapon is not visible from the spec. Inspect `src/player/player_inventory.gd` and pick the correct method/field. If the inventory exposes a getter like `get_active_weapon()`, prefer using that in `try_parry`. Update the test to use whatever real equip API exists rather than the fallback `set("primary_weapon", w)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_parry_intercept.gd`
Expected: FAIL — `try_parry` not defined.

- [ ] **Step 3: Implement `try_parry`**

Modify `src/player/player_controller.gd`. Add this method at the bottom of the file:

```gdscript
const PARRY_KNOCKBACK_SPEED: float = 40.0
const PARRY_STUN_DURATION: float = 0.25


func try_parry(attacker: Node, hit_pos: Vector2, hit_dir: Vector2) -> bool:
	var inv := get_node_or_null("PlayerInventory")
	if inv == null:
		return false
	var weapon: Weapon = null
	if inv.has_method("get_active_weapon"):
		weapon = inv.get_active_weapon()
	if weapon == null or not (weapon is MeleeWeapon):
		return false
	var melee: MeleeWeapon = weapon
	if not melee.is_parry_active():
		return false
	# Check attacker's weapon parryable flag if available.
	if attacker != null and "weapon" in attacker:
		var aw = attacker.get("weapon")
		if aw is MeleeWeapon and not aw.parryable:
			return false
	var dir := hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector2.RIGHT
	_knockback_velocity = -dir * PARRY_KNOCKBACK_SPEED
	if attacker is Node2D and "_knockback_velocity" in attacker:
		attacker._knockback_velocity = dir * PARRY_KNOCKBACK_SPEED
	if "_parry_stun_remaining" in attacker:
		attacker._parry_stun_remaining = PARRY_STUN_DURATION
	var midpoint: Vector2 = (global_position + (attacker.global_position if attacker is Node2D else hit_pos)) * 0.5
	NailClashFX.play(midpoint, dir.orthogonal())
	return true
```

Note: if `PlayerInventory` lacks `get_active_weapon`, add the simplest equivalent (look at how `WeaponManager` / equip flow surfaces the current weapon and call the same path). Don't fabricate an API — read the existing code.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_parry_intercept.gd`
Expected: PASS for `test_try_parry_returns_false_when_no_weapon` and `test_try_parry_succeeds_in_window`. The `test_try_parry_fails_for_unparryable_attacker` should also PASS.

- [ ] **Step 5: Commit**

```bash
git add src/player/player_controller.gd tests/unit/test_parry_intercept.gd
git commit -m "feat(player): add try_parry for HK-style nail clash"
```

---

### Task 7: Wire `try_parry` into enemy `MeleeWeapon` damage path

**Files:**
- Modify: `src/weapons/melee_weapon.gd`
- Test: `tests/unit/test_unparryable.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_unparryable.gd`:

```gdscript
extends GdUnitTestSuite

func test_parry_skips_damage_on_player() -> void:
	var player := auto_free(PlayerController.new())
	add_child(player)
	await get_tree().process_frame
	var pw := MeleeWeapon.new()
	var inv: PlayerInventory = player.get_node("PlayerInventory")
	if inv.has_method("equip_weapon"):
		inv.equip_weapon(pw)
	else:
		inv.set("primary_weapon", pw)
	pw.use(player)
	var hp_before: int = inv.get("health") if "health" in inv else 0

	var attacker := auto_free(Enemy.new())
	add_child(attacker)
	attacker.global_position = player.global_position + Vector2(0, 6)
	var ew := MeleeWeapon.new()
	ew.parryable = true
	attacker.weapon = ew

	ew.use(attacker)
	var hp_after: int = inv.get("health") if "health" in inv else 0
	assert_that(hp_after).is_equal(hp_before)

func test_unparryable_attacker_damages_player() -> void:
	var player := auto_free(PlayerController.new())
	add_child(player)
	await get_tree().process_frame
	var pw := MeleeWeapon.new()
	var inv: PlayerInventory = player.get_node("PlayerInventory")
	if inv.has_method("equip_weapon"):
		inv.equip_weapon(pw)
	else:
		inv.set("primary_weapon", pw)
	pw.use(player)
	var hp_before: int = inv.get("health") if "health" in inv else 0

	var attacker := auto_free(Enemy.new())
	add_child(attacker)
	attacker.global_position = player.global_position + Vector2(0, 6)
	var ew := MeleeWeapon.new()
	ew.parryable = false
	attacker.weapon = ew

	ew.use(attacker)
	var hp_after: int = inv.get("health") if "health" in inv else 0
	assert_that(hp_after).is_less(hp_before)
```

Note: if `PlayerInventory`'s health field has a different name, update both lines accordingly after reading `src/player/player_inventory.gd`.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_unparryable.gd`
Expected: FAIL — player takes damage in both cases because the parry path isn't wired up.

- [ ] **Step 3: Wire parry into `_hit_attackables_in_arc`**

Modify `src/weapons/melee_weapon.gd:116-141`. Replace the body of `_hit_attackables_in_arc` so that for each candidate the parry call runs first:

```gdscript
func _hit_attackables_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	var dmg: int = int(damage)
	if dmg <= 0:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc_angle / 2.0
	var targets: Array[Node] = []
	targets.assign(user.get_tree().get_nodes_in_group("attackable"))
	if user.is_in_group("attackable"):
		targets.append_array(user.get_tree().get_nodes_in_group("player"))
	for node in targets:
		if node == user:
			continue
		if not (node is Node2D):
			continue
		if not node.has_method("on_hit_impact"):
			continue
		var to_target: Vector2 = node.global_position - origin
		var dist: float = to_target.length()
		if dist > weapon_reach or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc_angle:
			continue
		var hit_dir: Vector2 = to_target / dist
		if node.has_method("try_parry"):
			if node.try_parry(user, node.global_position, hit_dir):
				continue
		node.on_hit_impact(node.global_position, hit_dir, dmg)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_unparryable.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/weapons/melee_weapon.gd tests/unit/test_unparryable.gd
git commit -m "feat(weapons): consult try_parry before applying melee damage"
```

---

### Task 8: Enemy parry-stun gate + cooldown extension

**Files:**
- Modify: `src/enemies/enemy.gd`
- Test: `tests/unit/test_enemy_state_machine.gd` (extend)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_state_machine.gd`:

```gdscript
func test_parry_stun_blocks_ai_tick() -> void:
	var e := auto_free(MeleeEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e._parry_stun_remaining = 0.2
	# Force state to CHASE so we'd normally see velocity change.
	e._state = Enemy.State.CHASE
	e._player_ref = self
	e.global_position = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e._process(0.05)
	# While stunned, AI should not have driven velocity toward player.
	assert_that(e.velocity).is_equal(Vector2.ZERO)
	assert_that(e._parry_stun_remaining).is_less(0.2)

func test_parry_stun_extends_cooldown() -> void:
	var e := auto_free(MeleeEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e.cooldown_duration = 0.1
	e._change_state(Enemy.State.COOLDOWN)
	e._parry_stun_remaining = 0.5
	e._process(0.05)
	# After 0.05s, normal cooldown would be ~0.05 remaining; stun should keep it >= 0.4.
	assert_that(e._state_timer).is_greater(0.3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd`
Expected: FAIL — `_parry_stun_remaining` not defined.

- [ ] **Step 3: Add stun field and gates**

Modify `src/enemies/enemy.gd`. Add the field near the other timer fields (after `var _teleport_cooldown: float = 0.0`):

```gdscript
var _parry_stun_remaining: float = 0.0
```

In `_process`, at the very top of the method (before the existing `if _teleport_cooldown > 0.0` block):

```gdscript
	if _parry_stun_remaining > 0.0:
		_parry_stun_remaining -= delta
		# Keep cooldown at least as long as the remaining stun.
		if _state == State.COOLDOWN and _state_timer < _parry_stun_remaining:
			_state_timer = _parry_stun_remaining
		velocity = Vector2.ZERO
		return
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_enemy_state_machine.gd`
Expected: PASS for the two new tests, and existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_state_machine.gd
git commit -m "feat(enemy): add parry stun gate and cooldown extension"
```

---

### Task 9: Full regression run

- [ ] **Step 1: Run the full unit test suite**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit`
Expected: all tests pass. If any fail, fix the root cause before proceeding.

- [ ] **Step 2: Manual smoke (if a dev session is available)**

Launch the game, swing into an enemy projectile (expect spark/flash, projectile gone), and swing into a melee enemy's wind-up (expect hitstop, ring, screen shake, both knocked back, enemy briefly stunned). If something feels off, return to the relevant task and tune the constant in that file (not via memory or new abstractions).

- [ ] **Step 3: Commit any tuning changes**

```bash
git add -p  # stage only intentional tuning changes
git commit -m "tune: parry & block FX timings"
```

(Skip if nothing needed tuning.)

---

## Self-review notes

- **Spec coverage:** Sections 1–5 of the spec each map to tasks: §1 → T1; projectile destruction (§2) → T2+T3+T4; nail clash + feedback (§3 + §5) → T5+T6+T7; enemy stun (§3) → T8.
- **No unhooked types:** every method (`is_swing_active`, `is_parry_active`, `try_parry`, `_destroy_projectiles_in_arc`, `_parry_stun_remaining`, `NailClashFX.play`, `ProjectileBlockFX.play`) is defined in a task before being called.
- **Inventory API caveat:** the plan flags in Tasks 6 and 7 that `PlayerInventory`'s equip/health API may use different names; the implementer must read `player_inventory.gd` and update test setup + `try_parry`'s lookup accordingly. This is the one place I'm not pre-resolving because the inventory file wasn't read during planning.
- **Cache-warm placement:** parry constants live in `player_controller.gd` next to existing knockback constants; FX timing constants live in `nail_clash_fx.gd` so tuning is colocated with the effect.
