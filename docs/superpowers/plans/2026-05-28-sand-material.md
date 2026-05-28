# Sand Material Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a MAT_SAND fluid material that spawns when walls are destroyed, behaving like dense sticky blood (high velocity damping, low outflow, no dissipation) with a burst velocity on spawn.

**Architecture:** Fork blood.glslinc into sand.glslinc with tuned constants (1/2 damping instead of 15/16, density/4 outflow instead of density/2, no dissipation). Add MAT_SAND to MaterialRegistry, regenerate GLSL includes. Modify melee_arc.glsl to write sand (not air) for destroyed solid cells based on per-material destruction probability. Add CPU-side `place_sand()` mirroring `place_blood()`. Wire sand into simulation.glsl priority chain (after oil, before blood).

**Tech Stack:** Godot 4.x, GLSL compute shaders, GDScript

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `shaders/include/sim/sand.glslinc` | Create | Sand fluid simulation (fork of blood) |
| `shaders/include/sim/common.glslinc` | Modify | Add THRESHOLD_BECOME_SAND constant |
| `shaders/compute/simulation.glsl` | Modify | Include sand.glslinc, add simulate_sand call |
| `shaders/compute/melee_arc.glsl` | Modify | Destruction distribution: spawn sand with velocity instead of air |
| `shaders/include/sim/blood.glslinc` | Modify | Update is_solid_for_blood to allow sand |
| `shaders/include/sim/oil.glslinc` | Modify | Update is_solid_for_oil to allow sand |
| `shaders/include/sim/lava.glslinc` | Modify | Update is_solid_for_lava to allow sand |
| `shaders/include/sim/gas.glslinc` | Modify | Update is_solid_for_gas to allow sand |
| `shaders/include/sim/explode_wave.glslinc` | Modify | Destruction: spawn sand instead of air for destroyed solids |
| `src/autoload/material_registry.gd` | Modify | Add MAT_SAND MaterialDef |
| `shaders/generated/materials.glslinc` | Regenerate | Auto-generated with MAT_SAND = 12 |
| `shaders/generated/materials.gdshaderinc` | Regenerate | Auto-generated with MAT_SAND = 12 |
| `src/core/terrain_surface.gd` | Modify | Add place_sand() |
| `src/core/terrain_modifier.gd` | Modify | Add place_sand() |
| `src/core/world_manager.gd` | Modify | Add place_sand() passthrough |
| `src/core/juice/terrain_impact.gd` | Modify | Add sand impact particles |

---

### Task 1: Add MAT_SAND to MaterialRegistry

**Files:**
- Modify: `src/autoload/material_registry.gd`

- [ ] **Step 1: Add MAT_SAND variable and MaterialDef entry**

Add after the `MAT_EXPLODE_WAVE` block (line 210) in `_init_materials()`:

```gdscript
var mat_sand := MaterialDef.new(
	"SAND", "",
	false, 0, 0,
	false, false,
	Color(0.6, 0.55, 0.45, 1.0),
	true,
	0,
	1.0,
	0.0
)
mat_sand.id = materials.size()
materials.append(mat_sand)
MAT_SAND = mat_sand.id
```

Add the class variable declaration alongside the others (after line 61):

```gdscript
var MAT_SAND: int
```

- [ ] **Step 2: Verify the script has no syntax errors**

Run the Godot project (or check for parse errors). MAT_SAND should now be material ID 12.

- [ ] **Step 3: Commit**

```bash
git add src/autoload/material_registry.gd
git commit -m "feat: add MAT_SAND to MaterialRegistry"
```

---

### Task 2: Regenerate GLSL material includes

**Files:**
- Modify: `shaders/generated/materials.glslinc` (regenerated)
- Modify: `shaders/generated/materials.gdshaderinc` (regenerated)

- [ ] **Step 1: Run the generation script**

```bash
cd /Users/jeremyzhao/Development/godot/top-down-rogue && godot --headless --script res://tools/generate_material_glsl.gd
```

This auto-generates `shaders/generated/materials.glslinc` and `shaders/generated/materials.gdshaderinc` from the current MaterialRegistry, now including `MAT_SAND = 12`, `IS_FLUID[12] = true`, etc.

- [ ] **Step 2: Verify the generated files contain MAT_SAND**

