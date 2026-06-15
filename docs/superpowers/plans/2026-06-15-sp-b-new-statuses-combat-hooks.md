# SP-B — New Statuses & Combat Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new statuses (steam, lightning, stun), timed status model, two reaction rules, MAT_STEAM material, and four combat verbs (stun/knockback/heal/bounty) so SP-B.1 modifiers can use them.

**Architecture:** Parallel `_timed_statuses` dict in StatusComponent alongside stains; steam is stain-based; lightning and stun are flat-duration timed effects; MAT_STEAM shares gas physics via parameterized `gas_advect_pull`; knockback/stun are direct methods on entities.

**Tech Stack:** GDScript (Godot 4), GLSL compute shaders, gdUnit4 tests.

---

### Task 1: StatusDef — add `mode` and `default_duration` fields

**Files:**
- Modify: `src/status/status_def.gd`
- Test: `tests/unit/test_status_registry.gd`

- [ ] **Step 1: Write failing test**

Add to `tests/unit/test_status_registry.gd`:

```gdscript
func test_status_def_has_mode_and_default_duration() -> void:
	var def := StatusDef.new("test_stain", "Test", Color.WHITE, 1.0, 1.0)
	assert_int(def.mode).is_equal(StatusDef.Mode.STAIN)
	assert_float(def.default_duration).is_equal(0.0)

func test_timed_status_def() -> void:
	var def := StatusDef.new("test_timed", "Timed", Color.BLUE, 0.0, 0.0, StatusDef.Category.HARMFUL, 0.0, false, 1.0, "", StatusDef.Mode.TIMED, 0.5)
	assert_int(def.mode).is_equal(StatusDef.Mode.TIMED)
	assert_float(def.default_duration).is_equal(0.5)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_registry.gd`
Expected: FAIL — `StatusDef` has no `Mode` enum or `default_duration` field.

- [ ] **Step 3: Implement — add `Mode` enum and fields to StatusDef**

In `src/status/status_def.gd`, add after `enum Category { HARMFUL, NEUTRAL, BENEFICIAL }`:

```gdscript
enum Mode { STAIN, TIMED }
```

Add after `var icon_path: String`:

```gdscript
var mode: int = Mode.STAIN
var default_duration: float = 0.0
```

Add two new parameters to `_init()`, after `p_icon_path`:

```gdscript
	p_mode: int = Mode.STAIN,
	p_default_duration: float = 0.0
) -> void:
```

Add assignments in the body before the closing `pass`:

```gdscript
	mode = p_mode
	default_duration = p_default_duration
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_registry.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/status/status_def.gd tests/unit/test_status_registry.gd
git commit -m "feat: add Mode enum and default_duration to StatusDef"
```

---

### Task 2: Register steam, lightning, stun status definitions + MAT_STEAM stain mapping

**Files:**
- Modify: `src/autoload/status_registry.gd`
- Test: `tests/unit/test_status_registry.gd`

- [ ] **Step 1: Write failing tests**

Add to `tests/unit/test_status_registry.gd`:

```gdscript
func test_steam_status_def() -> void:
	var def := StatusRegistry.get_def("steam")
	assert_that(def).is_not_null()
	assert_str(def.id).is_equal("steam")
	assert_int(def.mode).is_equal(StatusDef.Mode.STAIN)
	assert_float(def.burn_dps).is_equal(3.0)
	assert_float(def.slow_multiplier).is_equal(0.8)
	assert_float(def.decay_rate).is_equal(1.2)

func test_lightning_status_def() -> void:
	var def := StatusRegistry.get_def("lightning")
	assert_that(def).is_not_null()
	assert_str(def.id).is_equal("lightning")
	assert_int(def.mode).is_equal(StatusDef.Mode.TIMED)
	assert_float(def.default_duration).is_equal(0.4)
	assert_float(def.burn_dps).is_equal(0.0)

func test_stun_status_def() -> void:
	var def := StatusRegistry.get_def("stun")
	assert_that(def).is_not_null()
	assert_str(def.id).is_equal("stun")
	assert_int(def.mode).is_equal(StatusDef.Mode.TIMED)
	assert_float(def.default_duration).is_equal(0.2)

func test_stain_for_material_steam() -> void:
	assert_str(StatusRegistry.stain_for_material(MaterialRegistry.MAT_STEAM)).is_equal("steam")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_registry.gd`
