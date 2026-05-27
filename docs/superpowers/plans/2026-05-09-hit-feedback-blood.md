# Hit Feedback & Blood Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-enemy hit-flash/squash feedback and terrain-fluid blood splatter that bursts outward on every hit.

**Architecture:** Wire the orphaned `_on_hit()` call inside `Enemy.hit()`, define a new `MAT_BLOOD` fluid material in `MaterialRegistry` (no damage, no glow, red tint), create a `blood.glslinc` shader for blood advection (lava-like but without temperature), add `place_blood()` API through the `TerrainSurface → WorldManager → TerrainModifier` chain with per-pixel radial velocity, and hook the blood spawn into `Enemy.on_hit_impact()`.

**Tech Stack:** GDScript (Godot 4.6), GLSL compute shaders, RGBA8 terrain pixel format

---

### Task 1: Add MAT_BLOOD to MaterialRegistry

**Files:**
- Modify: `src/autoload/material_registry.gd`

- [ ] **Step 1: Add MAT_BLOOD variable declaration**

In `src/autoload/material_registry.gd`, add after `var MAT_WATER: int` (line 53):

```gdscript
var MAT_BLOOD: int
```

- [ ] **Step 2: Add BLOOD MaterialDef in _init_materials()**

In `src/autoload/material_registry.gd`, add after the `MAT_WATER` entry (after line 147 — after the water `materials.append(mat_water)` block):

```gdscript
	var mat_blood := MaterialDef.new(
		"BLOOD", "",
		false, 0, 0,
		false, false,
		Color(0.8, 0.05, 0.05, 1.0),
		true,
		0,
		1.0
	)
	mat_blood.id = materials.size()
	materials.append(mat_blood)
	MAT_BLOOD = mat_blood.id
```

- [ ] **Step 3: Commit**

```bash
git add src/autoload/material_registry.gd
git commit -m "add MAT_BLOOD material definition to registry"
```

---

### Task 2: Regenerate material GLSL files

**Files:**
- Regenerate: `shaders/generated/materials.glslinc`
- Regenerate: `shaders/generated/materials.gdshaderinc`

- [ ] **Step 1: Run the generator tool**

```bash
godot --headless --script res://tools/generate_material_glsl.gd
```

Expected: prints "Generated shaders/generated/materials.glslinc" and "Generated shaders/generated/materials.gdshaderinc"

- [ ] **Step 2: Verify MAT_BLOOD constant exists in generated output**

Run: `grep "MAT_BLOOD" shaders/generated/materials.glslinc`

Expected: line like `const int MAT_BLOOD = 10;`

- [ ] **Step 3: Commit**

```bash
git add shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "regenerate material GLSL with MAT_BLOOD"
```

---

### Task 3: Create blood fluid simulation shader

**Files:**
- Create: `shaders/include/sim/blood.glslinc`

- [ ] **Step 1: Create the blood simulation shader include**

Create `shaders/include/sim/blood.glslinc`:

```glsl
int get_density_blood(vec4 p) { return int(round(p.g * 255.0)); }

ivec2 unpack_velocity_blood(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_blood(int density, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_BLOOD) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		0.0,
		float(a) / 255.0
	);
}

bool is_solid_for_blood(int mat) {
	return mat != MAT_AIR && mat != MAT_BLOOD;
}

void blood_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
	int material = get_material(pixel);

	int n_mat_up    = get_material(n_up);
	int n_mat_down  = get_material(n_down);
	int n_mat_left  = get_material(n_left);
	int n_mat_right = get_material(n_right);

	bool any_blood_neighbor =
		n_mat_up == MAT_BLOOD || n_mat_down == MAT_BLOOD ||
		n_mat_left == MAT_BLOOD || n_mat_right == MAT_BLOOD;

	if (material == MAT_AIR && !any_blood_neighbor) {
		return;
	}

	int density = (material == MAT_BLOOD) ? get_density_blood(pixel) : 0;
	ivec2 vel = (material == MAT_BLOOD) ? unpack_velocity_blood(pixel) : ivec2(0);

	int comp_up    = max(0, -vel.y);
	int comp_down  = max(0,  vel.y);
	int comp_left  = max(0, -vel.x);
	int comp_right = max(0,  vel.x);

	if (is_solid_for_blood(n_mat_up))    comp_up    = 0;
	if (is_solid_for_blood(n_mat_down))  comp_down  = 0;
	if (is_solid_for_blood(n_mat_left))  comp_left  = 0;
	if (is_solid_for_blood(n_mat_right)) comp_right = 0;

	int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 1u);
	int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 2u);
	int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 3u);
	int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 4u);

	int total_out = out_up + out_down + out_left + out_right;
	int max_outflow = min(density, max(1, density / 2));
	if (total_out > max_outflow) {
		out_up    = out_up    * max_outflow / max(1, total_out);
		out_down  = out_down  * max_outflow / max(1, total_out);
		out_left  = out_left  * max_outflow / max(1, total_out);
		out_right = out_right * max_outflow / max(1, total_out);
		total_out = out_up + out_down + out_left + out_right;
	}

	int in_up = 0, in_down = 0, in_left = 0, in_right = 0;
	ivec2 vin_up = ivec2(0), vin_down = ivec2(0), vin_left = ivec2(0), vin_right = ivec2(0);

	if (n_mat_up == MAT_BLOOD) {
		int dN = get_density_blood(n_up);
		ivec2 vN = unpack_velocity_blood(n_up);
		in_up = stochastic_div(dN * max(0, vN.y), V_MAX_OUTFLOW, pos, 5u);
		vin_up = vN;
	}
	if (n_mat_down == MAT_BLOOD) {
		int dN = get_density_blood(n_down);
		ivec2 vN = unpack_velocity_blood(n_down);
		in_down = stochastic_div(dN * max(0, -vN.y), V_MAX_OUTFLOW, pos, 6u);
		vin_down = vN;
	}
	if (n_mat_left == MAT_BLOOD) {
		int dN = get_density_blood(n_left);
		ivec2 vN = unpack_velocity_blood(n_left);
		in_left = stochastic_div(dN * max(0, vN.x), V_MAX_OUTFLOW, pos, 7u);
		vin_left = vN;
	}
	if (n_mat_right == MAT_BLOOD) {
		int dN = get_density_blood(n_right);
		ivec2 vN = unpack_velocity_blood(n_right);
		in_right = stochastic_div(dN * max(0, -vN.x), V_MAX_OUTFLOW, pos, 8u);
		vin_right = vN;
	}

	int total_in = in_up + in_down + in_left + in_right;

	if (is_solid_for_blood(n_mat_up)    && vel.y < 0) vel.y = -vel.y;
	if (is_solid_for_blood(n_mat_down)  && vel.y > 0) vel.y = -vel.y;
	if (is_solid_for_blood(n_mat_left)  && vel.x < 0) vel.x = -vel.x;
	if (is_solid_for_blood(n_mat_right) && vel.x > 0) vel.x = -vel.x;

	int new_density = clamp(density - total_out + total_in, 0, 255);

	int stayed = max(0, density - total_out);
	int weight = max(1, stayed + total_in);
	ivec2 vsum = vel * stayed
	           + vin_up * in_up + vin_down * in_down
	           + vin_left * in_left + vin_right * in_right;
	ivec2 new_vel = vsum / weight;
	int new_vel_mag = max(abs(new_vel.x), abs(new_vel.y));
	if (new_vel_mag > 1) {
		new_vel = (new_vel * 15) / 16;
	}
	new_vel = clamp(new_vel, ivec2(-8), ivec2(7));

	if (material == MAT_AIR) {
		if (total_in >= THRESHOLD_BECOME_BLOOD) {
			ivec2 inflow_vel = ivec2(0);
			if (total_in > 0) {
				inflow_vel = (vin_up * in_up + vin_down * in_down + vin_left * in_left + vin_right * in_right) / total_in;
				inflow_vel = (inflow_vel * 15) / 16;
				inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
			}
			imageStore(chunk_tex, pos, pack_blood(total_in, inflow_vel));
			return;
		}
		return;
	}

	if (new_density < THRESHOLD_DISSIPATE) {
		imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
		return;
	}
	imageStore(chunk_tex, pos, pack_blood(new_density, new_vel));
}

bool simulate_blood(ivec2 pos, inout vec4 pixel, inout int material,
                    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	if (material != MAT_BLOOD && material != MAT_AIR) return false;
	blood_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
	if (material == MAT_BLOOD) return true;
	pixel = imageLoad(chunk_tex, pos);
	material = get_material(pixel);
	return material == MAT_BLOOD;
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/sim/blood.glslinc
git commit -m "add blood fluid simulation shader (advection, no temperature)"
```

