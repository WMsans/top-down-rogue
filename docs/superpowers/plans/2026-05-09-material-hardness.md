# Material Hardness & Carve Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hardness to materials so melee swings and projectiles carve less area in hard materials (stone) and more in soft ones (dirt), with material-specific impact particles and sounds.

**Architecture:** A new `hardness: float` field in `MaterialDef` feeds into the existing carve pipeline. `clear_and_push_materials_in_arc` gets a `damage` parameter; each cell computes its effective carve radius as `base_radius * clamp(damage/(damage+hardness), 0.1, 1.0)`. A new `TerrainImpact` autoload maps material_id to particle colors and sounds. Changes cascade through TerrainSurface→WorldManager→TerrainModifier delegation chain.

**Tech Stack:** Godot 4.6 GDScript, GdUnit4 test framework, existing GPU terrain texture pipeline

---

### Task 1: Add hardness to MaterialDef

**Files:**
- Modify: `src/autoload/material_registry.gd`

- [ ] **Step 1: Add hardness field and update _init()**

In `material_registry.gd`, add `hardness: float` to the `MaterialDef` inner class and update the `_init()` signature. Replace lines 4-41 (the `MaterialDef` class) with:

```gdscript
class MaterialDef:
	var id: int
	var name: String
	var texture_path: String
	var flammable: bool
	var ignition_temp: int
	var burn_health: int
	var has_collider: bool
	var has_wall_extension: bool
	var tint_color: Color
	var fluid: bool
	var damage: int
	var glow: float
	var hardness: float

	func _init(
		p_name: String,
		p_texture_path: String,
		p_flammable: bool,
		p_ignition_temp: int,
		p_burn_health: int,
		p_has_collider: bool,
		p_has_wall_extension: bool,
		p_tint_color: Color = Color(0, 0, 0, 0),
		p_fluid: bool = false,
		p_damage: int = 0,
		p_glow: float = 1.0,
		p_hardness: float = 0.0
	):
		name = p_name
		texture_path = p_texture_path
		flammable = p_flammable
		ignition_temp = p_ignition_temp
		burn_health = p_burn_health
		has_collider = p_has_collider
		has_wall_extension = p_has_wall_extension
		tint_color = p_tint_color
		fluid = p_fluid
		damage = p_damage
		glow = p_glow
		hardness = p_hardness
```

- [ ] **Step 2: Set hardness values for solid materials**

Replace the material instantiation lines in `_init_materials()` that create DIRT, WOOD, COAL, ICE, and STONE. Replace lines 106-137 with:

```gdscript
	var mat_dirt := MaterialDef.new(
		"DIRT", "res://textures/Environments/Walls/dirt.png",
		false, 0, 0,
		true, true,
		Color(0.45, 0.32, 0.18, 1.0),
		false, 0, 1.0,
		0.5
	)
	mat_dirt.id = materials.size()
	materials.append(mat_dirt)
	MAT_DIRT = mat_dirt.id

	var mat_coal := MaterialDef.new(
		"COAL", "res://textures/Environments/Walls/coal.png",
		true, 220, 200,
		true, true,
		Color(0.12, 0.12, 0.14, 1.0),
		false,
		0,
		20.0,
		3.0
	)
	mat_coal.id = materials.size()
	materials.append(mat_coal)
	MAT_COAL = mat_coal.id

	var mat_ice := MaterialDef.new(
		"ICE", "res://textures/Environments/Walls/ice.png",
		false, 0, 0,
		true, true,
		Color(0.7, 0.85, 0.95, 1.0),
		false, 0, 1.0,
		4.0
	)
	mat_ice.id = materials.size()
	materials.append(mat_ice)
	MAT_ICE = mat_ice.id
```

The WOOD and STONE materials must also be updated to pass their hardness values. WOOD already has matching params — add `, 2.0` before the closing paren. STONE needs the same. Replace lines 66-80:

```gdscript
	var mat_wood := MaterialDef.new(
		"WOOD", "res://textures/Environments/Walls/plank.png",
		true, 180, 255, true, true,
		Color(0, 0, 0, 0), false, 0, 1.0,
		2.0
	)
	mat_wood.id = materials.size()
	materials.append(mat_wood)
	MAT_WOOD = mat_wood.id
	
	var mat_stone := MaterialDef.new(
		"STONE", "res://textures/Environments/Walls/stone.png",
		false, 0, 0, true, true,
		Color(0, 0, 0, 0), false, 0, 1.0,
		5.0
	)
	mat_stone.id = materials.size()
	materials.append(mat_stone)
	MAT_STONE = mat_stone.id
```

- [ ] **Step 3: Add get_hardness() accessor**

Append after the existing `get_glow()` function at the end of file (after line 196):

```gdscript
func get_hardness(material_id: int) -> float:
	if material_id < 0 or material_id >= materials.size():
		return 1.0
	return materials[material_id].hardness
```

- [ ] **Step 4: Commit**

```bash
git add src/autoload/material_registry.gd
git commit -m "feat: add hardness field to MaterialDef with per-material values"
```

---

### Task 2: Write unit test for hardness values and carve formula

**Files:**
- Create: `tests/unit/test_material_hardness.gd`

- [ ] **Step 1: Write the test file**

```gdscript
extends GdUnitTestSuite

func test_hardness_values() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hardness(registry.MAT_AIR)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_GAS)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_LAVA)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_WATER)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_DIRT)).is_equal(0.5)
	assert_that(registry.get_hardness(registry.MAT_WOOD)).is_equal(2.0)
	assert_that(registry.get_hardness(registry.MAT_COAL)).is_equal(3.0)
	assert_that(registry.get_hardness(registry.MAT_ICE)).is_equal(4.0)
	assert_that(registry.get_hardness(registry.MAT_STONE)).is_equal(5.0)

func test_hardness_unknown_material() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hardness(-1)).is_equal(1.0)
	assert_that(registry.get_hardness(999)).is_equal(1.0)

func test_carve_scale_formula() -> void:
	# formula: clamp(damage / (damage + hardness), 0.1, 1.0)
	assert_float(clampf(5.0 / (5.0 + 0.5), 0.1, 1.0)).is_equal(0.90909).within(0.01)
	assert_float(clampf(5.0 / (5.0 + 2.0), 0.1, 1.0)).is_equal(0.71428).within(0.01)
	assert_float(clampf(5.0 / (5.0 + 5.0), 0.1, 1.0)).is_equal(0.5).within(0.01)
	assert_float(clampf(1.0 / (1.0 + 5.0), 0.1, 1.0)).is_equal(0.16666).within(0.01)
	assert_float(clampf(0.1 / (0.1 + 5.0), 0.1, 1.0)).is_equal(0.01960).within(0.01)
	# at the 0.1 clamp floor, 0.0196 < 0.1 so result is 0.1
	assert_float(clampf(maxf(0.0, 0.1) / (maxf(0.0, 0.1) + 5.0), 0.1, 1.0)).is_equal(0.1).within(0.01)
	# high damage vs low hardness produces near 1.0
	assert_float(clampf(100.0 / (100.0 + 0.5), 0.1, 1.0)).is_equal(0.99502).within(0.01)
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_material_hardness.gd`
Expected: All 3 tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_material_hardness.gd
git commit -m "test: add material hardness value and carve formula tests"
```

---

### Task 3: Add damage parameter through carve delegation chain

**Files:**
- Modify: `src/core/terrain_modifier.gd:260-268` (signature)
- Modify: `src/core/terrain_modifier.gd:269-356` (per-cell hardness scaling)
- Modify: `src/core/world_manager.gd:172-173` (delegate)
- Modify: `src/core/terrain_surface.gd:25-27` (delegate)

- [ ] **Step 1: Add damage param to TerrainModifier.clear_and_push_materials_in_arc and apply hardness scaling**

Replace the function signature (line 260) and the per-cell loop logic (lines 269-315) in `terrain_modifier.gd`. The key change: calculate `effective_radius` per cell using hardness.

Replace lines 260-315 with:

```gdscript
func clear_and_push_materials_in_arc(
	origin: Vector2,
	direction: Vector2,
	radius: float,
	arc_angle: float,
	push_speed: float,
	edge_fraction: float,
	materials: Array[int],
	damage: float = -1.0
) -> void:
	var origin_int := Vector2i(int(origin.x), int(origin.y))
	var r_int := int(ceil(radius))
	var half_arc := arc_angle / 2.0
	var dir_angle := direction.angle()
	var start_angle := dir_angle - half_arc
	var end_angle := dir_angle + half_arc
	var inner_r := radius * (1.0 - edge_fraction)
	var inner_r_sq := int(inner_r) * int(inner_r)
	var r_sq := r_int * r_int
	var apply_hardness := damage >= 0.0
	var safe_damage := maxf(damage, 0.1)

	var affected: Dictionary = {}

	for dx in range(-r_int, r_int + 1):
		for dy in range(-r_int, r_int + 1):
			var dist_sq := dx * dx + dy * dy
			if dist_sq > r_sq:
				continue

			var pixel_angle := atan2(float(dy), float(dx))
			var delta_start := pixel_angle - start_angle
			while delta_start > PI:
				delta_start -= TAU
			while delta_start < -PI:
				delta_start += TAU
			var delta_end := pixel_angle - end_angle
			while delta_end > PI:
				delta_end -= TAU
			while delta_end < -PI:
				delta_end += TAU

			if delta_start < 0.0 or delta_end > 0.0:
				continue

			var wx := origin_int.x + dx
			var wy := origin_int.y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []

			if dist_sq >= inner_r_sq:
				affected[chunk_coord].append([local, Vector2(float(dx), float(dy)).normalized(), false, dist_sq])
			else:
				affected[chunk_coord].append([local, Vector2.ZERO, true, dist_sq])
