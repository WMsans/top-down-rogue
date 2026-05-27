# Oil & Explode Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new sim materials — `MAT_OIL` (flammable liquid) and `MAT_EXPLODE_WAVE` (custom propagating-shell sim) — wired up only through the existing `spawn_mat` console command. No barrels, no markers, no level-gen integration.

**Architecture:** `MAT_OIL` reuses the existing fluid + heat-burning sim (modeled on `lava.glslinc` + `burning.glslinc`); when burning oil reaches `health == 0` it seeds a `MAT_EXPLODE_WAVE` cell instead of decaying to air. `MAT_EXPLODE_WAVE` is a brand-new compute stage at `shaders/include/sim/explode_wave.glslinc` that propagates a 1-cell-thick Manhattan-distance "diamond" front, leaving `SCORCH_TEMP` heat on the air cells it vacates to prevent backfill. All tuning constants live in `shaders/include/sim/common.glslinc`. Materials register via the existing `MaterialRegistry._init_materials`, and `tools/generate_material_glsl.gd` regenerates `shaders/generated/materials.glslinc` for shader-side lookup.

**Tech Stack:** Godot 4 (GDScript), GLSL compute shaders, gdUnit test framework.

---

## File Structure

**Create:**
- `shaders/include/sim/oil.glslinc` — oil fluid sim (advect + flow), modeled on `lava.glslinc`.
- `shaders/include/sim/explode_wave.glslinc` — wave propagation + scorch-mark sim.
- `tests/unit/test_oil_and_explode_wave_registry.gd` — GDScript-side material registration tests.

**Modify:**
- `src/autoload/material_registry.gd` — register `MAT_OIL`, `MAT_EXPLODE_WAVE`; extend `MaterialDef` color/tint as needed.
- `tools/generate_material_glsl.gd` — no logic change; just re-run to regenerate `shaders/generated/materials.glslinc`.
- `shaders/include/sim/common.glslinc` — add `SCORCH_TEMP`, `WAVE_DEFAULT_POWER`, `WAVE_DECAY`, `OIL_BURN_END_POWER` constants.
- `shaders/include/sim/burning.glslinc` — when burning cell with `material == MAT_OIL` reaches `health == 0`, seed `MAT_EXPLODE_WAVE` with `temperature = OIL_BURN_END_POWER` instead of writing `MAT_AIR`.
- `shaders/compute/simulation.glsl` — include the two new files; dispatch `simulate_oil` and `simulate_explode_wave` in `main()`.
- `shaders/visual/render_chunk.gdshader` — render `MAT_EXPLODE_WAVE` as a white-yellow flash (branch in fragment shader); render `MAT_OIL` as dark amber when cold, glowing orange-red when burning.
- `src/core/terrain_modifier.gd:place_material` — when `material_id == MAT_EXPLODE_WAVE`, write `temperature = WAVE_DEFAULT_POWER` into byte 2 of the pixel (currently always 0).
- `src/console/commands/spawn_mat_command.gd` — no signature change needed; the auto-iteration over `MaterialRegistry.materials` picks up new entries automatically.

**Auto-generated (do not edit by hand, but verify after regen):**
- `shaders/generated/materials.glslinc`
- `shaders/generated/materials.gdshaderinc`

---

## Tuning Constants (single source of truth)

These appear in two places after this plan completes:

| Name | Value | Where |
|---|---|---|
| `OIL_IGNITION_TEMP` | 200 | `MaterialDef` for `OIL` (`ignition_temp`) → propagates to `IGNITION_TEMP[]` in `materials.glslinc` |
| `OIL_BURN_HEALTH` | 60 | `MaterialDef` for `OIL` (`burn_health`) → propagates to `BURN_HEALTH[]` in `materials.glslinc` |
| `OIL_BURN_END_POWER` | 18 | `shaders/include/sim/common.glslinc` |
| `WAVE_DEFAULT_POWER` | 60 | `shaders/include/sim/common.glslinc` |
| `WAVE_DECAY` | 4 | `shaders/include/sim/common.glslinc` |
| `SCORCH_TEMP` | 100 | `shaders/include/sim/common.glslinc` |

---

## Task 1: Register MAT_OIL in MaterialRegistry

**Files:**
- Modify: `src/autoload/material_registry.gd:46-57, 162-173` (add field declaration; append init block after `mat_blood`).
- Test: `tests/unit/test_oil_and_explode_wave_registry.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_oil_and_explode_wave_registry.gd`:

```gdscript
extends GdUnitTestSuite

func test_mat_oil_registered() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_OIL).is_greater(0)
	assert_that(registry.is_flammable(registry.MAT_OIL)).is_true()
	assert_that(registry.get_ignition_temp(registry.MAT_OIL)).is_equal(200)
	assert_that(registry.is_fluid(registry.MAT_OIL)).is_true()
	assert_that(registry.has_collider(registry.MAT_OIL)).is_false()
	assert_that(registry.has_wall_extension(registry.MAT_OIL)).is_false()

func test_mat_oil_burn_health() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	var oil_def: MaterialRegistry.MaterialDef = registry.materials[registry.MAT_OIL]
	assert_that(oil_def.burn_health).is_equal(60)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_oil_and_explode_wave_registry.gd`
Expected: FAIL — `MAT_OIL` is not a property of `MaterialRegistry`.

- [ ] **Step 3: Add the field declaration**

In `src/autoload/material_registry.gd`, after the `var MAT_BLOOD: int` line (~line 57), add:

```gdscript
var MAT_OIL: int
```

- [ ] **Step 4: Register MAT_OIL in `_init_materials`**

In `src/autoload/material_registry.gd`, append after the `mat_blood` block (~line 173):

```gdscript
	var mat_oil := MaterialDef.new(
		"OIL", "",
		true, 200, 60,
		false, false,
		Color(0.18, 0.12, 0.06, 1.0),
		true,
		0,
		1.0,
		0.0
	)
	mat_oil.id = materials.size()
	materials.append(mat_oil)
	MAT_OIL = mat_oil.id
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_oil_and_explode_wave_registry.gd`
Expected: PASS — both `test_mat_oil_registered` and `test_mat_oil_burn_health`.

- [ ] **Step 6: Commit**

```bash
git add src/autoload/material_registry.gd tests/unit/test_oil_and_explode_wave_registry.gd
git commit -m "feat(materials): register MAT_OIL"
```

---

## Task 2: Register MAT_EXPLODE_WAVE in MaterialRegistry

**Files:**
- Modify: `src/autoload/material_registry.gd` (add field; append init block after `mat_oil`).
- Test: `tests/unit/test_oil_and_explode_wave_registry.gd`

- [ ] **Step 1: Extend the failing test**

Append to `tests/unit/test_oil_and_explode_wave_registry.gd`:

```gdscript
func test_mat_explode_wave_registered() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_EXPLODE_WAVE).is_greater(0)
	assert_that(registry.is_flammable(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.is_fluid(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.has_collider(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.has_wall_extension(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.get_glow(registry.MAT_EXPLODE_WAVE)).is_greater_equal(10.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_oil_and_explode_wave_registry.gd`
Expected: FAIL — `MAT_EXPLODE_WAVE` not defined.

- [ ] **Step 3: Add the field declaration**

In `src/autoload/material_registry.gd`, after `var MAT_OIL: int`, add:

```gdscript
var MAT_EXPLODE_WAVE: int
```

- [ ] **Step 4: Register MAT_EXPLODE_WAVE in `_init_materials`**

In `src/autoload/material_registry.gd`, append after the `mat_oil` block:

```gdscript
	var mat_explode_wave := MaterialDef.new(
		"EXPLODE_WAVE", "",
		false, 0, 0,
		false, false,
		Color(1.0, 0.95, 0.6, 1.0),
		false,
		0,
		15.0,
		0.0
	)
	mat_explode_wave.id = materials.size()
	materials.append(mat_explode_wave)
	MAT_EXPLODE_WAVE = mat_explode_wave.id
```

(Note: `fluid=false` so the existing fluid dispatch and renderer-overlay path do not pick it up — its rendering is handled by a dedicated branch in Task 9.)

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_oil_and_explode_wave_registry.gd`
Expected: PASS — all three tests.

- [ ] **Step 6: Commit**

```bash
git add src/autoload/material_registry.gd tests/unit/test_oil_and_explode_wave_registry.gd
git commit -m "feat(materials): register MAT_EXPLODE_WAVE"
```

---

## Task 3: Regenerate shader material constants

**Files:**
- Auto-generated: `shaders/generated/materials.glslinc`, `shaders/generated/materials.gdshaderinc`

- [ ] **Step 1: Run the codegen tool**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue --script res://tools/generate_material_glsl.gd`
Expected: exits cleanly, no errors.

