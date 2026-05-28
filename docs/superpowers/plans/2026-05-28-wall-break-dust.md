# Wall-break Dust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Breaking walls bursts out a dense, sluggish, GPU-simulated `MAT_DUST` fluid colored like the wall it came from, settling permanently in place.

**Architecture:** Add `MAT_DUST` to the material registry and regenerate the GLSL/gdshader material includes. Add a new pull-based advection sim (`dust.glslinc`) mirroring `blood.glslinc` but tuned to settle fast and barely spread, carrying its source wall id in the B channel. Inject dust on a fraction of destroyed wall pixels inside `melee_arc.glsl`'s solid carve pass, and render it in `render_chunk.gdshader` tinted by the source wall's texture color.

**Tech Stack:** Godot 4 (GDScript autoloads, GLSL compute shaders via RenderingDevice, canvas_item visual shaders), gdUnit4 tests.

---

## Reference: spec

Full design: `docs/superpowers/specs/2026-05-28-wall-break-dust-design.md`. Read it before starting.

## File Structure

- **Modify** `src/autoload/material_registry.gd` — register `MAT_DUST` (fluid, no collider).
- **Regenerate** `shaders/generated/materials.glslinc` and `shaders/generated/materials.gdshaderinc` — via `tools/generate_material_glsl.gd`; adds `MAT_DUST`, updates `MAT_COUNT` and all material arrays. Do not hand-edit.
- **Create** `shaders/include/sim/dust.glslinc` — dust advection sim + `simulate_dust`.
- **Modify** `shaders/compute/simulation.glsl` — include dust sim and call it in the fluid dispatch.
- **Modify** `shaders/compute/melee_arc.glsl` — inject dust on a hashed fraction of destroyed wall pixels.
- **Modify** `shaders/visual/render_chunk.gdshader` — render `MAT_DUST` tinted by source wall color.
- **Create** `tests/unit/test_dust_material.gd` — assert the registry properties of `MAT_DUST`.

## Channel layout (dust)

| Channel | Meaning |
|---------|---------|
| R | `MAT_DUST` |
| G | density 0–255 |
| B | source wall material id (DIRT/WOOD/STONE/COAL/ICE) |
| A | packed velocity `vx<<4 | vy`, each biased by 8 |

---

## Task 1: Register MAT_DUST and regenerate material includes

**Files:**
- Test: `tests/unit/test_dust_material.gd` (create)
- Modify: `src/autoload/material_registry.gd`
- Regenerate: `shaders/generated/materials.glslinc`, `shaders/generated/materials.gdshaderinc`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_dust_material.gd`:

```gdscript
extends GdUnitTestSuite

func test_dust_is_registered() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_DUST).is_greater(0)

func test_dust_is_fluid_no_collider() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.is_fluid(registry.MAT_DUST)).is_true()
	assert_bool(registry.has_collider(registry.MAT_DUST)).is_false()

func test_dust_is_inert() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.is_flammable(registry.MAT_DUST)).is_false()
	assert_that(registry.get_hardness(registry.MAT_DUST)).is_equal(0.0)
	assert_that(registry.get_damage(registry.MAT_DUST)).is_equal(0)

func test_dust_in_get_fluids() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.get_fluids().has(registry.MAT_DUST)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_dust_material.gd`
Expected: FAIL — `MAT_DUST` is not a declared property on the registry (parse/identifier error or null).

- [ ] **Step 3: Declare the MAT_DUST variable**

In `src/autoload/material_registry.gd`, add the declaration alongside the other `MAT_*` vars (after `var MAT_EXPLODE_WAVE: int` near line 61):

```gdscript
	var MAT_EXPLODE_WAVE: int
	var MAT_DUST: int