Spot-check that `materials.glslinc` now has:
- `const int MAT_SAND = 12;`
- `IS_FLUID[13]` array with `true` at index 12
- `MATERIAL_TINT[13]` with the sandy beige color

- [ ] **Step 3: Commit**

```bash
git add shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "feat: regenerate GLSL includes with MAT_SAND"
```

---

### Task 3: Create sand.glslinc simulation shader

**Files:**
- Create: `shaders/include/sim/sand.glslinc`

- [ ] **Step 1: Create sand.glslinc**

Create `/Users/jeremyzhao/Development/godot/top-down-rogue/shaders/include/sim/sand.glslinc` with the following content. This is a fork of blood.glslinc with these differences:
- Uses `MAT_SAND` instead of `MAT_BLOOD`
- `is_solid_for_sand()` returns true for everything except AIR, SAND, and WATER (sand can flow into water)
- Velocity damping is `new_vel / 2` instead of `(new_vel * 15) / 16`
- Max outflow is `density / 4` instead of `density / 2`
- Uses `THRESHOLD_BECOME_SAND` instead of `THRESHOLD_BECOME_BLOOD`
- No dissipation threshold — sand at density 0 converts to AIR, but sand at any density >= 1 persists
- Stochastic `salt` values offset from blood's to avoid correlation (11u–18u instead of 1u–8u)