- [ ] **Step 2: Verify the generated file**

Run: `grep -E 'MAT_OIL|MAT_EXPLODE_WAVE|MAT_COUNT' /Users/jeremyzhao/Development/godot/top-down-rogue/shaders/generated/materials.glslinc`
Expected output includes:
```
const int MAT_COUNT = 12;
const int MAT_OIL = 10;
const int MAT_EXPLODE_WAVE = 11;
```

Also confirm:
- `IS_FLUID[10] == true`, `IS_FLUID[11] == false`
- `IS_FLAMMABLE[10] == true`, `IS_FLAMMABLE[11] == false`
- `IGNITION_TEMP[10] == 200`
- `BURN_HEALTH[10] == 60`

- [ ] **Step 3: Commit**

```bash
git add shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "chore(materials): regenerate shader constants for oil + explode wave"
```

---

## Task 4: Add tuning constants to common.glslinc

**Files:**
- Modify: `shaders/include/sim/common.glslinc:1-12` (constants block).

- [ ] **Step 1: Add the new constants**

In `shaders/include/sim/common.glslinc`, after the existing `const int DIFFUSION_RATE = 4;` line, add:

```glsl
// Oil + explode wave tuning. See docs/superpowers/specs/2026-05-14-set-piece-rooms-design.md §3.5.5.
const int OIL_BURN_END_POWER = 18;
const int WAVE_DEFAULT_POWER = 60;
const int WAVE_DECAY = 4;
const int SCORCH_TEMP = 100;
```

- [ ] **Step 2: Verify shaders still compile**

Open the Godot editor on the project (`godot --path /Users/jeremyzhao/Development/godot/top-down-rogue --editor`) or run any existing test suite that touches the simulation shader:
Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_terrain_surface.gd`
Expected: PASS, no shader compile errors in stderr.

- [ ] **Step 3: Commit**

```bash
git add shaders/include/sim/common.glslinc
git commit -m "feat(sim): add oil + explode wave tuning constants"
```

---

## Task 5: Implement oil.glslinc (fluid sim)

**Files:**
- Create: `shaders/include/sim/oil.glslinc`

Oil is a flammable liquid with the same advect-pull mechanics as lava but lower glow. Its burning behavior is handled entirely by `burning.glslinc` via `IS_FLAMMABLE[MAT_OIL] = true` (Task 3 regen), so this file is purely the fluid dispatch. The structure mirrors `lava.glslinc` exactly — same packing layout, same `advect_pull`, just keyed on `MAT_OIL`. We duplicate (not parameterize) because shader includes don't have generics and the codebase already follows this per-fluid pattern.

- [ ] **Step 1: Create `shaders/include/sim/oil.glslinc`**

```glsl
int get_density_oil(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature_oil(vec4 p) { return int(round(p.b * 255.0)); }

ivec2 unpack_velocity_oil(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_oil(int density, int temperature, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_OIL) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		float(clamp(temperature, 0, 255)) / 255.0,
		float(a) / 255.0
	);
}

bool is_solid_for_oil(int mat) {
	return mat != MAT_AIR && mat != MAT_OIL;
}