```

- [ ] **Step 4: Register the dust material**

In `src/autoload/material_registry.gd`, at the end of `_init_materials()` (immediately after the `mat_explode_wave` block that sets `MAT_EXPLODE_WAVE = mat_explode_wave.id`, around line 210), append:

```gdscript
		var mat_dust := MaterialDef.new(
			"DUST", "",
			false, 0, 0,
			false, false,
			Color(0.6, 0.6, 0.6, 0.85),
			true
		)
		mat_dust.id = materials.size()
		materials.append(mat_dust)
		MAT_DUST = mat_dust.id
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_dust_material.gd`
Expected: PASS (4 tests).

- [ ] **Step 6: Regenerate the material includes**

Run: `godot --headless --script res://tools/generate_material_glsl.gd`
Expected output:
```
Generated shaders/generated/materials.glslinc
Generated shaders/generated/materials.gdshaderinc
```

Verify the new constant landed:

Run: `grep -n "MAT_DUST\|MAT_COUNT" shaders/generated/materials.glslinc`
Expected: `const int MAT_COUNT = 13;` and `const int MAT_DUST = 12;`, and the `IS_FLUID` entry for index 12 is `true`, `HAS_COLLIDER` index 12 is `false`.

- [ ] **Step 7: Confirm existing registry tests still pass**

Run: `./addons/gdUnit4/runtest.sh -a tests/unit/test_material_hardness.gd -a tests/unit/test_material_hazard_bits.gd`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add src/autoload/material_registry.gd tests/unit/test_dust_material.gd shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "feat: register MAT_DUST material"
```

---

## Task 2: Create the dust simulation include

**Files:**
- Create: `shaders/include/sim/dust.glslinc`

No unit test — GPU compute shaders are not unit-testable in this project. Correctness is verified by the game running without shader-compile errors (Task 3) and by manual verification (Task 6). This task only creates the file; it is not wired in until Task 3.

- [ ] **Step 1: Create `shaders/include/sim/dust.glslinc`**

This mirrors `shaders/include/sim/blood.glslinc` (a pull-based velocity-advected density fluid) with four behavioral changes: (1) B channel carries the source wall id, propagated through advection; (2) per-cell outflow cap is `density/4` instead of `density/2`; (3) velocity gets strong friction every step and snaps to rest, so dust settles fast; (4) dust dampens against solids (piles up) instead of reflecting, and persists until fully drained (cleared only at density 0, no dissipate threshold).

Note on tuning: the `stochastic_div` denominator stays `V_MAX_OUTFLOW` (=8). That value normalizes the velocity nibble (0..8) to a fraction of density; changing it would break the velocity scale. Sluggishness comes from the `DUST_OUTFLOW_DIV` cap and the friction, not from that denominator.

```glsl
const int DUST_OUTFLOW_DIV = 4;       // per-cell outflow cap = density / DUST_OUTFLOW_DIV (blood uses 2)
const int THRESHOLD_BECOME_DUST = 8;  // air needs this much inflow to become dust (blood uses 1)

int get_density_dust(vec4 p) { return int(round(p.g * 255.0)); }
int get_source_dust(vec4 p)  { return int(round(p.b * 255.0)); }

ivec2 unpack_velocity_dust(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_dust(int density, ivec2 vel, int source) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_DUST) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		float(clamp(source, 0, 255)) / 255.0,
		float(a) / 255.0
	);
}

bool is_solid_for_dust(int mat) {
	return mat != MAT_AIR && mat != MAT_DUST;
}