Expected: FAIL — steam/lightning/stun not registered, MAT_STEAM not defined.

- [ ] **Step 3: Add MAT_STEAM to material_registry.gd**

In `src/autoload/material_registry.gd`:

Add `var MAT_STEAM: int` declaration after `var MAT_BEDROCK: int` (line 63).

In `_init_materials()`, after the `MAT_BEDROCK` block (after line 236), add:

```gdscript
	var mat_steam := MaterialDef.new(
		"STEAM", "",
		false, 0, 0,
		false, false,
		Color(0.9, 0.9, 0.9, 0.7),
		true,
		0,
		1.0,
		0.0
	)
	mat_steam.id = materials.size()
	materials.append(mat_steam)
	MAT_STEAM = mat_steam.id
```

- [ ] **Step 4: Add stain_for_material mapping for MAT_STEAM**

In `src/autoload/status_registry.gd`, in `stain_for_material()`, add before `return ""`:

```gdscript
	if material_id == MaterialRegistry.MAT_STEAM:
		return "steam"
```

- [ ] **Step 5: Register steam, lightning, stun in _register_defs()**

In `src/autoload/status_registry.gd`, after the `poisoned` entry in `_register_defs()`, add:

```gdscript
	_add(StatusDefScript.new(
		"steam", "Steamed", Color(0.85, 0.85, 0.85, 1.0),
		1.2, 1.0, StatusDef.Category.HARMFUL, 3.0, false, 0.8,
		""))
	_add(StatusDefScript.new(
		"lightning", "Shocked", Color(0.9, 0.95, 1.0, 1.0),
		0.0, 0.0, StatusDef.Category.HARMFUL, 0.0, false, 1.0,
		"", StatusDef.Mode.TIMED, 0.4))
	_add(StatusDefScript.new(
		"stun", "Stunned", Color(1.0, 1.0, 0.5, 1.0),
		0.0, 0.0, StatusDef.Category.HARMFUL, 0.0, false, 1.0,
		"", StatusDef.Mode.TIMED, 0.2))
```

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_registry.gd`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/autoload/status_registry.gd src/autoload/material_registry.gd tests/unit/test_status_registry.gd
git commit -m "feat: register steam/lightning/stun statuses and MAT_STEAM stain mapping"
```

---

### Task 3: Timed status model in StatusComponent

**Files:**
- Modify: `src/status/status_component.gd`
- Test: `tests/unit/test_status_component.gd`

- [ ] **Step 1: Write failing tests**

Add to `tests/unit/test_status_component.gd`:

```gdscript
func test_add_timed_status() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	comp.add_timed_status("stun", 0.5)
	assert_bool(comp.has_timed_status("stun")).is_true()
	assert_bool(comp.has_timed_status("lightning")).is_false()

func test_timed_status_ticks_down() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	comp.add_timed_status("stun", 0.3)
	comp.tick(0.2)
	assert_bool(comp.has_timed_status("stun")).is_true()
	assert_float(comp.get_timed_remaining("stun")).is_equal_approx(0.1, 0.001)

func test_timed_status_expires() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	comp.add_timed_status("stun", 0.2)
	comp.tick(0.3)
	assert_bool(comp.has_timed_status("stun")).is_false()
	assert_float(comp.get_timed_remaining("stun")).is_equal(0.0)

func test_is_stunned() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	assert_bool(comp.is_stunned()).is_false()
	comp.add_timed_status("stun", 0.5)
	assert_bool(comp.is_stunned()).is_true()

func test_can_attack() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	assert_bool(comp.can_attack()).is_true()
	comp.add_timed_status("stun", 0.5)
	assert_bool(comp.can_attack()).is_false()

func test_stain_and_timed_coexist() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	comp.add_stain("on_fire", 3.0)
	comp.add_timed_status("stun", 0.5)
	assert_bool(comp.has_status("on_fire")).is_true()
	assert_bool(comp.has_timed_status("stun")).is_true()
	assert_bool(comp.is_stunned()).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_component.gd`
Expected: FAIL — `add_timed_status` does not exist.

- [ ] **Step 3: Implement timed status fields and methods**

In `src/status/status_component.gd`, add after line 41 (`var _accum_poll_delta`):