```

- [ ] **Step 2: Apply per-cell hardness scaling in the texture update loop**

Replace the texture processing loop (lines 319-356) with hardness-aware clearing:

```gdscript
	if affected.is_empty():
		return

	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var do_clear: bool = entry[2]
			var dist_sq: int = entry[3]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material: int = data[idx]

			var is_target := false
			for mat_id in materials:
				if material == mat_id:
					is_target = true
					break
			if not is_target:
				continue

			if do_clear:
				if apply_hardness:
					var hardness: float = MaterialRegistry.get_hardness(material)
					var scale: float = clampf(safe_damage / (safe_damage + hardness), 0.1, 1.0)
					var effective_radius: float = radius * scale
					if dist_sq > int(effective_radius) * int(effective_radius):
						continue
				data[idx] = MaterialRegistry.MAT_AIR
				data[idx + 1] = 0
				data[idx + 2] = 0
				data[idx + 3] = 136
			else:
				var push_vx := int(round(push_dir.x * push_speed / 60.0))
				var push_vy := int(round(push_dir.y * push_speed / 60.0))
				var vx_encoded := clampi(push_vx + 8, 0, 15)
				var vy_encoded := clampi(push_vy + 8, 0, 15)
				data[idx + 3] = (vx_encoded << 4) | vy_encoded
			modified = true

		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)

	if terrain_physical:
		var affected_rect := Rect2i(origin_int.x - r_int, origin_int.y - r_int, r_int * 2 + 1, r_int * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)
```

- [ ] **Step 3: Update WorldManager delegate**

Replace line 172-173 in `world_manager.gd`:

```gdscript
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int], damage: float = -1.0) -> void:
	terrain_modifier.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)
```

- [ ] **Step 4: Update TerrainSurface delegate**

Replace line 25-27 in `terrain_surface.gd`:

```gdscript
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array, damage: float = -1.0) -> void:
	if adapter:
		adapter.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)