void dust_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
	int material = get_material(pixel);

	int n_mat_up    = get_material(n_up);
	int n_mat_down  = get_material(n_down);
	int n_mat_left  = get_material(n_left);
	int n_mat_right = get_material(n_right);

	bool any_dust_neighbor =
		n_mat_up == MAT_DUST || n_mat_down == MAT_DUST ||
		n_mat_left == MAT_DUST || n_mat_right == MAT_DUST;

	if (material == MAT_AIR && !any_dust_neighbor) {
		return;
	}

	int density = (material == MAT_DUST) ? get_density_dust(pixel) : 0;
	ivec2 vel   = (material == MAT_DUST) ? unpack_velocity_dust(pixel) : ivec2(0);
	int source  = (material == MAT_DUST) ? get_source_dust(pixel) : 0;

	int comp_up    = max(0, -vel.y);
	int comp_down  = max(0,  vel.y);
	int comp_left  = max(0, -vel.x);
	int comp_right = max(0,  vel.x);

	if (is_solid_for_dust(n_mat_up))    comp_up    = 0;
	if (is_solid_for_dust(n_mat_down))  comp_down  = 0;
	if (is_solid_for_dust(n_mat_left))  comp_left  = 0;
	if (is_solid_for_dust(n_mat_right)) comp_right = 0;

	int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 11u);
	int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 12u);
	int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 13u);
	int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 14u);

	int total_out = out_up + out_down + out_left + out_right;
	int max_outflow = min(density, max(1, density / DUST_OUTFLOW_DIV));
	if (total_out > max_outflow) {
		out_up    = out_up    * max_outflow / max(1, total_out);
		out_down  = out_down  * max_outflow / max(1, total_out);
		out_left  = out_left  * max_outflow / max(1, total_out);
		out_right = out_right * max_outflow / max(1, total_out);
		total_out = out_up + out_down + out_left + out_right;
	}

	int in_up = 0, in_down = 0, in_left = 0, in_right = 0;
	ivec2 vin_up = ivec2(0), vin_down = ivec2(0), vin_left = ivec2(0), vin_right = ivec2(0);
	int src_up = 0, src_down = 0, src_left = 0, src_right = 0;

	if (n_mat_up == MAT_DUST) {
		int dN = get_density_dust(n_up);
		ivec2 vN = unpack_velocity_dust(n_up);
		in_up = stochastic_div(dN * max(0, vN.y), V_MAX_OUTFLOW, pos, 15u);
		vin_up = vN; src_up = get_source_dust(n_up);
	}
	if (n_mat_down == MAT_DUST) {
		int dN = get_density_dust(n_down);
		ivec2 vN = unpack_velocity_dust(n_down);
		in_down = stochastic_div(dN * max(0, -vN.y), V_MAX_OUTFLOW, pos, 16u);
		vin_down = vN; src_down = get_source_dust(n_down);
	}
	if (n_mat_left == MAT_DUST) {
		int dN = get_density_dust(n_left);
		ivec2 vN = unpack_velocity_dust(n_left);
		in_left = stochastic_div(dN * max(0, vN.x), V_MAX_OUTFLOW, pos, 17u);
		vin_left = vN; src_left = get_source_dust(n_left);
	}
	if (n_mat_right == MAT_DUST) {
		int dN = get_density_dust(n_right);
		ivec2 vN = unpack_velocity_dust(n_right);
		in_right = stochastic_div(dN * max(0, -vN.x), V_MAX_OUTFLOW, pos, 18u);
		vin_right = vN; src_right = get_source_dust(n_right);
	}

	int total_in = in_up + in_down + in_left + in_right;

	// Dampen against solids (pile up) instead of bouncing like blood.
	if (is_solid_for_dust(n_mat_up)    && vel.y < 0) vel.y = 0;
	if (is_solid_for_dust(n_mat_down)  && vel.y > 0) vel.y = 0;
	if (is_solid_for_dust(n_mat_left)  && vel.x < 0) vel.x = 0;
	if (is_solid_for_dust(n_mat_right) && vel.x > 0) vel.x = 0;

	int new_density = clamp(density - total_out + total_in, 0, 255);

	int stayed = max(0, density - total_out);
	int weight = max(1, stayed + total_in);
	ivec2 vsum = vel * stayed
	           + vin_up * in_up + vin_down * in_down
	           + vin_left * in_left + vin_right * in_right;
	ivec2 new_vel = vsum / weight;
	// Strong friction every step, then snap to rest so dust settles fast.
	new_vel = (new_vel * 12) / 16;
	if (max(abs(new_vel.x), abs(new_vel.y)) <= 1) new_vel = ivec2(0);
	new_vel = clamp(new_vel, ivec2(-8), ivec2(7));

	if (material == MAT_AIR) {
		if (total_in >= THRESHOLD_BECOME_DUST) {
			// Inherit source from the dominant inflow neighbor.
			int best_in = in_up; int best_src = src_up;
			if (in_down  > best_in) { best_in = in_down;  best_src = src_down; }
			if (in_left  > best_in) { best_in = in_left;  best_src = src_left; }
			if (in_right > best_in) { best_in = in_right; best_src = src_right; }

			ivec2 inflow_vel = ivec2(0);
			if (total_in > 0) {
				inflow_vel = (vin_up * in_up + vin_down * in_down + vin_left * in_left + vin_right * in_right) / total_in;
				inflow_vel = (inflow_vel * 12) / 16;
				if (max(abs(inflow_vel.x), abs(inflow_vel.y)) <= 1) inflow_vel = ivec2(0);
				inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
			}
			imageStore(chunk_tex, pos, pack_dust(total_in, inflow_vel, best_src));
		}
		return;
	}

	// Persist: clear only when fully drained (no time-based dissipation).
	if (new_density <= 0) {
		imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
		return;
	}
	imageStore(chunk_tex, pos, pack_dust(new_density, new_vel, source));
}