```gdscript
var _timed_statuses: Dictionary = {}
```

Add after the `clear()` method (after line 90):

```gdscript
func add_timed_status(id: String, duration: float) -> void:
	_timed_statuses[id] = {"remaining": duration, "duration": duration}
	changed.emit()

func has_timed_status(id: String) -> bool:
	return id in _timed_statuses and _timed_statuses[id]["remaining"] > 0.0

func get_timed_remaining(id: String) -> float:
	if id in _timed_statuses:
		return _timed_statuses[id]["remaining"]
	return 0.0

func is_stunned() -> bool:
	return has_timed_status("stun")

func can_attack() -> bool:
	return not is_stunned()
```

- [ ] **Step 4: Add timed decay to `tick()`**

In `src/status/status_component.gd`, in `tick()`, change the idle fast path (line 126) from:

```gdscript
	if _stains.is_empty() and _burn_accum == 0.0:
```

to:

```gdscript
	if _stains.is_empty() and _burn_accum == 0.0 and _timed_statuses.is_empty():
```

After the `_apply_effects(delta)` call (line 130) and before `changed.emit()` (line 131), add:

```gdscript
	var _expired: Array = []
	for id in _timed_statuses:
		_timed_statuses[id]["remaining"] -= delta
		if _timed_statuses[id]["remaining"] <= 0.0:
			_expired.append(id)
	for id in _expired:
		_timed_statuses.erase(id)
```

- [ ] **Step 5: Extend `is_movement_blocked()` and `get_blended_tint()`**

Replace `is_movement_blocked()` with:

```gdscript
func is_movement_blocked() -> bool:
	if is_stunned():
		return true
	return is_zero_approx(get_move_speed_multiplier())
```

Replace `get_blended_tint()` with:

```gdscript
func get_blended_tint() -> Color:
	var ids: Array = get_active_ids()
	var c: Color = Color.WHITE
	if ids.is_empty() and _timed_statuses.is_empty():
		return Color.WHITE
	for id in ids:
		c = c.lerp(StatusRegistry.get_tint(id), 0.5)
	for id in _timed_statuses:
		if _timed_statuses[id]["remaining"] > 0.0:
			var ratio: float = _timed_statuses[id]["remaining"] / _timed_statuses[id]["duration"]
			c = c.lerp(StatusRegistry.get_tint(id), 0.5 * ratio)
	return c
```

- [ ] **Step 6: Run tests**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_component.gd`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/status/status_component.gd tests/unit/test_status_component.gd
git commit -m "feat: add timed status model to StatusComponent"
```

---

### Task 4: Reaction rules 7–8 and MAT_STEAM material placement

**Files:**
- Modify: `src/autoload/status_registry.gd` (reactions, `apply_reactions` signature)
- Modify: `src/status/status_component.gd` (pass position to reactions)
- Modify: `src/core/terrain_surface.gd` (add `place_steam`)
- Modify: `src/core/terrain_modifier.gd` (add `place_steam`)
- Test: `tests/unit/test_status_reactions.gd`

- [ ] **Step 1: Add `place_steam` to TerrainSurface**

In `src/core/terrain_surface.gd`, add after `place_fire`:

```gdscript
func place_steam(world_pos: Vector2, radius: float, density: int) -> void:
	if adapter:
		adapter.place_steam(world_pos, radius, density)
```

- [ ] **Step 2: Add `place_steam` to TerrainModifier**

In `src/core/terrain_modifier.gd`, add after `place_gas` (after line 55). This is modeled exactly on `place_gas` but uses `MaterialRegistry.MAT_STEAM`:

```gdscript
func place_steam(world_pos: Vector2, radius: float, density: int, velocity: Vector2i = Vector2i.ZERO) -> void:
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
			affected[chunk_coord].append(local)
	var clamped_density: int = clampi(density, 0, 255)
	var vx := clampi(velocity.x + 8, 0, 15)
	var vy := clampi(velocity.y + 8, 0, 15)
	var packed_velocity: int = (vx << 4) | vy
	for chunk_coord in affected:
		var chunk: Chunk = world_manager.chunks[chunk_coord]
		var data: PackedByteArray = world_manager.rd.texture_get_data(chunk.rd_texture, 0)
		var modified := false
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = MaterialRegistry.MAT_STEAM
			data[idx + 1] = clamped_density
			data[idx + 2] = 0
			data[idx + 3] = packed_velocity
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)
			world_manager.mark_terrain_dirty(chunk.coord)
	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)
```

