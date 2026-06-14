# Oil Barrel & Gas Vent Props + Poisoned Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make barrel and vent props interact with the terrain simulation (oil splashes, gas clouds) and add a poisoned status effect so gas is tactically meaningful.

**Architecture:** Oil barrel is an Area2D with HP that splashes oil on hit and dumps a pool on death. Gas vent is a Node2D timer that emits gas clouds every 5 seconds. A new "poisoned" status effect is added to StatusRegistry with DoT + slow. Projectile hit detection is extended to recognize "destructible" group props.

**Tech Stack:** GDScript, Godot 4.x, existing terrain/status systems

---

### Task 1: Add `place_oil()` convenience method to TerrainSurface

**Files:**
- Modify: `src/core/terrain_surface.gd`

- [ ] **Step 1: Add `place_oil` method**

Add after the existing `place_fire` method (line 25):

```gdscript
func place_oil(world_pos: Vector2, radius: float) -> void:
	if adapter:
		adapter.place_material(world_pos, radius, MaterialRegistry.MAT_OIL)
```

- [ ] **Step 2: Commit**

```bash
git add src/core/terrain_surface.gd
git commit -m "feat: add place_oil convenience method to TerrainSurface"
```

---

### Task 2: Add "poisoned" status definition to StatusRegistry

**Files:**
- Modify: `src/autoload/status_registry.gd`
- Create: `textures/ui/status/Effect_poisoned.png` (placeholder)

- [ ] **Step 1: Create placeholder poisoned status icon**

Create a simple 16x16 green-tinted icon. Use an existing status icon as reference and tint it green, or create a minimal placeholder:

```bash
# Copy the existing "Effect_oiled.png" as a base and rename it
cp textures/ui/status/Effect_oiled.png textures/ui/status/Effect_poisoned.png
```

Note: This is a placeholder. The icon can be replaced with proper art later.

- [ ] **Step 2: Add poisoned status definition**

In `src/autoload/status_registry.gd`, in the `_register_defs()` function, add after the "bloody" entry (after line 48):

```gdscript
	_add(StatusDefScript.new(
		"poisoned", "Poisoned", Color(0.3, 0.85, 0.25, 1.0),
		0.4, 0.3, StatusDef.Category.HARMFUL, 2.0, false, 0.6,
		"res://textures/ui/status/Effect_poisoned.png"))
```

Parameters:
- decay_rate: 0.4 (decays slowly after leaving gas)
- active_threshold: 0.3 (easy to activate, slight exposure triggers it)
- category: HARMFUL
- burn_dps: 2.0 (2 damage per second while poisoned)
- blocks_movement: false
- slow_multiplier: 0.6 (60% speed while poisoned)
- icon: poisoned icon path

- [ ] **Step 3: Add MAT_GAS → "poisoned" mapping in `stain_for_material`**

In `src/autoload/status_registry.gd`, in the `stain_for_material()` method (line 112), add before the final `return ""`:

```gdscript
	if material_id == MaterialRegistry.MAT_GAS:
		return "poisoned"
```

So the method becomes:

```gdscript
func stain_for_material(material_id: int) -> String:
	if material_id == MaterialRegistry.MAT_LAVA or material_id == MaterialRegistry.MAT_EXPLODE_WAVE:
		return "on_fire"
	if material_id == MaterialRegistry.MAT_WATER:
		return "wet"
	if material_id == MaterialRegistry.MAT_OIL:
		return "oiled"
	if material_id == MaterialRegistry.MAT_BLOOD:
		return "bloody"
	if material_id == MaterialRegistry.MAT_GAS:
		return "poisoned"
	return ""
```

- [ ] **Step 4: Commit**

```bash
git add src/autoload/status_registry.gd textures/ui/status/Effect_poisoned.png
git commit -m "feat: add poisoned status effect and gas→poisoned mapping"
```

---

### Task 3: Create the Oil Barrel script

**Files:**
- Create: `src/props/oil_barrel.gd`

- [ ] **Step 1: Write the oil barrel script**

Create `src/props/oil_barrel.gd`:

```gdscript
extends Area2D

const MAX_HP := 3
const SPLASH_RADIUS := 4.0
const DUMP_RADIUS := 8.0

var _hp: int = MAX_HP
var _dead: bool = false


func _ready() -> void:
	add_to_group("destructible")


func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if _dead:
		return
	_hp -= 1
	_flash()
	var splash_pos := impact_point if impact_point != Vector2.ZERO else global_position
	TerrainSurface.place_oil(splash_pos, SPLASH_RADIUS)
	if _hp <= 0:
		_dead = true
		TerrainSurface.place_oil(global_position, DUMP_RADIUS)
		queue_free()


func _flash() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(0.6, 0.35, 0.15, 1.0), 0.15)
```

Key design decisions:
- Extends `Area2D` so melee weapon physics queries (which use `intersect_shape` on layer 8) detect it
- In "destructible" group, NOT "attackable" group (to avoid auto-targeting and encounter tracking issues)
- `on_hit_impact` is the method called by both melee and projectile weapons
- Small splash (4px) on each hit, large dump (8px) on destruction
- `_flash()` provides visual hit feedback by briefly whitening the sprite then tweening back to barrel color

- [ ] **Step 2: Commit**

```bash
git add src/props/oil_barrel.gd
git commit -m "feat: add oil barrel prop script with splash-on-hit and dump-on-death"
```

---

### Task 4: Update barrel.tscn scene

**Files:**
- Modify: `scenes/props/barrel.tscn`

- [ ] **Step 1: Rewrite the barrel scene**

The current scene is a plain Node2D with a placeholder sprite. Change it to an Area2D with script and CollisionShape2D on layer 8 (ATTACKABLE_HIT_LAYER, bit 7 = value 128).

Replace the entire content of `scenes/props/barrel.tscn` with:

```
[gd_scene load_steps=3 format=3 uid="uid://barrel_stub_0001"]

[ext_resource type="Script" path="res://src/props/oil_barrel.gd" id="1"]

[sub_resource type="PlaceholderTexture2D" id="PlaceholderTexture2D_barrel"]
size = Vector2(16, 20)

[sub_resource type="CircleShape2D" id="CircleShape2D_barrel"]
radius = 6.0

[node name="Barrel" type="Area2D"]
collision_layer = 128
collision_mask = 0
script = ExtResource("1")

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.6, 0.35, 0.15, 1)
texture = SubResource("PlaceholderTexture2D_barrel")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_barrel")
```

Notes:
- `collision_layer = 128` puts the barrel on layer 8 (ATTACKABLE_HIT_LAYER, bit 7) so melee weapons and projectiles detect it
- `collision_mask = 0` means the barrel doesn't detect other bodies (it's a passive target)
- The CollisionShape2D radius (6px) matches the barrel's visual size
- `sub_resource` blocks must come before `node` blocks in .tscn format

- [ ] **Step 2: Commit**

```bash
git add scenes/props/barrel.tscn
git commit -m "feat: update barrel scene to Area2D with script and collision"
```

---

### Task 5: Create the Gas Vent script

**Files:**
- Create: `src/props/gas_vent.gd`

- [ ] **Step 1: Write the gas vent script**

Create `src/props/gas_vent.gd`:

```gdscript
extends Node2D

const EMIT_INTERVAL := 5.0
const EMIT_RADIUS := 6.0
const EMIT_DENSITY := 80

var _timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= EMIT_INTERVAL:
		_timer -= EMIT_INTERVAL
		TerrainSurface.place_gas(global_position, EMIT_RADIUS, EMIT_DENSITY)
```

Key design decisions:
- Simple Node2D with a periodic timer — indestructible, always active
- Uses `TerrainSurface.place_gas()` which delegates to the GPU simulation
- No collision shape needed (not hittable, gas is the hazard)

- [ ] **Step 2: Commit**

```bash
git add src/props/gas_vent.gd
git commit -m "feat: add gas vent prop script with periodic emission"
```

---

### Task 6: Update vent.tscn scene

**Files:**
- Modify: `scenes/props/vent.tscn`

- [ ] **Step 1: Rewrite the vent scene**

Add the gas_vent.gd script to the existing scene. The vent stays as a plain Node2D (no collision needed).