bool simulate_dust(ivec2 pos, inout vec4 pixel, inout int material,
                   vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	if (material != MAT_DUST && material != MAT_AIR) return false;
	dust_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
	if (material == MAT_DUST) return true;
	pixel = imageLoad(chunk_tex, pos);
	material = get_material(pixel);
	return material == MAT_DUST;
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/sim/dust.glslinc
git commit -m "feat: add dust fluid simulation include"
```

---

## Task 3: Wire dust into the simulation dispatch

**Files:**
- Modify: `shaders/compute/simulation.glsl`

- [ ] **Step 1: Include the dust sim**

In `shaders/compute/simulation.glsl`, add the include after the blood include (line 40, `#include "res://shaders/include/sim/blood.glslinc"`):

```glsl
#include "res://shaders/include/sim/blood.glslinc"
#include "res://shaders/include/sim/dust.glslinc"
#include "res://shaders/include/sim/injection.glslinc"
```

- [ ] **Step 2: Call simulate_dust in the fluid dispatch**

In the same file, in `main()`, add the dust call immediately after the blood call (line 69, `if (simulate_blood(...)) return;`):

```glsl
	if (simulate_blood(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_dust(pos, pixel, material, n_up, n_down, n_left, n_right))  return;
	if (simulate_gas(pos, pixel, material, n_up, n_down, n_left, n_right))   return;
```

- [ ] **Step 3: Verify the shader compiles by launching the game**

Run: `godot --quit-after 4` (opens the project, compiles shaders, then exits).
Expected: process exits cleanly with no `ERROR`/shader-compile messages mentioning `dust.glslinc`, `simulation.glsl`, or `MAT_DUST`. If errors appear, fix the GLSL before continuing.

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/simulation.glsl
git commit -m "feat: dispatch dust simulation"
```

---

## Task 4: Inject dust on wall break in melee_arc.glsl

**Files:**
- Modify: `shaders/compute/melee_arc.glsl`

The solid carve pass currently clears each destroyed wall pixel to air (line 82) then records a hit. We replace the unconditional clear with: record the hit (unchanged), then for a hashed ~35% of destroyed pixels write a dust pixel (source id in B, outward velocity in A) instead of air. Because the carve pass only targets solid wall types (`is_target` gate at line 71), dust is created only by destroying walls — never by swinging through air or existing dust.

- [ ] **Step 1: Add the hash helper and tuning constants**

In `shaders/compute/melee_arc.glsl`, after the `is_target` function (ends line 42) and before `hardness_for` (line 44), add:

```glsl
const int DUST_SPAWN_PERCENT = 35;   // % of destroyed wall pixels that become dust
const float DUST_BURST_SPEED = 120.0; // outward burst speed (world units/sec)
const int DUST_BURST_DENSITY = 200;   // initial density of spawned dust

uint dust_hash(uint n) {
	n = (n >> 16) ^ n;
	n *= 0xed5ad0bbu;
	n = (n >> 16) ^ n;
	n *= 0xac4c1b51u;
	n = (n >> 16) ^ n;
	return n;
}
```

- [ ] **Step 2: Replace the clear with hit-record + dust injection**

In `shaders/compute/melee_arc.glsl`, the current `is_solid_pass` block is:

```glsl
		imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));

		uint idx = atomicAdd(hit_list.count, 1u);
		if (idx < pc.hit_capacity) {
			hit_list.entries[idx].world_x = int(world_pos.x);
			hit_list.entries[idx].world_y = int(world_pos.y);
			hit_list.entries[idx].mat_id = mat;
			hit_list.entries[idx].scale = scale_clamped;
		}