- [ ] **Step 3: Update `apply_reactions` signature to accept entity position**

In `src/autoload/status_registry.gd`, change line 142:

From:
```gdscript
func apply_reactions(c: StatusComponent, delta: float) -> void:
```

To:
```gdscript
func apply_reactions(c: StatusComponent, delta: float, entity_position: Vector2 = Vector2.ZERO) -> void:
```

- [ ] **Step 4: Add reaction rules 7 and 8**

In `src/autoload/status_registry.gd`, after rule 6 (the `chilly >= CHILLY_FREEZE_THRESHOLD` block at line ~170) and before the closing `}` of `apply_reactions`, add reaction constants and rules:

After the existing constants block (after `CHILLY_RAMP_RATE`), add:

```gdscript
const LIGHTNING_STEAM_DRAIN_WET := 3.0
const STEAM_EXTINGUISH_FIRE := 3.0
const STEAM_DRAIN_RATE := 2.0
```

Then in `apply_reactions`, after rule 6, add:

```gdscript
	# 7. Lightning + wet → spawn MAT_STEAM around the entity.
	if c.has_timed_status("lightning") and c.get_stain("wet") >= get_threshold("wet"):
		TerrainSurface.place_steam(entity_position, 12.0, 180)
		c.reduce_stain("wet", LIGHTNING_STEAM_DRAIN_WET * delta)
		c.add_timed_status("lightning", 0.0)  # consume lightning
	# 8. Steam smothers fire (bidirectional).
	if c.get_stain("steam") > 0.0 and c.get_stain("on_fire") > 0.0:
		c.reduce_stain("on_fire", STEAM_EXTINGUISH_FIRE * delta)
		c.reduce_stain("steam", STEAM_DRAIN_RATE * delta)
```

- [ ] **Step 5: Update `StatusComponent.tick()` to pass owner position**

In `src/status/status_component.gd`, change the `tick()` method's call from:

```gdscript
	StatusRegistry.apply_reactions(self, delta)
```

to:

```gdscript
	var entity_pos: Vector2 = Vector2.ZERO
	if _owner_node is Node2D:
		entity_pos = (_owner_node as Node2D).global_position
	StatusRegistry.apply_reactions(self, delta, entity_pos)
```

- [ ] **Step 6: Write reaction tests**

Add to `tests/unit/test_status_reactions.gd`:

```gdscript
func test_lightning_plus_wet_drains_wet_and_consumes_lightning() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	comp.add_stain("wet", 5.0)
	comp.add_timed_status("lightning", 0.4)
	StatusRegistry.apply_reactions(comp, 0.1, Vector2(100.0, 100.0))
	assert_float(comp.get_stain("wet")).is_less(5.0)
	assert_bool(comp.has_timed_status("lightning")).is_false()

func test_steam_smothers_fire() -> void:
	var comp := StatusComponent.new()
	comp._ready()
	comp.add_stain("steam", 4.0)
	comp.add_stain("on_fire", 3.0)
	StatusRegistry.apply_reactions(comp, 0.1, Vector2.ZERO)
	assert_float(comp.get_stain("on_fire")).is_less(3.0)
	assert_float(comp.get_stain("steam")).is_less(4.0)
```

- [ ] **Step 7: Run tests**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_reactions.gd && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_component.gd`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/autoload/status_registry.gd src/status/status_component.gd src/core/terrain_surface.gd src/core/terrain_modifier.gd tests/unit/test_status_reactions.gd
git commit -m "feat: add reaction rules (lightning+wet→steam, steam+fire) and place_steam"
```

---

### Task 5: MAT_STEAM shader dispatch (parameterize gas_advect_pull)

**Files:**
- Modify: `shaders/include/sim/gas.glslinc` (add `pack_steam`, parameterize output material in `gas_advect_pull`)
- Modify: `shaders/compute/simulation.glsl` (add `simulate_steam` dispatch)
- Regenerate: `shaders/generated/materials.glslinc` and `materials.gdshaderinc`