---

### Task 4: Add THRESHOLD_BECOME_BLOOD to common.glslinc

**Files:**
- Modify: `shaders/include/sim/common.glslinc`

- [ ] **Step 1: Add the threshold constant**

In `shaders/include/sim/common.glslinc`, after `const int THRESHOLD_BECOME_LAVA = 1;` (line 8), add:

```glsl
const int THRESHOLD_BECOME_BLOOD = 1;
```

The full block should read:
```glsl
const int THRESHOLD_BECOME_GAS = 1;
const int THRESHOLD_BECOME_LAVA = 1;
const int THRESHOLD_BECOME_BLOOD = 1;
const int THRESHOLD_DISSIPATE = 1;
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/sim/common.glslinc
git commit -m "add THRESHOLD_BECOME_BLOOD constant to sim common"
```

---

### Task 5: Wire blood into simulation.glsl

**Files:**
- Modify: `shaders/compute/simulation.glsl`

- [ ] **Step 1: Add blood include**

In `shaders/compute/simulation.glsl`, after `#include "res://shaders/include/sim/lava.glslinc"` (line 37), add:

```glsl
#include "res://shaders/include/sim/blood.glslinc"
```

- [ ] **Step 2: Add simulate_blood dispatch call**

In `shaders/compute/simulation.glsl`, after `if (simulate_lava(...))` (line 57), add:

```glsl
	if (simulate_blood(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
```

The final fluid dispatch section (lines 55-58) should read:
```glsl
	// Fluid dispatch — each simulate_* returns true if the cell is fully processed.
	// Add new fluids here in priority order (higher priority first).
	if (simulate_lava(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_blood(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_gas(pos, pixel, material, n_up, n_down, n_left, n_right))  return;
```

- [ ] **Step 3: Verify simulation.glsl compiles**

Run: `godot --headless --quit`

Expected: No shader compilation errors.

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/simulation.glsl
git commit -m "wire blood fluid into compute simulation pipeline"
```

---

### Task 6: Add MAT_BLOOD to render_chunk.gdshader fluid check

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader`

- [ ] **Step 1: Extend the fluid overlay check**

In `shaders/visual/render_chunk.gdshader`, change line 163 from:
```glsl
	if (mat == MAT_GAS || mat == MAT_LAVA) {
```
to:
```glsl
	if (mat == MAT_GAS || mat == MAT_LAVA || mat == MAT_BLOOD) {
```

- [ ] **Step 2: Verify**

Run: `godot --headless --quit`

Expected: No shader compilation errors.

- [ ] **Step 3: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "add MAT_BLOOD to fluid overlay rendering check"
```

---

### Task 7: Add place_blood to TerrainModifier

**Files:**
- Modify: `src/core/terrain_modifier.gd`

- [ ] **Step 1: Add place_blood() implementation**

In `src/core/terrain_modifier.gd`, add after `place_lava()` (after line 93, before `place_material()` at line 96):

```gdscript
func place_blood(world_pos: Vector2, radius: float, outward_speed: float) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))
	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not world_manager.chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append([local, Vector2(float(dx), float(dy))])
	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for entry in affected[chunk_coord]:
			var pixel_pos: Vector2i = entry[0]
			var dir: Vector2 = entry[1]
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = MaterialRegistry.MAT_BLOOD
			data[idx + 1] = 200
			data[idx + 2] = 0
			var dir_normalized := dir
			if dir.length_squared() > 0.0001:
				dir_normalized = dir.normalized()
			var vel := (dir_normalized * outward_speed) / 60.0
			var vx := clampi(int(round(vel.x)) + 8, 0, 15)
			var vy := clampi(int(round(vel.y)) + 8, 0, 15)
			data[idx + 3] = (vx << 4) | vy
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)
```

- [ ] **Step 2: Commit**

```bash
git add src/core/terrain_modifier.gd
git commit -m "add place_blood with per-pixel radial velocity to TerrainModifier"
```

---

### Task 8: Add place_blood to TerrainSurface

**Files:**
- Modify: `src/core/terrain_surface.gd`

- [ ] **Step 1: Add place_blood() delegate**

In `src/core/terrain_surface.gd`, add after `place_lava()` (after line 17):

```gdscript
func place_blood(world_pos: Vector2, radius: float, outward_speed: float) -> void:
	if adapter:
		adapter.place_blood(world_pos, radius, outward_speed)