```

Replace it with (record the hit first, then choose dust-or-air for the cleared pixel):

```glsl
		uint idx = atomicAdd(hit_list.count, 1u);
		if (idx < pc.hit_capacity) {
			hit_list.entries[idx].world_x = int(world_pos.x);
			hit_list.entries[idx].world_y = int(world_pos.y);
			hit_list.entries[idx].mat_id = mat;
			hit_list.entries[idx].scale = scale_clamped;
		}

		uint h = dust_hash(uint(int(world_pos.x)) ^ dust_hash(uint(int(world_pos.y))));
		if (int(h % 100u) < DUST_SPAWN_PERCENT) {
			float len = length(to_pixel);
			vec2 outward = (len > 0.0001) ? to_pixel / len : pc.direction;
			float vx_f = outward.x * DUST_BURST_SPEED / 60.0;
			float vy_f = outward.y * DUST_BURST_SPEED / 60.0;
			int vx_enc = clamp(int(round(vx_f)) + 8, 0, 15);
			int vy_enc = clamp(int(round(vy_f)) + 8, 0, 15);
			float packed = float((vx_enc << 4) | vy_enc) / 255.0;
			imageStore(chunk_tex, local, vec4(
				float(MAT_DUST) / 255.0,
				float(DUST_BURST_DENSITY) / 255.0,
				float(mat) / 255.0,
				packed
			));
		} else {
			imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));
		}
```

(`to_pixel`, `world_pos`, `mat`, `pc.direction`, and `pc.hit_capacity` are all already in scope from earlier in `main()`.)

- [ ] **Step 3: Verify the shader compiles by launching the game**

Run: `godot --quit-after 4`
Expected: clean exit, no shader-compile errors mentioning `melee_arc.glsl` or `MAT_DUST`.

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/melee_arc.glsl
git commit -m "feat: inject dust burst on wall break"
```

---

## Task 5: Render dust tinted by source wall color

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader`

- [ ] **Step 1: Add a MAT_DUST overlay branch**

In `shaders/visual/render_chunk.gdshader`, the existing fluid overlay block is:

```glsl
	if (mat == MAT_GAS || mat == MAT_LAVA || mat == MAT_BLOOD) {
		vec4 tint = MATERIAL_TINT[mat];
		fluid_tint = vec4(tint.rgb * MATERIAL_GLOW[mat], 1.0);
		// Ensure visibility even at low density: minimum 25% alpha, scales to tint.a at max
		fluid_alpha = mix(0.25, tint.a, data.g);
		mat = MAT_AIR;
	}