- [ ] **Step 1: Add `pack_steam` to `gas.glslinc`**

In `shaders/include/sim/gas.glslinc`, add after the `pack_gas` function (after line 18):

```glsl
vec4 pack_steam(int density, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_STEAM) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		0.0,
		float(a) / 255.0
	);
}
```

- [ ] **Step 2: Parameterize `gas_advect_pull` with output material**

Change the function signature of `gas_advect_pull` (line 24) from:

```glsl
void gas_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
```

to:

```glsl
void gas_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right,
	int out_material
) {
```

- [ ] **Step 3: Replace `pack_gas` calls in `gas_advect_pull` with conditional pack**

In `gas_advect_pull`, change line 168 from:

```glsl
			imageStore(chunk_tex, pos, pack_gas(air_total_in, inflow_vel));
```

to:

```glsl
			vec4 packed = (out_material == MAT_STEAM) ? pack_steam(air_total_in, inflow_vel) : pack_gas(air_total_in, inflow_vel);
			imageStore(chunk_tex, pos, packed);
```

Change line 181 from:

```glsl
	imageStore(chunk_tex, pos, pack_gas(new_density, new_vel));
```

to:

```glsl
	vec4 out_packed = (out_material == MAT_STEAM) ? pack_steam(new_density, new_vel) : pack_gas(new_density, new_vel);
	imageStore(chunk_tex, pos, out_packed);
```

- [ ] **Step 4: Update `simulate_gas` call to pass `MAT_GAS`**

Change `simulate_gas` (line 184-188) to pass `MAT_GAS`:

```glsl
bool simulate_gas(ivec2 pos, inout vec4 pixel, inout int material,
                  vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	if (material != MAT_GAS && material != MAT_AIR) return false;
	gas_advect_pull(pos, pixel, n_up, n_down, n_left, n_right, MAT_GAS);
	return true;
}
```

- [ ] **Step 5: Update `is_solid_for_gas` to accept `MAT_STEAM` too**

Change line 20-22:

```glsl
bool is_solid_for_gas(int mat) {
	return mat != MAT_AIR && mat != MAT_GAS && mat != MAT_STEAM;
}
```

- [ ] **Step 6: Update `any_gas_neighbor` in `gas_advect_pull` to include `MAT_STEAM`**

Change lines 35-38:

```glsl
	bool any_gas_neighbor =
		n_mat_up == MAT_GAS || n_mat_down == MAT_GAS ||
		n_mat_left == MAT_GAS || n_mat_right == MAT_GAS ||
		n_mat_up == MAT_STEAM || n_mat_down == MAT_STEAM ||
		n_mat_left == MAT_STEAM || n_mat_right == MAT_STEAM;
```

- [ ] **Step 7: Update density/velocity reads to include `MAT_STEAM`**

Change lines 46-47:

```glsl
	int density = (material == MAT_GAS || material == MAT_STEAM) ? get_density(pixel) : 0;
	ivec2 vel = (material == MAT_GAS || material == MAT_STEAM) ? unpack_velocity(pixel) : ivec2(0);
```

- [ ] **Step 8: Update neighbor density reads in diffusion**

Change lines 121-124:

```glsl
		int dens_up    = (n_mat_up == MAT_GAS || n_mat_up == MAT_STEAM)    ? get_density(n_up)    : 0;
		int dens_down  = (n_mat_down == MAT_GAS || n_mat_down == MAT_STEAM)  ? get_density(n_down)  : 0;
		int dens_left  = (n_mat_left == MAT_GAS || n_mat_left == MAT_STEAM)  ? get_density(n_left)  : 0;
		int dens_right = (n_mat_right == MAT_GAS || n_mat_right == MAT_STEAM) ? get_density(n_right) : 0;
```

- [ ] **Step 9: Update diffusion neighbor checks (lines 133-136)**

```glsl
	if ((n_mat_up == MAT_GAS || n_mat_up == MAT_STEAM)    && get_density(n_up) > density    && !is_solid_for_gas(material))    diff_in += (get_density(n_up) - density) / DIFFUSION_RATE;
	if ((n_mat_down == MAT_GAS || n_mat_down == MAT_STEAM)  && get_density(n_down) > density  && !is_solid_for_gas(material))  diff_in += (get_density(n_down) - density) / DIFFUSION_RATE;
	if ((n_mat_left == MAT_GAS || n_mat_left == MAT_STEAM)  && get_density(n_left) > density  && !is_solid_for_gas(material))  diff_in += (get_density(n_left) - density) / DIFFUSION_RATE;
	if ((n_mat_right == MAT_GAS || n_mat_right == MAT_STEAM) && get_density(n_right) > density && !is_solid_for_gas(material)) diff_in += (get_density(n_right) - density) / DIFFUSION_RATE;
```