```

- [ ] **Step 5: Commit**

```bash
git add src/core/terrain_modifier.gd src/core/world_manager.gd src/core/terrain_surface.gd
git commit -m "feat: add damage-based hardness scaling to clear_and_push_materials_in_arc"
```

---

### Task 4: Update MeleeWeapon to pass damage and target solids

**Files:**
- Modify: `src/weapons/melee_weapon.gd:95-101`

- [ ] **Step 1: Pass damage to terrain carve and target solids instead of just fluids**

Replace the `_use_impl()` function (lines 95-101) in `melee_weapon.gd`:

```gdscript
func _use_impl(user: Node) -> void:
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	# Push fluids (gas, lava) — existing behavior, no hardness
	var fluids: Array[int] = MaterialRegistry.get_fluids()
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, push_speed, 0.25, fluids)
	# Carve solids (wall materials) — new, with hardness scaling
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, 0.0, 0.0, solids, damage)
	_hit_attackables_in_arc(user, pos, direction)
```

Note: `push_speed=0.0` and `edge_fraction=0.0` for the solid carve pass because we only want to clear (erase) solids, not push them. Solids are replaced with AIR in-place.

- [ ] **Step 2: Commit**

```bash
git add src/weapons/melee_weapon.gd
git commit -m "feat: melee weapons now carve solids with hardness-scaled radius"
```

---

### Task 5: Add projectile terrain carve with hardness

**Files:**
- Modify: `src/weapons/projectile.gd:30-52`

- [ ] **Step 1: Replace StaticBody2D destroy with terrain carve**

Replace the `_handle_hit` function in `projectile.gd` (lines 38-52):

```gdscript
func _handle_hit(target: Node) -> void:
	if is_enemy_projectile:
		if target.is_in_group("player"):
			if target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
		elif target is StaticBody2D:
			_carve_terrain()
			queue_free()
	else:
		if target.is_in_group("attackable"):
			if target != source_node and target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
				queue_free()
		elif target is StaticBody2D:
			_carve_terrain()
			queue_free()
```

- [ ] **Step 2: Add _carve_terrain helper function**

Insert the helper function somewhere in the `Projectile` class. After `_handle_hit()` (before the final `queue_free` lines were merged in, add as a new function at the end of the class):

```gdscript
func _carve_terrain() -> void:
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	TerrainSurface.clear_and_push_materials_in_arc(
		global_position, direction, 3.0, TAU, 0.0, 0.0, solids, damage
	)
```

The `TAU` arc angle creates a full-circle carve (small crater), `radius=3.0` pixels for a tiny impact crater.

- [ ] **Step 3: Commit**

```bash
git add src/weapons/projectile.gd
git commit -m "feat: projectiles carve small terrain craters with hardness scaling"
```

---

### Task 6: Create TerrainImpact autoload

**Files:**
- Create: `src/core/juice/terrain_impact.gd`

- [ ] **Step 1: Write the autoload script**

Create `src/core/juice/terrain_impact.gd`:

```gdscript
extends Node

const IMPACT_DATA := {
	MaterialRegistry.MAT_DIRT: {
		"particle_color": Color(0.45, 0.32, 0.18),
		"particle_count": 6,
	},
	MaterialRegistry.MAT_WOOD: {
		"particle_color": Color(0.55, 0.42, 0.25),
		"particle_count": 8,
	},
	MaterialRegistry.MAT_COAL: {
		"particle_color": Color(0.12, 0.12, 0.14),
		"particle_count": 8,
	},
	MaterialRegistry.MAT_ICE: {
		"particle_color": Color(0.7, 0.85, 0.95),
		"particle_count": 10,
	},
	MaterialRegistry.MAT_STONE: {
		"particle_color": Color(0.5, 0.5, 0.5),
		"particle_count": 6,
	},
}