```glsl
int get_density_sand(vec4 p) { return int(round(p.g * 255.0)); }

ivec2 unpack_velocity_sand(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_sand(int density, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_SAND) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		0.0,
		float(a) / 255.0
	);
}

bool is_solid_for_sand(int mat) {
	return mat != MAT_AIR && mat != MAT_SAND && mat != MAT_WATER;
}

void sand_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
	int material = get_material(pixel);

	int n_mat_up    = get_material(n_up);
	int n_mat_down  = get_material(n_down);
	int n_mat_left  = get_material(n_left);
	int n_mat_right = get_material(n_right);

	bool any_sand_neighbor =
		n_mat_up == MAT_SAND || n_mat_down == MAT_SAND ||
		n_mat_left == MAT_SAND || n_mat_right == MAT_SAND;

	if (material == MAT_AIR && !any_sand_neighbor) {
		return;
	}

	// Water cells can receive sand inflow; treat water like air for this cell's entry.
	if (material == MAT_WATER && !any_sand_neighbor) {
		return;
	}

	int density = (material == MAT_SAND) ? get_density_sand(pixel) : 0;
	ivec2 vel = (material == MAT_SAND) ? unpack_velocity_sand(pixel) : ivec2(0);

	int comp_up    = max(0, -vel.y);
	int comp_down  = max(0,  vel.y);
	int comp_left  = max(0, -vel.x);
	int comp_right = max(0,  vel.x);

	if (is_solid_for_sand(n_mat_up))    comp_up    = 0;
	if (is_solid_for_sand(n_mat_down))  comp_down  = 0;
	if (is_solid_for_sand(n_mat_left))  comp_left  = 0;
	if (is_solid_for_sand(n_mat_right)) comp_right = 0;

	int out_up    = stochastic_div(density * comp_up,    V_MAX_OUTFLOW, pos, 11u);
	int out_down  = stochastic_div(density * comp_down,  V_MAX_OUTFLOW, pos, 12u);
	int out_left  = stochastic_div(density * comp_left,  V_MAX_OUTFLOW, pos, 13u);
	int out_right = stochastic_div(density * comp_right, V_MAX_OUTFLOW, pos, 14u);

	int total_out = out_up + out_down + out_left + out_right;
	int max_outflow = min(density, max(1, density / 4));
	if (total_out > max_outflow) {
		out_up    = out_up    * max_outflow / max(1, total_out);
		out_down  = out_down  * max_outflow / max(1, total_out);
		out_left  = out_left  * max_outflow / max(1, total_out);
		out_right = out_right * max_outflow / max(1, total_out);
		total_out = out_up + out_down + out_left + out_right;
	}

	int in_up = 0, in_down = 0, in_left = 0, in_right = 0;
	ivec2 vin_up = ivec2(0), vin_down = ivec2(0), vin_left = ivec2(0), vin_right = ivec2(0);

	if (n_mat_up == MAT_SAND) {
		int dN = get_density_sand(n_up);
		ivec2 vN = unpack_velocity_sand(n_up);
		in_up = stochastic_div(dN * max(0, vN.y), V_MAX_OUTFLOW, pos, 15u);
		vin_up = vN;
	}
	if (n_mat_down == MAT_SAND) {
		int dN = get_density_sand(n_down);
		ivec2 vN = unpack_velocity_sand(n_down);
		in_down = stochastic_div(dN * max(0, -vN.y), V_MAX_OUTFLOW, pos, 16u);
		vin_down = vN;
	}
	if (n_mat_left == MAT_SAND) {
		int dN = get_density_sand(n_left);
		ivec2 vN = unpack_velocity_sand(n_left);
		in_left = stochastic_div(dN * max(0, vN.x), V_MAX_OUTFLOW, pos, 17u);
		vin_left = vN;
	}
	if (n_mat_right == MAT_SAND) {
		int dN = get_density_sand(n_right);
		ivec2 vN = unpack_velocity_sand(n_right);
		in_right = stochastic_div(dN * max(0, -vN.x), V_MAX_OUTFLOW, pos, 18u);
		vin_right = vN;
	}

	int total_in = in_up + in_down + in_left + in_right;

	if (is_solid_for_sand(n_mat_up)    && vel.y < 0) vel.y = -vel.y;
	if (is_solid_for_sand(n_mat_down)  && vel.y > 0) vel.y = -vel.y;
	if (is_solid_for_sand(n_mat_left)  && vel.x < 0) vel.x = -vel.x;
	if (is_solid_for_sand(n_mat_right) && vel.x > 0) vel.x = -vel.x;

	int new_density = clamp(density - total_out + total_in, 0, 255);

	int stayed = max(0, density - total_out);
	int weight = max(1, stayed + total_in);
	ivec2 vsum = vel * stayed
	           + vin_up * in_up + vin_down * in_down
	           + vin_left * in_left + vin_right * in_right;
	ivec2 new_vel = vsum / weight;
	int new_vel_mag = max(abs(new_vel.x), abs(new_vel.y));
	// Heavy damping: sand loses 50% velocity per frame
	if (new_vel_mag > 0) {
		new_vel = new_vel / 2;
	}
	new_vel = clamp(new_vel, ivec2(-8), ivec2(7));

	if (material == MAT_AIR || material == MAT_WATER) {
		if (total_in >= THRESHOLD_BECOME_SAND) {
			ivec2 inflow_vel = ivec2(0);
			if (total_in > 0) {
				inflow_vel = (vin_up * in_up + vin_down * in_down + vin_left * in_left + vin_right * in_right) / total_in;
				inflow_vel = inflow_vel / 2;
				inflow_vel = clamp(inflow_vel, ivec2(-8), ivec2(7));
			}
			imageStore(chunk_tex, pos, pack_sand(total_in, inflow_vel));
			return;
		}
		return;
	}

	// Sand never dissipates — even density 1 persists. Only density 0 (all flowed out) becomes air.
	if (new_density == 0) {
		imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, 0));
		return;
	}
	imageStore(chunk_tex, pos, pack_sand(new_density, new_vel));
}

bool simulate_sand(ivec2 pos, inout vec4 pixel, inout int material,
                    vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right) {
	if (material != MAT_SAND && material != MAT_AIR && material != MAT_WATER) return false;
	sand_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
	if (material == MAT_SAND) return true;
	pixel = imageLoad(chunk_tex, pos);
	material = get_material(pixel);
	return material == MAT_SAND;
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/sim/sand.glslinc
git commit -m "feat: add sand fluid simulation shader"
```

---

### Task 4: Add THRESHOLD_BECOME_SAND constant and update is_solid_for_* in existing shaders

**Files:**
- Modify: `shaders/include/sim/common.glslinc`
- Modify: `shaders/include/sim/blood.glslinc`
- Modify: `shaders/include/sim/oil.glslinc`
- Modify: `shaders/include/sim/lava.glslinc`
- Modify: `shaders/include/sim/gas.glslinc`

- [ ] **Step 1: Add THRESHOLD_BECOME_SAND to common.glslinc**

After `const int THRESHOLD_BECOME_BLOOD = 1;` (line 9), add:

```glsl
const int THRESHOLD_BECOME_SAND = 1;
```

- [ ] **Step 2: Update is_solid_for_blood in blood.glslinc**

Change line 21 from:
```glsl
bool is_solid_for_blood(int mat) {
	return mat != MAT_AIR && mat != MAT_BLOOD;
}
```
to:
```glsl
bool is_solid_for_blood(int mat) {
	return mat != MAT_AIR && mat != MAT_BLOOD && mat != MAT_SAND;
}
```

This means blood treats sand as a solid it can't flow into, and sand won't displace blood. Since sand sim runs before blood sim, sand will claim space first, and blood respects sand walls.

- [ ] **Step 3: Update is_solid_for_oil in oil.glslinc**

Change line 21 from:
```glsl
bool is_solid_for_oil(int mat) {
	return mat != MAT_AIR && mat != MAT_OIL;
}
```
to:
```glsl
bool is_solid_for_oil(int mat) {
	return mat != MAT_AIR && mat != MAT_OIL && mat != MAT_SAND;
}
```

- [ ] **Step 4: Update is_solid_for_lava in lava.glslinc**

Change line 21 from:
```glsl
bool is_solid_for_lava(int mat) {
	return mat != MAT_AIR && mat != MAT_LAVA;
}
```
to:
```glsl
bool is_solid_for_lava(int mat) {
	return mat != MAT_AIR && mat != MAT_LAVA && mat != MAT_SAND;
}
```

- [ ] **Step 5: Update is_solid_for_gas in gas.glslinc**

Change line 20 from:
```glsl
bool is_solid_for_gas(int mat) {
	return mat != MAT_AIR && mat != MAT_GAS;
}
```
to:
```glsl
bool is_solid_for_gas(int mat) {
	return mat != MAT_AIR && mat != MAT_GAS && mat != MAT_SAND;
}
```