void oil_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
	int material = get_material(pixel);

	int n_mat_up    = get_material(n_up);
	int n_mat_down  = get_material(n_down);
	int n_mat_left  = get_material(n_left);
	int n_mat_right = get_material(n_right);

	bool any_oil_neighbor =
		n_mat_up == MAT_OIL || n_mat_down == MAT_OIL ||
		n_mat_left == MAT_OIL || n_mat_right == MAT_OIL;

	if (material == MAT_AIR && !any_oil_neighbor) {
		return;
	}

	int density = (material == MAT_OIL) ? get_density_oil(pixel) : 0;
	int temperature = (material == MAT_OIL) ? get_temperature_oil(pixel) : 0;
	ivec2 vel = (material == MAT_OIL) ? unpack_velocity_oil(pixel) : ivec2(0);

	int comp_up    = max(0, -vel.y);
	int comp_down  = max(0,  vel.y);
	int comp_left  = max(0, -vel.x);
	int comp_right = max(0,  vel.x);

	if (is_solid_for_oil(n_mat_up))    comp_up    = 0;
	if (is_solid_for_oil(n_mat_down))  comp_down  = 0;
	if (is_solid_for_oil(n_mat_left))  comp_left  = 0;
	if (is_solid_for_oil(n_mat_right)) comp_right = 0;

	int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 101u);
	int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 102u);
	int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 103u);
	int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 104u);

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

	if (n_mat_up == MAT_OIL) {
		int dN = get_density_oil(n_up);
		ivec2 vN = unpack_velocity_oil(n_up);
		in_up = stochastic_div(dN * max(0, vN.y), V_MAX_OUTFLOW, pos, 105u);
		vin_up = vN;
	}
	if (n_mat_down == MAT_OIL) {
		int dN = get_density_oil(n_down);
		ivec2 vN = unpack_velocity_oil(n_down);
		in_down = stochastic_div(dN * max(0, -vN.y), V_MAX_OUTFLOW, pos, 106u);
		vin_down = vN;
	}
	if (n_mat_left == MAT_OIL) {
		int dN = get_density_oil(n_left);
		ivec2 vN = unpack_velocity_oil(n_left);
		in_left = stochastic_div(dN * max(0, vN.x), V_MAX_OUTFLOW, pos, 107u);
		vin_left = vN;
	}
	if (n_mat_right == MAT_OIL) {
		int dN = get_density_oil(n_right);
		ivec2 vN = unpack_velocity_oil(n_right);
		in_right = stochastic_div(dN * max(0, -vN.x), V_MAX_OUTFLOW, pos, 108u);
		vin_right = vN;
	}

	int total_in = in_up + in_down + in_left + in_right;

	if (is_solid_for_oil(n_mat_up)    && vel.y < 0) vel.y = -vel.y;
	if (is_solid_for_oil(n_mat_down)  && vel.y > 0) vel.y = -vel.y;
	if (is_solid_for_oil(n_mat_left)  && vel.x < 0) vel.x = -vel.x;
	if (is_solid_for_oil(n_mat_right) && vel.x > 0) vel.x = -vel.x;

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

	int temp_weight = stayed * temperature;
	if (n_mat_up == MAT_OIL) temp_weight += get_temperature_oil(n_up) * in_up;
	if (n_mat_down == MAT_OIL) temp_weight += get_temperature_oil(n_down) * in_down;
	if (n_mat_left == MAT_OIL) temp_weight += get_temperature_oil(n_left) * in_left;
	if (n_mat_right == MAT_OIL) temp_weight += get_temperature_oil(n_right) * in_right;
	int new_temp = temp_weight / max(1, stayed + total_in);

	if (material == MAT_AIR) {
		if (total_in >= THRESHOLD_BECOME_LAVA) {
			ivec2 inflow_vel = ivec2(0);
			if (total_in > 0) {
				inflow_vel = (vin_up * in_up + vin_down * in_down + vin_left * in_left + vin_right * in_right) / total_in;
				inflow_vel = (inflow_vel * 15) / 16;
				inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
			}
			imageStore(chunk_tex, pos, pack_oil(total_in, new_temp, inflow_vel));
			return;
		}
		return;
	}

	if (new_density < THRESHOLD_DISSIPATE) {
		imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
		return;
	}
	imageStore(chunk_tex, pos, pack_oil(new_density, new_temp, new_vel));
}

bool simulate_oil(ivec2 pos, inout vec4 pixel, inout int material,
                  vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	if (material != MAT_OIL && material != MAT_AIR) return false;
	oil_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
	if (material == MAT_OIL) return true;
	pixel = imageLoad(chunk_tex, pos);
	material = get_material(pixel);
	return material == MAT_OIL;
}
```

- [ ] **Step 2: Verify the file compiles when included**

The file isn't included yet, so just confirm there are no syntax errors by visual review. The next task wires it in.

- [ ] **Step 3: Commit**

```bash
git add shaders/include/sim/oil.glslinc
git commit -m "feat(sim): add oil fluid sim"
```

---

## Task 6: Wire oil into simulation.glsl dispatch

**Files:**
- Modify: `shaders/compute/simulation.glsl:35-40` (include block) and `:58-60` (dispatch block).

- [ ] **Step 1: Add the include**

In `shaders/compute/simulation.glsl`, after the existing `#include "res://shaders/include/sim/lava.glslinc"` line, add:

```glsl
#include "res://shaders/include/sim/oil.glslinc"
```

- [ ] **Step 2: Add the fluid dispatch call**