func play_impact(world_pos: Vector2, material_id: int, intensity: float) -> void:
	var data: Dictionary = IMPACT_DATA.get(material_id, {})
	if data.is_empty():
		return
	var color: Color = data.get("particle_color", Color(0.5, 0.5, 0.5))
	var count: int = maxi(1, int(data.get("particle_count", 6) * intensity))
	for _i in range(count):
		var particle := ColorRect.new()
		particle.color = color
		particle.size = Vector2(2, 2)
		particle.position = world_pos + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
		particle.z_index = 100
		add_child(particle)
		var tween := create_tween()
		var target_pos := particle.position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
		tween.tween_property(particle, "position", target_pos, randf_range(0.15, 0.35))
		tween.parallel().tween_property(particle, "modulate:a", 0.0, randf_range(0.15, 0.35))
		tween.tween_callback(particle.queue_free)
```

- [ ] **Step 2: Register TerrainImpact in project.godot autoloads**

In `project.godot`, add after the existing TerrainSurface autoload line:

```
TerrainImpact="*res://src/core/juice/terrain_impact.gd"
```

Place it after the TerrainSurface line. The autoload section should now read (new line indicated):

```
[autoload]

MaterialRegistry="*res://src/autoload/material_registry.gd"
BiomeRegistry="*res://src/autoload/biome_registry.gd"
LevelManager="*res://src/autoload/level_manager.gd"
SceneManager="*res://src/autoload/scene_manager.gd"
ConsoleManager="*res://src/autoload/console_manager.gd"
WeaponRegistry="*res://src/autoload/weapon_registry.gd"
HitReaction="*res://src/core/juice/hit_reaction.gd"
TerrainSurface="*res://src/core/terrain_surface.gd"
TerrainImpact="*res://src/core/juice/terrain_impact.gd"
GameModeManager="*res://src/autoload/game_mode_manager.gd"
```

- [ ] **Step 3: Commit**

```bash
git add src/core/juice/terrain_impact.gd project.godot
git commit -m "feat: add TerrainImpact autoload with material-specific debris particles"
```

---

### Task 7: Wire impact feedback into melee carve

**Files:**
- Modify: `src/core/terrain_modifier.gd` (return impact data from carve)
- Modify: `src/weapons/melee_weapon.gd` (consume impact data and call TerrainImpact)

- [ ] **Step 1: Have clear_and_push_materials_in_arc return impact data**

Modify the TerrainModifier function to collect and return impact data. Change the return type from `void` to `Array` and accumulate impacts during the texture loop. Replace the function signature line and the entire function ending:

In `terrain_modifier.gd`, change line 260 from:
```gdscript
) -> void:
```
to:
```gdscript
) -> Array:
```

And add a return statement at the end of the function. After the invalidate_rect call (the last line), add:

```gdscript
	return impact_list
```

Now collect impacts during the clear loop. Inside the `if do_clear:` block (where a cell gets cleared), after setting data values, add:

```gdscript
				if apply_hardness:
					impact_list.append({
						"world_pos": Vector2(wx, wy),
						"material_id": material,
						"scale": clampf(safe_damage / (safe_damage + MaterialRegistry.get_hardness(material)), 0.1, 1.0),
					})