Replace the entire content of `scenes/props/vent.tscn` with:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://src/props/gas_vent.gd" id="1"]

[sub_resource type="PlaceholderTexture2D" id="PlaceholderTexture2D_vent"]
size = Vector2(20, 20)

[node name="Vent" type="Node2D"]
script = ExtResource("1")

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.4, 0.4, 0.5, 1)
texture = SubResource("PlaceholderTexture2D_vent")
```

- [ ] **Step 2: Commit**

```bash
git add scenes/props/vent.tscn
git commit -m "feat: update vent scene with gas_vent script"
```

---

### Task 7: Extend Projectile hit detection for destructible props

**Files:**
- Modify: `src/weapons/projectile.gd`

The barrel is in "destructible" group, not "attackable". Player projectiles currently only hit "attackable" group members and StaticBody2D. We need to add handling for "destructible" group.

- [ ] **Step 1: Add destructible group check in `_handle_hit`**

In `src/weapons/projectile.gd`, in the `_handle_hit` method (around line 56), after the enemy projectile block (line 72, `return`), and before the existing player projectile hit logic (line 74), add a check for destructible props. The modified section should look like:

```gdscript
func _handle_hit(target: Node) -> void:
	if _age < collisionless_time:
		return
	if is_enemy_projectile:
		if target.is_in_group("player"):
			if target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
		elif target is StaticBody2D:
			var keep := false
			for b in behaviors:
				keep = b.on_terrain_hit(self) or keep
			if keep:
				return
			_carve_terrain()
			queue_free()
		elif target.is_in_group("destructible") and target.has_method("on_hit_impact"):
			target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
		return

	# Player projectile passing an enemy projectile: opt-in clear hook, no self death.
	if target != self and target.is_in_group("projectile") and "is_enemy_projectile" in target and target.is_enemy_projectile:
		for b in behaviors:
			b.on_enemy_projectile_overlap(self, target)
		return

	if target.is_in_group("attackable"):
		if target != source_node and target.has_method("on_hit_impact"):
			var is_crit: bool = randf() < clampf(crit_chance, 0.0, 1.0)
			var dmg: int = int(damage * crit_multiplier) if is_crit else int(damage)
			target.on_hit_impact(global_position, direction, dmg)
			if is_crit and crit_status != "":
				var sc = target.get_node_or_null("StatusComponent")
				if sc != null:
					sc.add_stain(crit_status, CRIT_STATUS_STAIN)
			if hit_status != "":
				var hs = target.get_node_or_null("StatusComponent")
				if hs != null:
					hs.add_stain(hit_status, HIT_STATUS_STAIN)
			var keep_enemy := false
			for b in behaviors:
				keep_enemy = b.on_enemy_hit(self, target) or keep_enemy
			if not keep_enemy:
				queue_free()
	elif target.is_in_group("destructible") and target.has_method("on_hit_impact"):
		target.on_hit_impact(global_position, direction, int(damage))
		queue_free()
	elif target is StaticBody2D:
		var keep_terrain := false
		for b in behaviors:
			keep_terrain = b.on_terrain_hit(self) or keep_terrain
		if keep_terrain:
			return
		_carve_terrain()
		queue_free()
```

Key changes:
1. **Enemy projectile path**: Added `elif target.is_in_group("destructible")` check after the StaticBody2D check. Enemy projectiles now also destroy barrels before hitting terrain.
2. **Player projectile path**: Added `elif target.is_in_group("destructible")` check between "attackable" and StaticBody2D. Player projectiles now hit destructible props.

- [ ] **Step 2: Commit**

```bash
git add src/weapons/projectile.gd
git commit -m "feat: extend projectile hit detection for destructible props"
```

---

### Task 8: Write tests

**Files:**
- Create: `tests/unit/test_oil_barrel.gd`
- Create: `tests/unit/test_gas_vent.gd`
- Create: `tests/unit/test_poisoned_status.gd`

- [ ] **Step 1: Write poisoned status test**

Create `tests/unit/test_poisoned_status.gd`:

```gdscript
extends GdUnitTestSuite

const StatusRegistryScript := preload("res://src/autoload/status_registry.gd")