```

- [ ] **Step 2: Commit**

```bash
git add src/core/terrain_surface.gd
git commit -m "add place_blood delegate to TerrainSurface"
```

---

### Task 9: Add place_blood to WorldManager

**Files:**
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add place_blood() adapter**

In `src/core/world_manager.gd`, add after `place_lava()` (after line 165):

```gdscript
func place_blood(world_pos: Vector2, radius: float, outward_speed: float) -> void:
	terrain_modifier.place_blood(world_pos, radius, outward_speed)
```

- [ ] **Step 2: Commit**

```bash
git add src/core/world_manager.gd
git commit -m "add place_blood adapter to WorldManager"
```

---

### Task 10: Wire flash/squash + blood spawn in Enemy

**Files:**
- Modify: `src/enemies/enemy.gd`

- [ ] **Step 1: Call _on_hit() in hit()**

In `src/enemies/enemy.gd`, in the `hit()` method, add `_on_hit()` after `health_changed.emit(...)`:

The `hit()` method (lines 302-317) should read:

```gdscript
func hit(damage: int) -> void:
	if damage <= 0:
		return
	if GameModeManager.is_creative():
		damage = max_health

	health -= damage
	health_changed.emit(health, max_health)
	_on_hit()
	if health <= 0:
		_change_state(State.DEATH)
		die()
		return
	if _state != State.HURT:
		_prev_state = _state
	_state = State.HURT
	_state_timer = hurt_duration
```

The only change is adding `_on_hit()` on the line after `health_changed.emit(health, max_health)`.

- [ ] **Step 2: Spawn blood in on_hit_impact()**

In `src/enemies/enemy.gd`, in the `on_hit_impact()` method, add `TerrainSurface.place_blood()` after `HitReaction.play(spec)`:

```gdscript
	HitReaction.play(spec)

	TerrainSurface.place_blood(impact_point, 6.0, 120.0)

	if is_elite and elite_ability == EliteAbility.TELEPORT and _teleport_cooldown <= 0.0:
```

(The `TerrainSurface.place_blood(...)` line is added between `HitReaction.play(spec)` and the elite teleport check.)

- [ ] **Step 3: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "wire enemy hit flash/squash and blood terrain fluid splatter"
```

---

### Task 11: Integration verification

**Files:**
- No file changes — verification only.

- [ ] **Step 1: Launch Godot and test**

Run: `godot`

Manual test:
1. Enter the game
2. Find an enemy and hit it with a melee weapon
3. Verify: enemy sprite flashes white and squashes on hit
4. Verify: red blood fluid appears on terrain at impact point and spreads outward
5. Verify: blood dissipates over time (not permanent)
6. Verify: blood does not cause damage to the player

- [ ] **Step 2: Check for console errors**

Watch the Godot output panel for any shader or script errors during gameplay.

---

### Task 12: Final verification & commit

**Files:**
- No file changes — verification only.

- [ ] **Step 1: Run unit tests**

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
```

Expected: All tests pass (no regressions from existing tests).

- [ ] **Step 2: Final commit (if any cleanup needed)**

If any lint/format issues were found and fixed:
```bash
git add -A
git commit -m "fix: lint/format cleanup for hit feedback and blood"
```