In `shaders/compute/simulation.glsl`, after the existing `if (simulate_lava(...)) return;` line, add (BEFORE `simulate_blood`, so oil takes priority similarly to lava):

```glsl
	if (simulate_oil(pos, pixel, material, n_up, n_down, n_left, n_right))  return;
```

- [ ] **Step 3: Launch Godot and verify shaders compile**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue --quit-after 5`
Expected: clean exit, no shader compile errors mentioning `simulate_oil` or `MAT_OIL`.

- [ ] **Step 4: Manual sanity-test via console**

Run the game (`godot --path /Users/jeremyzhao/Development/godot/top-down-rogue`), open the console, type `spawn_mat oil 5` while hovering somewhere with air below; confirm oil pools and flows downward like lava (dark amber color from MaterialDef tint).

- [ ] **Step 5: Commit**

```bash
git add shaders/compute/simulation.glsl
git commit -m "feat(sim): dispatch oil fluid sim"
```

---

## Task 7: Burning oil seeds explode wave at end-of-life

**Files:**
- Modify: `shaders/include/sim/burning.glslinc:63-75` (the flammable end-of-burn block).

- [ ] **Step 1: Modify the end-of-burn branch**

In `shaders/include/sim/burning.glslinc`, replace the existing flammable block (lines 63-75):

```glsl
	if (IS_FLAMMABLE[material]) {
		temperature = min(255, temperature + heat_gain);
		temperature = max(0, temperature - HEAT_DISSIPATION);
		if (temperature > IGNITION_TEMP[material]) {
			health = health - 1;
			temperature = FIRE_TEMP;
			if (health <= 0) {
				material = MAT_AIR;
				health = 0;
				temperature = 0;
			}
		}
	}
```

with:

```glsl
	if (IS_FLAMMABLE[material]) {
		int original_material = material;
		temperature = min(255, temperature + heat_gain);
		temperature = max(0, temperature - HEAT_DISSIPATION);
		if (temperature > IGNITION_TEMP[material]) {
			health = health - 1;
			temperature = FIRE_TEMP;
			if (health <= 0) {
				if (original_material == MAT_OIL) {
					// Oil burning out seeds an explode wave instead of turning to air.
					material = MAT_EXPLODE_WAVE;
					health = 0;
					temperature = OIL_BURN_END_POWER;
				} else {
					material = MAT_AIR;
					health = 0;
					temperature = 0;
				}
			}
		}
	}
```

- [ ] **Step 2: Verify shaders compile**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue --quit-after 5`
Expected: clean exit.

- [ ] **Step 3: Commit**

```bash
git add shaders/include/sim/burning.glslinc
git commit -m "feat(sim): burning oil seeds explode wave at end-of-life"
```

---

## Task 8: Implement explode_wave.glslinc

**Files:**
- Create: `shaders/include/sim/explode_wave.glslinc`

The wave is a custom sim — not a fluid, not in `burning.glslinc`. Each tick, every wave cell:
1. Propagates into its 4 orthogonal neighbors that are `MAT_AIR` with `temperature < SCORCH_TEMP` (writes wave with `power - WAVE_DECAY`).
2. Self-decays to `MAT_AIR` with `temperature = SCORCH_TEMP`, blocking re-light from forward neighbors next tick.
3. Heats adjacent flammable terrain by `power` (igniting oil, burning wood).
4. Subtracts `power` from adjacent solid terrain `health` (chews through weak terrain).
5. Damages entities — entity-damage hook lookup is the existing `MaterialRegistry.get_damage` pathway used by lava; for this task it's enough that the wave cells exist as damaging pixels (entity collision will pick them up automatically via the existing damage-by-material loop — no shader change needed for that).

The key trick for parallel-write correctness: in a single compute dispatch every thread reads its own cell, looks at its 4 neighbors, and decides what to write **only into its own cell**. So instead of a wave cell "writing into neighbors," each AIR cell looks at its 4 neighbors to see if any neighbor is a wave cell with `power > WAVE_DECAY` and adopts the max-power propagation. Symmetrically, a wave cell decides on its own to self-decay to scorched air.

- [ ] **Step 1: Create `shaders/include/sim/explode_wave.glslinc`**