Wait — per the spec design, sand should be able to flow into water. But gas should treat sand as solid (gas can't push through sand). Lava and oil should also treat sand as solid (they're heavier, process earlier, and shouldn't merge with sand). Blood should treat sand as solid. This is all correct per the above.

Actually, rethinking: should lava flow *over* sand, or treat it as solid? Since lava has higher priority (processes first), if lava treats sand as solid, lava won't try to flow into sand cells — that's correct behavior. Sand is a wall from lava's perspective.

- [ ] **Step 6: Commit**

```bash
git add shaders/include/sim/common.glslinc shaders/include/sim/blood.glslinc shaders/include/sim/oil.glslinc shaders/include/sim/lava.glslinc shaders/include/sim/gas.glslinc
git commit -m "feat: add THRESHOLD_BECOME_SAND and update is_solid_for_* for sand"
```

---

### Task 5: Wire sand into simulation.glsl

**Files:**
- Modify: `shaders/compute/simulation.glsl`

- [ ] **Step 1: Add sand.glslinc include**

After line 40 (`#include "res://shaders/include/sim/blood.glslinc"`), add:

```glsl
#include "res://shaders/include/sim/sand.glslinc"
```

- [ ] **Step 2: Add simulate_sand call in main()**

After the `simulate_oil` call (line 68) and **before** the `simulate_blood` call (line 69), add:

```glsl
	if (simulate_sand(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
```

The final priority order should be:
```
simulate_explode_wave → simulate_lava → simulate_oil → simulate_sand → simulate_blood → simulate_gas → simulate_burning
```

- [ ] **Step 3: Commit**

```bash
git add shaders/compute/simulation.glsl
git commit -m "feat: wire sand simulation into main loop"
```

---

### Task 6: Modify melee_arc.glsl to spawn sand on wall destruction

**Files:**
- Modify: `shaders/compute/melee_arc.glsl`

- [ ] **Step 1: Add destruction distribution logic**

The melee arc shader currently writes `vec4(0,0,0,0)` (MAT_AIR) when destroying solid cells. Change this to write `pack_sand(255, vel)` with a probabilistic distribution based on the destroyed material.

Replace lines 76–90 of `melee_arc.glsl` (the `if (is_solid_pass)` block) with:

```glsl
	if (is_solid_pass) {
		float hardness = hardness_for(mat);
		float scale_clamped = clamp(pc.damage / (pc.damage + hardness), 0.1, 1.0);
		float effective_r = pc.radius * scale_clamped;
		if (dist_sq > effective_r * effective_r) return;

		// Destruction distribution: some materials spawn sand instead of air.
		// STONE=2, DIRT=5, COAL=6 → probabilistic sand, others → pure air.
		uint rng = hash(uint(local.x) ^ hash(uint(local.y) ^ uint(pc.frame_seed)));
		bool spawn_sand = false;
		if (mat == uint(MAT_STONE) || mat == uint(MAT_DIRT)) {
			spawn_sand = (rng % 100u) < 40u;
		} else if (mat == uint(MAT_COAL)) {
			spawn_sand = (rng % 100u) < 30u;
		}

		if (spawn_sand) {
			float dist = sqrt(dist_sq);
			vec2 push_dir = (dist > 0.0001) ? to_pixel / dist : pc.direction;
			float speed = 200.0; // pixels/sec outward burst
			float vx_f = push_dir.x * speed / 60.0;
			float vy_f = push_dir.y * speed / 60.0;
			int vx = clamp(int(round(vx_f)) + 8, 0, 15);
			int vy = clamp(int(round(vy_f)) + 8, 0, 15);
			uint packed_vel = (uint(vx) << 4) | uint(vy);
			imageStore(chunk_tex, local, vec4(
				float(MAT_SAND) / 255.0,
				255.0 / 255.0,
				0.0,
				float(packed_vel) / 255.0
			));
		} else {
			imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));
		}

		uint idx = atomicAdd(hit_list.count, 1u);
		if (idx < pc.hit_capacity) {
			hit_list.entries[idx].world_x = int(world_pos.x);
			hit_list.entries[idx].world_y = int(world_pos.y);
			hit_list.entries[idx].mat_id = mat;
			hit_list.entries[idx].scale = scale_clamped;
		}
	}
```

Note: `pc.frame_seed` is already available as a push constant (offset 4 in the current push constants). We need to check if it's available. Looking at the melee_arc push constants, the current structure only has `chunk_origin`, `origin`, `direction`, `radius`, `inner_radius`, `arc_half_angle`, `push_speed`, `damage`, `target_mask`, `hit_capacity`. There's no `frame_seed`. 

We can instead use a hash of the position alone for the destruction RNG — the pattern won't be perfectly random but will look fine for a one-time destruction event:

Change the hash line to:

```glsl
		uint rng = hash(uint(local.x) * 1973u + uint(local.y) * 9241u + uint(mat) * 4523u);
```

Also, the `pack_sand` function isn't available in melee_arc.glsl. Since melee_arc.glsl is a separate compute shader that doesn't include simulation includes, we need to construct the pixel value manually. The inline construction above (using `float(MAT_SAND) / 255.0`, etc.) handles this correctly.

Also need to add `#include "res://shaders/generated/materials.glslinc"` — it's already included at line 4 of melee_arc.glsl. Good.

But `MAT_SAND` won't be in the generated materials yet at this task step since we already ran generation in Task 2. So this should work.

Also need the `hash` function — melee_arc.glsl doesn't currently include common.glslinc. We need to add a local hash or include common.glslinc. Looking at the melee_arc shader, it doesn't have the `hash()` function. The simplest approach: include common.glslinc. But it includes the simulation `chunk_tex` binding which might conflict. Let me check what common.glslinc needs... it needs `chunk_tex` and `pc.frame_seed`. Melee arc already has `chunk_tex` as binding 0 and has its own push constants. We could just add a standalone hash, which is cleaner:

Add this after line 4 (the materials include) in melee_arc.glsl:

```glsl
uint melee_hash(uint n) {
	n = (n >> 16u) ^ n;
	n *= 0xed5ad0bbu;
	n = (n >> 16u) ^ n;
	n *= 0xac4c1b51u;
	n = (n >> 16u) ^ n;
	return n;
}
```

Then use `melee_hash` instead of `hash` in the destruction RNG.

- [ ] **Step 2: Commit**

```bash
git add shaders/compute/melee_arc.glsl
git commit -m "feat: melee arc spawns sand on wall destruction"
```

---

### Task 7: Modify explode_wave.glslinc to spawn sand on terrain destruction

**Files:**
- Modify: `shaders/include/sim/explode_wave.glslinc`

- [ ] **Step 1: Update Branch D (line 114) to spawn sand probabilistically**

In `explode_wave.glslinc`, find the Branch D block where `new_health <= 0` currently writes `make_pixel(MAT_AIR, 0, SCORCH_TEMP)`. Change the `imageStore` on what is currently line 115 from:

```glsl
			imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
```

to:

```glsl
			// Probabilistic sand spawn for destroyed collider materials
			uint wave_rng = hash(uint(pos.x) * 1973u + uint(pos.y) * 9241u + uint(material) * 4523u);
			bool wave_spawn_sand = false;
			if (material == MAT_STONE || material == MAT_DIRT) {
				wave_spawn_sand = (wave_rng % 100u) < 40u;
			} else if (material == MAT_COAL) {
				wave_spawn_sand = (wave_rng % 100u) < 30u;
			}
			if (wave_spawn_sand) {
				// Give sand a burst velocity pointing away from the wave source
				// (not available here, so give zero initial velocity — sand just sits)
				imageStore(chunk_tex, pos, pack_sand(255, ivec2(0)));
			} else {
				imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
			}
```

Wait — `pack_sand` is defined in `sand.glslinc` which is only included in `simulation.glsl`. The `explode_wave.glslinc` is also included in `simulation.glsl`, so `pack_sand` should be available. Actually, since `explode_wave.glslinc` is `#include`d before `sand.glslinc` in simulation.glsl (line ordering: explode_wave at line 39, sand will be at line 40 or 41), `pack_sand` won't be defined yet when explode_wave tries to use it.

There are two options:
1. Move the sand include before explode_wave
2. Forward-declare `pack_sand` in explode_wave
3. Inline the pack logic in explode_wave

The cleanest approach is to reorder the includes so sand.glslinc comes before explode_wave.glslinc, or just inline the pack. Let me inline it — it's just a vec4 construction:

```glsl
			uint wave_rng = hash(uint(pos.x) * 1973u + uint(pos.y) * 9241u + uint(material) * 4523u);
			bool wave_spawn_sand = false;
			if (material == MAT_STONE || material == MAT_DIRT) {
				wave_spawn_sand = (wave_rng % 100u) < 40u;
			} else if (material == MAT_COAL) {
				wave_spawn_sand = (wave_rng % 100u) < 30u;
			}
			if (wave_spawn_sand) {
				imageStore(chunk_tex, pos, vec4(float(MAT_SAND) / 255.0, 1.0, 0.0, 0.0));
			} else {
				imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
			}
```

Note: `density = 255` maps to `p.g = 255/255 = 1.0`. `vel = (0,0)` maps to `p.a = 0.0` (both vx+8=8, vy+8=8, packed = 0x88 = 136... wait, `(8 << 4) | 8 = 136`). Let me recalculate: with vel=(0,0), vx = 0+8 = 8, vy = 0+8 = 8, packed = (8<<4)|8 = 128+8 = 136, so p.a = 136/255. Hmm, but we want zero initial velocity, so the pixel value should be `vec4(MAT_SAND/255, 255/255, 0, 136/255)`.

Actually, let me reconsider. For a zero-velocity pack: vx=0, vy=0 → encoded vx = 0+8 = 8, encoded vy = 0+8 = 8, packed = (8 << 4) | 8 = 136, alpha = 136/255 ≈ 0.533. So:

```glsl
			imageStore(chunk_tex, pos, vec4(float(MAT_SAND) / 255.0, 1.0, 0.0, 136.0 / 255.0));
```

- [ ] **Step 2: Commit**

```bash
git add shaders/include/sim/explode_wave.glslinc
git commit -m "feat: explode wave spawns sand on terrain destruction"
```

---

### Task 8: Add CPU-side place_sand function chain

**Files:**
- Modify: `src/core/terrain_surface.gd`
- Modify: `src/core/terrain_modifier.gd`
- Modify: `src/core/world_manager.gd`

- [ ] **Step 1: Add place_sand to terrain_surface.gd**

After `place_blood` (line 22), add:

```gdscript
func place_sand(world_pos: Vector2, radius: float, outward_speed: float, bias_dir: Vector2 = Vector2.ZERO) -> void:
	if adapter:
		adapter.place_sand(world_pos, radius, outward_speed, bias_dir)
```

- [ ] **Step 2: Add place_sand to world_manager.gd**

After `place_blood` (line 200), add:

```gdscript
func place_sand(world_pos: Vector2, radius: float, outward_speed: float, bias_dir: Vector2 = Vector2.ZERO) -> void:
	terrain_modifier.place_sand(world_pos, radius, outward_speed, bias_dir)
```

- [ ] **Step 3: Add place_sand to terrain_modifier.gd**

After the `place_blood` function (ending around line 165), add:

```gdscript
func place_sand(world_pos: Vector2, radius: float, outward_speed: float, bias_dir: Vector2 = Vector2.ZERO) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))
	var r_sq := float(r * r)
	var bias_len := bias_dir.length()
	var bias := Vector2.ZERO
	if bias_len > 0.0001:
		bias = bias_dir / bias_len
	var affected: Dictionary = {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var d_sq := float(dx * dx + dy * dy)
			if d_sq > r_sq:
				continue
			var t : float = 1.0 - sqrt(d_sq) / max(1.0, float(r))
			var keep := 0.35 + 0.65 * t
			if bias != Vector2.ZERO and (dx != 0 or dy != 0):
				var cell_dir := Vector2(float(dx), float(dy)).normalized()
				keep += 0.35 * cell_dir.dot(bias)
			if randf() > keep:
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
			var existing_mat := data[idx]
			# Sand can replace air or water, but not solids or other fluids
			if existing_mat != MaterialRegistry.MAT_AIR and existing_mat != MaterialRegistry.MAT_WATER:
				continue
			data[idx] = MaterialRegistry.MAT_SAND
			data[idx + 1] = 255  # full density
			data[idx + 2] = 0
			var dir_normalized := dir
			if dir.length_squared() > 0.0001:
				dir_normalized = dir.normalized()
			elif bias != Vector2.ZERO:
				dir_normalized = bias
			var jitter_angle := randf_range(-0.6, 0.6)
			dir_normalized = dir_normalized.rotated(jitter_angle)
			var speed := outward_speed * randf_range(0.6, 1.4)
			if bias != Vector2.ZERO:
				dir_normalized = (dir_normalized + bias * 0.6).normalized()
			var vel := (dir_normalized * speed) / 60.0
			var vx := clampi(int(round(vel.x)) + 8, 0, 15)
			var vy := clampi(int(round(vel.y)) + 8, 0, 15)
			data[idx + 3] = (vx << 4) | vy
			modified = true
		if modified:
			world_manager.rd.texture_update(chunk.rd_texture, 0, data)
			world_manager.mark_terrain_dirty(chunk.coord)

	if terrain_physical:
		var affected_rect := Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1)
		terrain_physical.invalidate_rect(affected_rect)
```

- [ ] **Step 4: Commit**

```bash
git add src/core/terrain_surface.gd src/core/world_manager.gd src/core/terrain_modifier.gd
git commit -m "feat: add place_sand CPU-side function chain"
```

---

### Task 9: Add sand impact particles to terrain_impact.gd

**Files:**
- Modify: `src/core/juice/terrain_impact.gd`

- [ ] **Step 1: Add MAT_SAND entry to impact_data**

In the `_ready()` function's `impact_data` dictionary (after the `MAT_STONE` entry around line 27), add:

```gdscript
		MaterialRegistry.MAT_SAND: {
			"particle_color": Color(0.6, 0.55, 0.45),
			"particle_count": 6,
		},
```

- [ ] **Step 2: Commit**

```bash
git add src/core/juice/terrain_impact.gd
git commit -m "feat: add sand impact particles"
```

---

### Task 10: Verify everything works

- [ ] **Step 1: Run the Godot project and test**

Launch the game. Debug console should allow `spawn_mat sand`. Test:

1. Spawn sand via console — it should appear as a sandy beige blob and barely spread
2. Melee a stone wall — destroyed cells should sometimes spawn sand with a burst
3. Sand should pile up and not dissipate
4. Blood should not flow through sand cells
5. Sand should be able to flow into water cells
6. Explosion destroying stone should also spawn sand debris

- [ ] **Step 2: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: sand material integration fixes"
```