func test_poisoned_status_exists() -> void:
	var def := StatusRegistry.get_def("poisoned")
	assert_not_null(def)
	assert_eq(def.display_name, "Poisoned")
	assert_eq(def.category, StatusRegistryScript.StatusDef.Category.HARMFUL)


func test_poisoned_properties() -> void:
	var def := StatusRegistry.get_def("poisoned")
	assert_eq(def.decay_rate, 0.4)
	assert_eq(def.active_threshold, 0.3)
	assert_eq(def.burn_dps, 2.0)
	assert_eq(def.blocks_movement, false)
	assert_eq(def.slow_multiplier, 0.6)


func test_gas_material_maps_to_poisoned() -> void:
	var result := StatusRegistry.stain_for_material(MaterialRegistry.MAT_GAS)
	assert_eq(result, "poisoned")


func test_oil_material_maps_to_oiled() -> void:
	var result := StatusRegistry.stain_for_material(MaterialRegistry.MAT_OIL)
	assert_eq(result, "oiled")


func test_poisoned_slow_multiplier() -> void:
	var multiplier := StatusRegistry.get_slow_multiplier("poisoned")
	assert_eq(multiplier, 0.6)


func test_poisoned_burn_dps() -> void:
	var dps := StatusRegistry.get_burn_dps("poisoned")
	assert_eq(dps, 2.0)
```

- [ ] **Step 2: Write oil barrel test**

Create `tests/unit/test_oil_barrel.gd`:

```gdscript
extends GdUnitTestSuite

const OilBarrelScript := preload("res://src/props/oil_barrel.gd")


func test_barrel_in_destructible_group() -> void:
	var barrel := AutoFree(OilBarrelScript.new())
	barrel._ready()
	assert_true(barrel.is_in_group("destructible"))


func test_barrel_starts_with_max_hp() -> void:
	var barrel := AutoFree(OilBarrelScript.new())
	assert_eq(barrel._hp, 3)


func test_barrel_hit_reduces_hp() -> void:
	var barrel := AutoFree(OilBarrelScript.new())
	barrel._hp = 3
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_eq(barrel._hp, 2)
	assert_false(barrel._dead)


func test_barrel_third_hit_kills() -> void:
	var barrel := AutoFree(OilBarrelScript.new())
	barrel._hp = 3
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_eq(barrel._hp, 0)
	assert_true(barrel._dead)


func test_barrel_no_hit_after_death() -> void:
	var barrel := AutoFree(OilBarrelScript.new())
	barrel._hp = 1
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_true(barrel._dead)
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_eq(barrel._hp, 0)
```

- [ ] **Step 3: Write gas vent test**

Create `tests/unit/test_gas_vent.gd`:

```gdscript
extends GdUnitTestSuite

const GasVentScript := preload("res://src/props/gas_vent.gd")


func test_vent_timer_starts_at_zero() -> void:
	var vent := AutoFree(GasVentScript.new())
	assert_eq(vent._timer, 0.0)


func test_vent_emits_after_interval() -> void:
	var vent := AutoFree(GasVentScript.new())
	vent._timer = 4.99
	vent._process(0.01)
	# Timer should have reached threshold and reset
	# After resetting, _timer should be approximately 0
	assert_lt(vent._timer, 1.0)


func test_vent_timer_resets_on_emit() -> void:
	var vent := AutoFree(GasVentScript.new())
	vent._timer = 5.0
	vent._process(0.0)
	assert_lt(vent._timer, 0.01)
```

- [ ] **Step 4: Run the tests**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_poisoned_status.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_oil_barrel.gd && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_gas_vent.gd
```

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_poisoned_status.gd tests/unit/test_oil_barrel.gd tests/unit/test_gas_vent.gd
git commit -m "test: add tests for poisoned status, oil barrel, and gas vent"
```

---

### Task 9: Integration test — run existing test suite

**Files:** None (verification only)

- [ ] **Step 1: Run all existing tests to verify no regressions**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/
```

Verify all tests pass. If any fail, investigate and fix before proceeding.

- [ ] **Step 2: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: regressions from oil barrel/gas vent implementation"
```