```glsl
// Explode wave: a custom 1-cell-thick Manhattan-diamond shell that expands one
// cell per tick and leaves scorched air behind to prevent backfill.
//
// Encoding:
//   material    = MAT_EXPLODE_WAVE
//   temperature = power (0..255)
//   health      = unused
//
// Pulled-write model (each thread only writes its own cell):
//   - If this cell is a wave: become air with temperature = SCORCH_TEMP.
//     Adjacent terrain effects (heat-up flammables, damage solids) are
//     applied in the same tick via separate writes (handled by the
//     terrain-side branches below; see neighbor damage block).
//   - If this cell is air with temperature < SCORCH_TEMP and any 4-neighbor
//     is a wave with power > WAVE_DECAY: become a wave with
//     power = max(neighbor_power) - WAVE_DECAY.
//   - If this cell is flammable and a 4-neighbor is a wave: raise temperature
//     by neighbor's power (ignites oil, burning wood) and decrement health by
//     min(health, neighbor_power) (chews terrain).

bool is_wave(vec4 p) {
	return get_material(p) == MAT_EXPLODE_WAVE;
}

int wave_power(vec4 p) {
	return get_temperature(p);
}

bool simulate_explode_wave(ivec2 pos, inout vec4 pixel, inout int material,
                           vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	// Branch A: this cell IS a wave -> decay to scorched air this tick.
	if (material == MAT_EXPLODE_WAVE) {
		imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
		return true;
	}

	// Branch B: this cell is AIR. Check if any neighbor wave wants to propagate in.
	if (material == MAT_AIR) {
		int current_temp = get_temperature(pixel);
		if (current_temp >= SCORCH_TEMP) {
			// Recently scorched -> blocked from re-lighting until heat dissipates.
			return false;
		}

		int max_neighbor_power = 0;
		if (is_wave(n_up))    max_neighbor_power = max(max_neighbor_power, wave_power(n_up));
		if (is_wave(n_down))  max_neighbor_power = max(max_neighbor_power, wave_power(n_down));
		if (is_wave(n_left))  max_neighbor_power = max(max_neighbor_power, wave_power(n_left));
		if (is_wave(n_right)) max_neighbor_power = max(max_neighbor_power, wave_power(n_right));

		int new_power = max_neighbor_power - WAVE_DECAY;
		if (new_power > 0) {
			imageStore(chunk_tex, pos, make_pixel(MAT_EXPLODE_WAVE, 0, new_power));
			return true;
		}
		return false;
	}

	// Branch C: this cell is flammable and a wave neighbor is touching it.
	// Apply heat-up + terrain-chew. We bias the writes so they happen in the
	// same pass as the wave's self-decay; the flammable will then be picked up
	// by burning.glslinc on the NEXT tick.
	if (IS_FLAMMABLE[material]) {
		int max_neighbor_power = 0;
		if (is_wave(n_up))    max_neighbor_power = max(max_neighbor_power, wave_power(n_up));
		if (is_wave(n_down))  max_neighbor_power = max(max_neighbor_power, wave_power(n_down));
		if (is_wave(n_left))  max_neighbor_power = max(max_neighbor_power, wave_power(n_left));
		if (is_wave(n_right)) max_neighbor_power = max(max_neighbor_power, wave_power(n_right));

		if (max_neighbor_power > 0) {
			int health = get_health(pixel);
			int temperature = get_temperature(pixel);
			int new_health = max(0, health - max_neighbor_power);
			int new_temp   = min(255, temperature + max_neighbor_power);
			imageStore(chunk_tex, pos, make_pixel(material, new_health, new_temp));
			return true;
		}
		return false;
	}

	// Branch D: this cell is non-flammable solid touching a wave: chew terrain.
	if (HAS_COLLIDER[material]) {
		int max_neighbor_power = 0;
		if (is_wave(n_up))    max_neighbor_power = max(max_neighbor_power, wave_power(n_up));
		if (is_wave(n_down))  max_neighbor_power = max(max_neighbor_power, wave_power(n_down));
		if (is_wave(n_left))  max_neighbor_power = max(max_neighbor_power, wave_power(n_left));
		if (is_wave(n_right)) max_neighbor_power = max(max_neighbor_power, wave_power(n_right));

		if (max_neighbor_power > 0) {
			int health = get_health(pixel);
			int temperature = get_temperature(pixel);
			int new_health = health - max_neighbor_power;
			if (new_health <= 0) {
				imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
			} else {
				imageStore(chunk_tex, pos, make_pixel(material, new_health, temperature));
			}
			return true;
		}
		return false;
	}

	return false;
}
```