```

Immediately after that block (before the `MAT_EXPLODE_WAVE` block), add:

```glsl
	if (mat == MAT_DUST) {
		// B carries the source wall id; tint dust with that wall's own color,
		// lightened so it reads as airborne dust rather than solid wall.
		int dust_src = int(round(data.b * 255.0));
		vec3 dust_rgb = get_material_top_color(dust_src, px.x);
		dust_rgb = mix(dust_rgb, vec3(1.0), 0.25);
		fluid_tint = vec4(dust_rgb, 1.0);
		fluid_alpha = mix(0.4, 0.95, data.g);
		mat = MAT_AIR;
	}
```

(`get_material_top_color` is defined at line 104, above `fragment()`, and samples the material texture array — so dust inherits the exact wall palette.)

- [ ] **Step 2: Verify the shader compiles by launching the game**

Run: `godot --quit-after 4`
Expected: clean exit, no shader-compile errors mentioning `render_chunk.gdshader` or `MAT_DUST`.

- [ ] **Step 3: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: render dust tinted by source wall color"
```

---

## Task 6: Manual verification

**Files:** none (verification only).

GPU simulation feel cannot be unit-tested; verify it by playing. Use the `run` skill or launch the project directly.

- [ ] **Step 1: Launch the game and reach a level with breakable walls**

Run the project (e.g. `godot` or the `run` skill). Get the player next to a wall.

- [ ] **Step 2: Verify each acceptance criterion**

- [ ] Carve each wall type (dirt, wood, stone, coal, ice). Dust bursts outward in roughly that wall's color (brown / tan / grey / near-black / pale blue).
- [ ] The carved cavity stays mostly open — only a fraction of the broken volume becomes dust.
- [ ] Dust settles quickly (sluggish, barely spreads) and then stays put — it does not fade over time.
- [ ] Swinging the weapon through empty air produces no dust.
- [ ] Swinging through already-settled dust does not create new dust (it only nudges/pushes it).
- [ ] Walking through dust does not block the player (no collision).
- [ ] The existing flying-chip particles still appear on wall breaks (unchanged).

- [ ] **Step 3: Tune if needed**

If the feel is off, adjust and re-verify. Knobs:
- `melee_arc.glsl`: `DUST_SPAWN_PERCENT` (how much dust), `DUST_BURST_SPEED` (how far it sprays), `DUST_BURST_DENSITY` (opacity).
- `dust.glslinc`: `DUST_OUTFLOW_DIV` and the `* 12 / 16` friction factor (spread vs settle speed), `THRESHOLD_BECOME_DUST` (pile tightness).
- `render_chunk.gdshader`: the `mix(dust_rgb, vec3(1.0), 0.25)` lighten and the `mix(0.4, 0.95, data.g)` alpha range (color readability).

No commit unless tuning constants were changed; if so:

```bash
git add -A
git commit -m "tune: dust burst feel"
```

---

## Self-Review Notes

- **Spec coverage:** material registration (T1), pixel layout B=source (T1 channel doc + T2 pack_dust), sluggish sim with source propagation/dampen/persist (T2), dispatch (T3), fraction-burst injection gated to walls (T4), source-tinted render (T5), tests + manual feel + tuning knobs (T1, T6). Existing chips untouched (verified T6). All spec sections map to a task.
- **Tuning correction vs spec:** the spec's "DUST_MAX_OUTFLOW ≈ 4 lowers the stochastic_div denominator" was imprecise — a lower denominator *increases* outflow. This plan keeps `V_MAX_OUTFLOW` as the velocity normalization and uses `DUST_OUTFLOW_DIV` as the per-cell cap plus friction for sluggishness. Net effect matches the spec's intent (dust barely flows, settles fast).
- **Type consistency:** `pack_dust(density, vel, source)`, `get_source_dust`, `simulate_dust` signature mirrors `simulate_blood`; `MAT_DUST` produced by the generator in T1 is consumed by T2/T4/T5.