- [ ] **Step 10: Update air-cell final check (line 186)**

```glsl
	if (material != MAT_GAS && material != MAT_STEAM && material != MAT_AIR) return false;
```

- [ ] **Step 11: Update `injection.glslinc` to accept `MAT_STEAM` next to `MAT_GAS`**

In `shaders/include/sim/injection.glslinc`, change any `MAT_GAS` checks that should also match `MAT_STEAM`. Find the injection check (line ~22) and update:

```glsl
		if ((material == MAT_GAS || material == MAT_STEAM) && diff.x == 0 && diff.y == 0) {
```

- [ ] **Step 12: Add `simulate_steam` to `simulation.glsl`**

Add after the `simulate_gas` call (after line 78):

```glsl
	if (simulate_steam(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
```

Add the `simulate_steam` function inline before `void main()` in `simulation.glsl`:

```glsl
bool simulate_steam(ivec2 pos, inout vec4 pixel, inout int material,
                    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	if (material != MAT_STEAM) return false;
	gas_advect_pull(pos, pixel, n_up, n_down, n_left, n_right, MAT_STEAM);
	return true;
}
```

- [ ] **Step 13: Regenerate shader constants**

Run: `godot --headless --path . --import && godot --headless --path . --script res://tools/generate_material_glsl.gd`

Verify that `shaders/generated/materials.glslinc` now contains `const int MAT_STEAM = 14;` (or whatever the next ID is).

- [ ] **Step 14: Manual verification**

Launch the game, use the spawn_mat console command to place `MAT_STEAM` and verify it rises and disperses like gas, tints white, and applies the "Steamed" status to the player when standing in it.

- [ ] **Step 15: Commit**

```bash
git add shaders/ src/autoload/material_registry.gd
git commit -m "feat: add MAT_STEAM material and gas-like shader dispatch"
```

---

### Task 6: Combat verbs — stun, knockback (entity changes)

**Files:**
- Modify: `src/enemies/enemy.gd` (add `apply_knockback`, remove `_parry_stun_remaining`, gate attack states)
- Modify: `src/player/player_controller.gd` (add `apply_knockback`, gate weapon use, update parry)
- Test: `tests/unit/test_status_component.gd` (stun/can_attack verified in Task 3)

- [ ] **Step 1: Add `apply_knockback` to Enemy**

In `src/enemies/enemy.gd`, add after `_tick_knockback` (after line ~619):

```gdscript
func apply_knockback(direction: Vector2, strength: float) -> void:
	_knockback_velocity += direction.normalized() * strength
```

- [ ] **Step 2: Refactor `on_hit_impact` in Enemy to use `apply_knockback`**

In `src/enemies/enemy.gd`, in `on_hit_impact()` (line 562), change line 564 from:

```gdscript
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
```

to:

```gdscript
		apply_knockback(hit_dir, KNOCKBACK_SPEED)
```

- [ ] **Step 3: Replace `_parry_stun_remaining` with timed stun in Enemy**

In `src/enemies/enemy.gd`:

Remove line 67: `var _parry_stun_remaining: float = 0.0`

In `_process()` (lines 155-162), replace the `_parry_stun_remaining` block. Change:

```gdscript
	if _parry_stun_remaining > 0.0:
		_parry_stun_remaining -= delta
		# Keep cooldown at least as long as the remaining stun.
		if _state == State.COOLDOWN and _state_timer < _parry_stun_remaining:
			_state_timer = _parry_stun_remaining
		velocity = Vector2.ZERO
		return
```

to:

```gdscript
	if _status_component != null and _status_component.is_stunned():
		velocity = Vector2.ZERO
		return
```

- [ ] **Step 4: Gate enemy attack states on stun**

In `_process_windup()` (line 301), add stun check at the beginning:

```gdscript
func _process_windup(delta: float) -> void:
	if _status_component != null and _status_component.is_stunned():
		_change_state(State.CHASE)
		return
	_state_timer -= delta
	...
```

In `_process_attack()` (line 312), add stun check:

```gdscript
func _process_attack(_delta: float) -> void:
	if _status_component != null and _status_component.is_stunned():
		_change_state(State.CHASE)
		return
	if not _attack_started:
		_attack_started = true
		_execute_attack()
	...
```

- [ ] **Step 5: Add `apply_knockback` to PlayerController**

In `src/player/player_controller.gd`, add after the knockback constants:

```gdscript
func apply_knockback(direction: Vector2, strength: float) -> void:
	_knockback_velocity = direction.normalized() * strength
```

- [ ] **Step 6: Refactor player `on_hit_impact` to use `apply_knockback`**

In `src/player/player_controller.gd`, in `on_hit_impact()` (line 322), change:

```gdscript
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity = hit_dir.normalized() * KNOCKBACK_SPEED
```

to:

```gdscript
	if hit_dir.length_squared() > 0.0001:
		apply_knockback(hit_dir, KNOCKBACK_SPEED)
```

- [ ] **Step 7: Gate player weapon use on `can_attack()`**

In `src/player/player_controller.gd`, in `_physics_process()`, find where the weapon use input is processed. Add a check:

```gdscript
	var status := get_node_or_null("StatusComponent")
	if status != null and not status.can_attack():
		# Clear attack input — stunned player cannot attack
		pass  # The attack input will be swallowed by the can_attack check
```

This should be placed wherever the attack action is read and forwarded to the weapon. Find the attack input handling and wrap it with:

```gdscript
	if status == null or status.can_attack():
		# ... existing attack input code ...
```

(The exact location depends on how weapon use is triggered — typically in `_physics_process` or `_unhandled_input`. Locate the attack/use input and gate it.)

- [ ] **Step 8: Update parry stun to use StatusComponent**

In `src/player/player_controller.gd`, in `try_parry()` (line ~400), change:

```gdscript
	if "_parry_stun_remaining" in attacker:
		attacker._parry_stun_remaining = PARRY_STUN_DURATION
```

to:

```gdscript
	var attacker_status = attacker.get_node_or_null("StatusComponent")
	if attacker_status != null:
		attacker_status.add_timed_status("stun", PARRY_STUN_DURATION)
```

- [ ] **Step 9: Run all status and enemy tests**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_component.gd && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_registry.gd && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_status_reactions.gd`

Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add src/enemies/enemy.gd src/player/player_controller.gd
git commit -m "feat: add knockback/stun verbs to entities, migrate parry stun to timed status"
```

---

### Task 7: StatusVisuals — render timed status icons and tints

**Files:**
- Modify: `src/status/status_visuals.gd`

- [ ] **Step 1: Extend `refresh()` to include timed statuses**

In `src/status/status_visuals.gd`, in the `refresh()` method (line 30), after building `active` (stain IDs), also include timed status IDs:

Replace:

```gdscript
func refresh() -> void:
	if _status == null:
		return
	var active: Array = _status.get_active_ids()
```

with:

```gdscript
func refresh() -> void:
	if _status == null:
		return
	var active: Array = _status.get_active_ids()
	var timed: Array = _status.get_timed_ids()
```

Then update the icon management loop. After the existing stain icon loop, add timed icon management:

```gdscript
	for id in _icons.keys():
		if not active.has(id) and not timed.has(id):
			var spr: Sprite2D = _icons[id]
			remove_child(spr)
			spr.queue_free()
			_icons.erase(id)
	for id in active:
		if not _icons.has(id):
			_icons[id] = _make_icon(id)
	for id in timed:
		if not _icons.has(id):
			_icons[id] = _make_icon(id)
	var ordered: Array = _icons.keys()
	for i in ordered.size():
		var id: String = ordered[i]
		var spr: Sprite2D = _icons[id]
		var x := (float(i) - (ordered.size() - 1) * 0.5) * ICON_SPACING
		spr.position = _head_offset + Vector2(x, 0.0)
		if active.has(id):
			var a := StatusRegistry.get_icon_alpha(id, _status.get_stain(id))
			spr.modulate = Color(1.0, 1.0, 1.0, a)
		elif timed.has(id):
			var remaining := _status.get_timed_remaining(id)
			var duration := StatusRegistry.get_def(id).default_duration
			var ratio := clampf(remaining / maxf(duration, 0.001), 0.0, 1.0)
			spr.modulate = Color(1.0, 1.0, 1.0, lerpf(0.15, 1.0, ratio))
```