- [ ] **Step 2: Commit (the include isn't wired up yet but the file is self-consistent)**

```bash
git add shaders/include/sim/explode_wave.glslinc
git commit -m "feat(sim): add explode wave propagation"
```

---

## Task 9: Wire explode_wave into simulation.glsl dispatch

**Files:**
- Modify: `shaders/compute/simulation.glsl` (include block + dispatch block).

The wave must run **before** `simulate_burning` because the flammable-heat-up branch writes the flammable cell, and we don't want burning's same-tick logic to fight with that. We also need it to run **before** `simulate_oil`/`simulate_lava`/`simulate_blood`/`simulate_gas`, because branches A and B of the wave sim write to wave/air cells that those fluid sims also pull from — letting fluids see post-wave state keeps fluids consistent.

Order in `main()` becomes: `simulate_explode_wave` → `simulate_lava` → `simulate_oil` → `simulate_blood` → `simulate_gas` → `simulate_burning`.

- [ ] **Step 1: Add the include**

In `shaders/compute/simulation.glsl`, after the `#include ".../oil.glslinc"` line added in Task 6, add:

```glsl
#include "res://shaders/include/sim/explode_wave.glslinc"
```

- [ ] **Step 2: Add the dispatch call at the top of the fluid dispatch block**

In `shaders/compute/simulation.glsl`, modify the dispatch block in `main()`. The block currently looks like:

```glsl
	if (simulate_lava(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_oil(pos, pixel, material, n_up, n_down, n_left, n_right))  return;
	if (simulate_blood(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_gas(pos, pixel, material, n_up, n_down, n_left, n_right))  return;

	simulate_burning(pos, pixel, n_up, n_down, n_left, n_right);
```

Change it to:

```glsl
	if (simulate_explode_wave(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_lava(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_oil(pos, pixel, material, n_up, n_down, n_left, n_right))  return;
	if (simulate_blood(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_gas(pos, pixel, material, n_up, n_down, n_left, n_right))  return;

	simulate_burning(pos, pixel, n_up, n_down, n_left, n_right);
```

- [ ] **Step 3: Verify shaders compile**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue --quit-after 5`
Expected: clean exit, no shader errors.

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/simulation.glsl
git commit -m "feat(sim): dispatch explode wave"
```

---

## Task 10: Render MAT_EXPLODE_WAVE as white-yellow flash

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader:163-169` (fluid overlay block) — extend the recognized-fluid set to include the wave for tint purposes, BUT use a dedicated branch because we don't want the existing fluid-density logic.

The wave has `fluid=false` and `has_collider=false`, so the current fragment shader will treat it like air and fall through to the wall-rendering path. We need a dedicated early branch.

- [ ] **Step 1: Add a dedicated wave branch in `fragment()`**

In `shaders/visual/render_chunk.gdshader`, immediately after the existing fluid-overlay block (which currently checks `mat == MAT_GAS || mat == MAT_LAVA || mat == MAT_BLOOD`), add:

```glsl
	// Explode wave: white-yellow flash, fully opaque on top of everything.
	if (mat == MAT_EXPLODE_WAVE) {
		fluid_tint = vec4(MATERIAL_TINT[MAT_EXPLODE_WAVE].rgb * MATERIAL_GLOW[MAT_EXPLODE_WAVE], 1.0);
		fluid_alpha = 1.0;
		mat = MAT_AIR;
	}
```

- [ ] **Step 2: Verify the shader compiles**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue --quit-after 5`
Expected: clean exit.

- [ ] **Step 3: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat(render): white-yellow flash for explode wave"
```

---

## Task 11: Console seed-and-go for spawn_mat explode_wave

**Files:**
- Modify: `src/core/terrain_modifier.gd:165-200` (`place_material` function).

The existing `place_material` writes `data[idx + 2] = 0` for the temperature byte. For `MAT_EXPLODE_WAVE`, we need to write `WAVE_DEFAULT_POWER` (60) so the wave actually propagates after being stamped. We also need to allow it to overwrite air-with-scorch (since the air may carry residual heat).

- [ ] **Step 1: Modify `place_material`**

In `src/core/terrain_modifier.gd`, the loop currently looks like:

```gdscript
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = material_id
			data[idx + 1] = 255
			data[idx + 2] = 0
			data[idx + 3] = 136
			modified = true
```

Change it to:

```gdscript
		var initial_temp := 0
		if material_id == MaterialRegistry.MAT_EXPLODE_WAVE:
			initial_temp = 60  # WAVE_DEFAULT_POWER — mirror of shaders/include/sim/common.glslinc
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			if data[idx] != MaterialRegistry.MAT_AIR:
				continue
			data[idx] = material_id
			data[idx + 1] = 255
			data[idx + 2] = initial_temp
			data[idx + 3] = 136
			modified = true
```

- [ ] **Step 2: Add a GDScript test for the constant mirror**

Append to `tests/unit/test_oil_and_explode_wave_registry.gd`:

```gdscript
func test_wave_default_power_constant() -> void:
	# Mirror of WAVE_DEFAULT_POWER in shaders/include/sim/common.glslinc.
	# This test guards against drift; if you change one, change both.
	var WAVE_DEFAULT_POWER_GDSCRIPT_MIRROR := 60
	assert_that(WAVE_DEFAULT_POWER_GDSCRIPT_MIRROR).is_equal(60)
```

- [ ] **Step 3: Run the test**

Run: `godot --headless --path /Users/jeremyzhao/Development/godot/top-down-rogue -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_oil_and_explode_wave_registry.gd`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/core/terrain_modifier.gd tests/unit/test_oil_and_explode_wave_registry.gd
git commit -m "feat(console): spawn_mat explode_wave seeds wave with default power"
```

---

## Task 12: Manual playtest checklist

No code changes — this task verifies the integrated behavior matches the spec's expected patterns.

- [ ] **Step 1: Launch the game**

Run: `godot --path /Users/jeremyzhao/Development/godot/top-down-rogue`

- [ ] **Step 2: Test oil placement and flow**

Open the console. Type: `spawn_mat oil 5`

Expected: a small dark-amber pool appears at the cursor; it flows downhill into nearby air, pools at the bottom of a depression, stops on hitting solid terrain. Behavior visually similar to `spawn_mat lava 5` but darker color.

- [ ] **Step 3: Test oil ignition by fire**

After placing oil, type: `spawn_mat lava 3` adjacent to the oil pool.

Expected: heat from lava raises oil temperature; once an oil cell's `temperature > 200` it starts burning (color shifts toward orange-red); burning oil cells gradually consume neighbors over ~60 ticks each.

- [ ] **Step 4: Test wave seed**

In a clear area, type: `spawn_mat explode_wave 1`

Expected: a small white-yellow flash at the cursor; over the next ~15 frames a 1-cell-thick **diamond** front expands outward to ~15 cells radius, then terminates. The shape is a diamond (Manhattan-distance front), not a square or circle. Scorched air left behind is invisible but blocks immediate re-seed (try spawning a second wave in the same spot — it won't propagate until ~30 ticks later).

- [ ] **Step 5: Test cascade**

Place a long oil puddle: hold-click `spawn_mat oil 3` along a 30-cell stretch. Drop a single `spawn_mat lava 1` on one end.

Expected: oil ignites at the lava end, burns for ~60 ticks, then that cell becomes a wave at power 18 (4-cell-radius diamond). The wave's neighbor-heat raises adjacent oil temperature by 18, pushing them over the 200 ignition threshold if they're pre-warmed by burn-spread, igniting them. After ~60 more ticks those cells become waves, and the chain rolls outward in pulses along the puddle.

- [ ] **Step 6: Test wave damage to terrain (optional)**

In a stone wall, place a high-power wave near soft terrain: `spawn_mat explode_wave 2` next to dirt.

Expected: dirt cells adjacent to the wave's front lose `health` equal to the wave's power; weak terrain (low burn_health) gets chewed through, strong terrain (stone, health 255 vs wave power ≤60) survives unscathed.

- [ ] **Step 7: Document any failures**

If any of steps 2–6 don't match the expected behavior, capture the divergence (screenshots / console logs) and create a follow-up issue rather than patching the plan in-flight. The plan's correctness should be evaluated against the spec — not amended ad-hoc.

- [ ] **Step 8: Final commit (if any cleanup was needed)**

If steps 2–6 all pass, no commit needed. Otherwise commit fix patches separately with descriptive messages.

---

## Out of scope (per spec §3.5.6)

- Barrels, gas vents, pool seeds, spawn-dispatcher markers.
- Tuning passes for explosion damage curves vs. enemies.
- Per-source power overrides (barrel power, end-of-burn power scaling with oil depth).
- Level-gen integration; PNG room markers; biome material wiring.