```

The full modified function body needs these key additions:
1. `var impact_list: Array = []` declared before the loops (after `var safe_damage` line)
2. `impact_list.append(...)` inside the clear block
3. `return impact_list` at the end

Since the function is long, here's the complete replacement for lines 260-356 in `terrain_modifier.gd`:

```gdscript
func clear_and_push_materials_in_arc(
	origin: Vector2,
	direction: Vector2,
	radius: float,
	arc_angle: float,
	push_speed: float,
	edge_fraction: float,
	materials: Array[int],
	damage: float = -1.0
) -> Array:
	var origin_int := Vector2i(int(origin.x), int(origin.y))
	var r_int := int(ceil(radius))
	var half_arc := arc_angle / 2.0
	var dir_angle := direction.angle()
	var start_angle := dir_angle - half_arc
	var end_angle := dir_angle + half_arc
	var inner_r := radius * (1.0 - edge_fraction)
	var inner_r_sq := int(inner_r) * int(inner_r)
	var r_sq := r_int * r_int
	var apply_hardness := damage >= 0.0
	var safe_damage := maxf(damage, 0.1)
	var impact_list: Array = []

	var affected: Dictionary = {}

	for dx in range(-r_int, r_int + 1):
		for dy in range(-r_int, r_int + 1):
			var dist_sq := dx * dx + dy * dy
			if dist_sq > r_sq:
				continue

			var pixel_angle := atan2(float(dy), float(dx))
			var delta_start := pixel_angle - start_angle
			while delta_start > PI:
				delta_start -= TAU
			while delta_start < -PI:
				delta_start += TAU
			var delta_end := pixel_angle - end_angle
			while delta_end > PI:
				delta_end -= TAU
			while delta_end < -PI:
				delta_end += TAU

			if delta_start < 0.0 or delta_end > 0.0:
				continue

			var wx := origin_int.x + dx
			var wy := origin_int.y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []

			if dist_sq >= inner_r_sq:
				affected[chunk_coord].append([local, Vector2(float(dx), float(dy)).normalized(), false, dist_sq])
			else:
				affected[chunk_coord].append([local, Vector2.ZERO, true, dist_sq])

	if affected.is_empty():
		return impact_list

	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var push_dir: Vector2 = entry[1]
			var do_clear: bool = entry[2]
			var dist_sq: int = entry[3]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material: int = data[idx]

			var is_target := false
			for mat_id in materials:
				if material == mat_id:
					is_target = true
					break
			if not is_target:
				continue

			if do_clear:
				if apply_hardness:
					var hardness: float = MaterialRegistry.get_hardness(material)
					var scale: float = clampf(safe_damage / (safe_damage + hardness), 0.1, 1.0)
					var effective_radius: float = radius * scale
					if dist_sq > int(effective_radius) * int(effective_radius):
						continue
					impact_list.append({
						"world_pos": Vector2(wx, wy),
						"material_id": material,
						"scale": scale,
					})
				data[idx] = MaterialRegistry.MAT_AIR
				data[idx + 1] = 0
				data[idx + 2] = 0
				data[idx + 3] = 136
			else:
				var push_vx := int(round(push_dir.x * push_speed / 60.0))
				var push_vy := int(round(push_dir.y * push_speed / 60.0))
				var vx_encoded := clampi(push_vx + 8, 0, 15)
				var vy_encoded := clampi(push_vy + 8, 0, 15)
				data[idx + 3] = (vx_encoded << 4) | vy_encoded
			modified = true

		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)

	if terrain_physical:
		var affected_rect := Rect2i(origin_int.x - r_int, origin_int.y - r_int, r_int * 2 + 1, r_int * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)

	return impact_list
```

Note: The `wx` and `wy` variables used in the `impact_list.append()` inside the `for chunk_coord in affected` loop must be reconstructed. The `wx` and `wy` are not accessible inside the texture loop. We need to rebuild them from the pixel position and chunk coordinate.

Fix the impact_list.append line inside the texture update loop to reconstruct world coordinates:

```gdscript
					var world_wx := chunk_coord.x * CHUNK_SIZE + pixel_pos.x
					var world_wy := chunk_coord.y * CHUNK_SIZE + pixel_pos.y
					impact_list.append({
						"world_pos": Vector2(world_wx, world_wy),
						"material_id": material,
						"scale": scale,
					})
```

- [ ] **Step 2: Update WorldManager and TerrainSurface return types**

In `world_manager.gd`, change the `clear_and_push_materials_in_arc` return type from `void` to `Array` and return the result:

```gdscript
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array[int], damage: float = -1.0) -> Array:
	return terrain_modifier.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)
```

In `terrain_surface.gd`, same change:

```gdscript
func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array, damage: float = -1.0) -> Array:
	if adapter:
		return adapter.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials, damage)
	return []