- [ ] **Step 2: Add `get_timed_ids()` to StatusComponent**

In `src/status/status_component.gd`, add after `has_timed_status`:

```gdscript
func get_timed_ids() -> Array:
	var result: Array = []
	for id in _timed_statuses:
		if _timed_statuses[id]["remaining"] > 0.0:
			result.append(id)
	return result
```

- [ ] **Step 3: Create status icon textures for timed statuses**

Create placeholder icon textures (or reuse existing ones with tinting). For `stun`, `lightning`, and `steam`, the icon path in StatusDef is `""` (empty). When no icon texture exists, `StatusRegistry.get_icon()` returns null, and `_make_icon` should skip creating an icon. Verify this handles empty icon paths gracefully — if `_make_icon` creates a Sprite2D with null texture, it will be invisible. That's acceptable for now; real icon textures can be added later.

- [ ] **Step 4: Verify visually (manual test)**

Launch the game, apply stun to the player via console, confirm no crash and the tint changes (yellow for stun).

- [ ] **Step 5: Commit**

```bash
git add src/status/status_visuals.gd src/status/status_component.gd
git commit -m "feat: render timed status icons and blended tints in StatusVisuals"
```

---

### Task 8: Steam burn DoT effect in StatusComponent

**Files:**
- Modify: `src/status/status_component.gd`

- [ ] **Step 1: Add steam burn DoT to `_apply_effects`**

In `src/status/status_component.gd`, in `_apply_effects()`, after the `on_fire` burn block, add steam scalding:

```gdscript
	if has_status("steam"):
		_burn_accum += StatusRegistry.get_burn_dps("steam") * delta
```

This reuses the existing `_burn_accum` mechanism. Burn tick (the signal) fires for any DoT source.

- [ ] **Step 2: Commit**

```bash
git add src/status/status_component.gd
git commit -m "feat: add steam scalding DoT in StatusComponent"
```

---

### Task 9: Update implementation_todo.md

**Files:**
- Modify: `docs/design_docs/implementation_todo.md`

- [ ] **Step 1: Mark SP-B tasks as done**

Update the Sub-project B table to mark all tasks as `x`:

```markdown
### Sub-project B (6): New statuses & combat hooks
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| x | P2 | High | `lightning`/`steam`/`stun` statuses | StatusDefs + reaction rules (wet→steam, neutral stun) |
| x | P2 | Medium | Enemy stun + knockback hooks | Immobilize + radial impulse verbs |
| x | P2 | Medium | Player heal + economy bounty hooks | `heal` verb; `bounty` extra-gold on kill |
| x | P2 | Medium | Modifiers using new hooks | chain_spark, steam_burst, concussive_edge, repulsor_nova, shockwave_stomp, magnet_field, midas_touch |
```

Also add the new sub-project B.1:

```markdown
### Sub-project B.1 (6.5): SP-B modifier scripts
| Done | Priority | Difficulty | Task | Description |
|------|----------|------------|------|-------------|
| | P2 | Medium | chain_spark, steam_burst, concussive_edge | New on_hit/on_crit modifiers |
| | P2 | Medium | repulsor_nova, shockwave_stomp | Knockback/area modifiers |
| | P2 | Medium | magnet_field, midas_touch | Pull/bounty utility modifiers |
```

- [ ] **Step 2: Commit**

```bash
git add docs/design_docs/implementation_todo.md
git commit -m "docs: mark SP-B tasks complete, add SP-B.1 sub-project"
```

---

### Task 10: Full test suite regression

- [ ] **Step 1: Run full test suite**

Run: `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/`

Expected: ALL PASS

- [ ] **Step 2: Fix any failures**

If any tests fail, investigate and fix. Common issues:
- StatusComponent tests that relied on `tick()` not processing timed statuses
- StatusRegistry tests that rely on the exact number of statuses
- Any hardcoded material ID references

- [ ] **Step 3: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: test regression fixes"
```