```

- [ ] **Step 3: Call TerrainImpact from MeleeWeapon solid carve**

Update the solid carve call in `melee_weapon.gd` `_use_impl()` to capture the result and trigger impacts:

```gdscript
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	var impacts: Array = TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, 0.0, 0.0, solids, damage)
	for impact in impacts:
		TerrainImpact.play_impact(impact["world_pos"], impact["material_id"], impact["scale"])
```

- [ ] **Step 4: Commit**

```bash
git add src/core/terrain_modifier.gd src/core/world_manager.gd src/core/terrain_surface.gd src/weapons/melee_weapon.gd
git commit -m "feat: wire TerrainImpact feedback into melee solid carving"
```

---

### Task 8: Wire impact feedback into projectile carve

**Files:**
- Modify: `src/weapons/projectile.gd`

- [ ] **Step 1: Update _carve_terrain to trigger TerrainImpact**

Replace the `_carve_terrain()` function in `projectile.gd` to capture and forward impact data:

```gdscript
func _carve_terrain() -> void:
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	var impacts: Array = TerrainSurface.clear_and_push_materials_in_arc(
		global_position, direction, 3.0, TAU, 0.0, 0.0, solids, damage
	)
	for impact in impacts:
		TerrainImpact.play_impact(impact["world_pos"], impact["material_id"], impact["scale"])
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/projectile.gd
git commit -m "feat: wire TerrainImpact feedback into projectile terrain carving"
```

---

### Task 9: Integration test — verify hardness carve scaling works end-to-end

**Files:**
- Create: `tests/unit/test_material_hardness.gd` (append to existing test)

- [ ] **Step 1: Add integration-level test assertions**

Append to `tests/unit/test_material_hardness.gd`:

```gdscript
func test_carve_scale_for_known_weapons() -> void:
	# Base melee weapon: damage=5.0
	# Dirt (0.5): 5/(5+0.5) = 0.909 → ~91% radius
	var dirt_scale := clampf(5.0 / (5.0 + 0.5), 0.1, 1.0)
	assert_float(dirt_scale).is_greater(0.9)
	# Stone (5.0): 5/(5+5) = 0.5 → 50% radius
	var stone_scale := clampf(5.0 / (5.0 + 5.0), 0.1, 1.0)
	assert_float(stone_scale).is_equal(0.5).within(0.01)
	# Stone should be less than dirt
	assert_that(stone_scale).is_less(dirt_scale)

func test_carve_scale_preserves_ordering() -> void:
	var damage := 5.0
	var dirts := clampf(damage / (damage + 0.5), 0.1, 1.0)
	var woods := clampf(damage / (damage + 2.0), 0.1, 1.0)
	var coals := clampf(damage / (damage + 3.0), 0.1, 1.0)
	var ices := clampf(damage / (damage + 4.0), 0.1, 1.0)
	var stones := clampf(damage / (damage + 5.0), 0.1, 1.0)
	assert_that(dirts).is_greater(woods)
	assert_that(woods).is_greater(coals)
	assert_that(coals).is_greater(ices)
	assert_that(ices).is_greater(stones)
```

- [ ] **Step 2: Run all hardness tests**

Run: `godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_material_hardness.gd`
Expected: All 5 tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_material_hardness.gd
git commit -m "test: add carve scale ordering integration assertions"
```

---

### Task 10: Final verification

- [ ] **Step 1: Run full test suite**

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/
```
Expected: All existing tests still pass, new hardness tests pass.

- [ ] **Step 2: Run Godot editor lint check**

Open `project.godot` in Godot editor and verify no script errors appear in the debugger for: `material_registry.gd`, `terrain_modifier.gd`, `terrain_impact.gd`, `terrain_surface.gd`, `world_manager.gd`, `melee_weapon.gd`, `projectile.gd`.

- [ ] **Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final verification fixes for material hardness"
```
