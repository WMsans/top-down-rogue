# Wall Ambient Occlusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add uniform contact-shadow ambient occlusion to the terrain renderer covering floors, wall faces, and corners, computed entirely in `render_chunk.gdshader` with at most 8 new texture samples per pixel.

**Architecture:** AO darkness is driven by local solid density via one shared 8-tap ring sampler (floor + wall faces) plus a free density tally folded into the existing `near_air` disc scan (caps). Floor AO is written as semi-transparent black on air pixels and composites over the floor sprite that sits below the chunk meshes at `z = -10`. Out-of-bounds reads count as air during AO sampling to avoid chunk-border seams. Two uniforms (`ao_strength`, `ao_reach`) make it tunable.

**Tech Stack:** Godot 4.6.3, `canvas_item` GDShader, gdUnit4 for the regression guard.

---

## Background for the implementer

- The shader being edited is `shaders/visual/render_chunk.gdshader`. It runs over a per-pixel
  RGBA8 chunk texture (256×256) where `data.r * 255` is the material id. `HAS_COLLIDER[mat]`
  (from the generated `materials.gdshaderinc`) tells you whether a cell is solid.
- It is applied to **two** full-chunk quads (`src/core/chunk_manager.gd:83-106`):
  - `mesh_instance`, `layer_mode = 1` → vertical wall faces. On air pixels it scans downward
    for a wall; if none is found it currently writes transparent.
  - `wall_mesh_instance`, `layer_mode = 0`, `z_index = 1` → flat solid tops ("caps").
- The floor is a separate `Sprite2D` at `z_index = -10` (`src/core/world_manager.gd:33`), so
  anything the faces pass draws on an air pixel composites over the floor via the default
  `mix` blend.
- Existing per-pixel cost is already ~28 samples (caps `near_air` disc) to ~32 samples
  (faces wall scan), so the AO additions are small relative to the baseline.

**Test command (used throughout):**
```bash
GODOT_BIN=/usr/bin/godot addons/gdUnit4/runtest.sh -a tests/unit/test_render_chunk_shader.gd
```

## File structure

- **Modify** `shaders/visual/render_chunk.gdshader` — all AO logic: two uniforms, the
  `is_solid_ao` helper, the `ring_occlusion` sampler, the `near_air` → `disc_ao` refactor,
  and three fragment integration points.
- **Modify** `src/core/chunk_manager.gd` — set `ao_strength` / `ao_reach` on both materials.
- **Create** `tests/unit/test_render_chunk_shader.gd` — compile + uniform-presence guard.

---

## Task 1: Regression-guard test for the AO uniforms

**Files:**
- Create: `tests/unit/test_render_chunk_shader.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_render_chunk_shader.gd`:

```gdscript
extends GdUnitTestSuite

const SHADER_PATH := "res://shaders/visual/render_chunk.gdshader"

func _uniform_names() -> Array:
	var shader := load(SHADER_PATH) as Shader
	assert_that(shader).is_not_null()
	var names: Array = []
	for u in shader.get_shader_uniform_list():
		names.append(String(u.get("name", "")))
	return names

func _has_uniform(names: Array, target: String) -> bool:
	for n in names:
		if String(n).ends_with(target):
			return true
	return false

func test_shader_exposes_ao_strength_uniform() -> void:
	assert_bool(_has_uniform(_uniform_names(), "ao_strength")).is_true()

func test_shader_exposes_ao_reach_uniform() -> void:
	assert_bool(_has_uniform(_uniform_names(), "ao_reach")).is_true()
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
GODOT_BIN=/usr/bin/godot addons/gdUnit4/runtest.sh -a tests/unit/test_render_chunk_shader.gd
```
Expected: both tests FAIL — `ao_strength` / `ao_reach` are not in the shader's uniform list yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_render_chunk_shader.gd
git commit -m "test: guard render_chunk AO uniforms (failing)"
```

---

## Task 2: AO uniforms, sampler, and floor AO

This task adds the uniforms, the `is_solid_ao` helper, the `ring_occlusion` sampler, and the
first usage (floor AO). After this task the guard test passes, because the uniforms are
referenced and therefore appear in the uniform list.

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader` (uniforms after `:9`; helpers after `is_solid` `:34-41`; floor branch `:221-223`)

- [ ] **Step 1: Add the two AO uniforms**

In `shaders/visual/render_chunk.gdshader`, immediately after the existing
`uniform int layer_mode = 0;` line (`:9`), add:

```glsl
uniform float ao_strength = 0.6;
uniform float ao_reach = 3.0;
```

- [ ] **Step 2: Add the `is_solid_ao` helper**

Immediately after the existing `is_solid()` function (ends at `:41`, the closing `}` of the
function that returns `HAS_COLLIDER[m]`), add:

```glsl
// Like is_solid(), but out-of-bounds reads as AIR. Used only by AO sampling so that a
// missing neighbor chunk does not create false dark seams at chunk borders.
bool is_solid_ao(ivec2 pos) {
	if (pos.x < 0 || pos.x >= CHUNK_SIZE || pos.y < 0 || pos.y >= CHUNK_SIZE) {
		return false;
	}
	int m = get_material(read_pixel(pos));
	return HAS_COLLIDER[m];
}

// 8-tap ring occlusion in [0,1]: fraction of the ring (radius ao_reach) that is solid.
// The 4 cardinal taps gate the 4 diagonal taps, so fully open areas cost only 4 samples.
float ring_occlusion(ivec2 center) {
	int r = int(round(ao_reach));
	float s = 0.0;
	s += is_solid_ao(center + ivec2(r, 0)) ? 1.0 : 0.0;
	s += is_solid_ao(center + ivec2(-r, 0)) ? 1.0 : 0.0;
	s += is_solid_ao(center + ivec2(0, r)) ? 1.0 : 0.0;
	s += is_solid_ao(center + ivec2(0, -r)) ? 1.0 : 0.0;
	if (s == 0.0) {
		return 0.0;
	}
	int d = int(round(ao_reach * 0.7071));
	s += is_solid_ao(center + ivec2(d, d)) ? 1.0 : 0.0;
	s += is_solid_ao(center + ivec2(-d, d)) ? 1.0 : 0.0;
	s += is_solid_ao(center + ivec2(d, -d)) ? 1.0 : 0.0;
	s += is_solid_ao(center + ivec2(-d, -d)) ? 1.0 : 0.0;
	return s / 8.0;
}
```

- [ ] **Step 3: Wire floor AO into the faces pass**

In `fragment()`, find the `!found_wall` block (currently `:221-223`):

```glsl
				if (!found_wall) {
					base_color = vec4(0.0);
				}
```

Replace it with:

```glsl
				if (!found_wall) {
					float occ = ring_occlusion(px);
					base_color = vec4(0.0, 0.0, 0.0, occ * ao_strength);
				}
```

- [ ] **Step 4: Run the guard test to verify it passes**

Run:
```bash
GODOT_BIN=/usr/bin/godot addons/gdUnit4/runtest.sh -a tests/unit/test_render_chunk_shader.gd
```
Expected: both tests PASS (the shader compiles and both uniforms are now listed).

- [ ] **Step 5: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: floor ambient occlusion in render_chunk shader"
```

---

## Task 3: Wall-face AO

Darken each vertical wall-face pixel by the occlusion of its source solid cell, reusing the
same `ring_occlusion` sampler.

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader` (the `found_wall` body, currently `:216-219`)

- [ ] **Step 1: Apply AO to the sampled wall face**

In `fragment()`, find the wall-face hit block inside the downward scan (currently `:216-219`):

```glsl
					if (is_solid_extended(check_pos)) {
						base_color = vec4(sample_material_texture(get_material(src_data), px.x, d, src_data, px), 1.0);
						found_wall = true;
					}
```

Replace it with:

```glsl
					if (is_solid_extended(check_pos)) {
						vec3 face_rgb = sample_material_texture(get_material(src_data), px.x, d, src_data, px);
						float occ = ring_occlusion(check_pos);
						face_rgb *= (1.0 - occ * ao_strength);
						base_color = vec4(face_rgb, 1.0);
						found_wall = true;
					}
```

- [ ] **Step 2: Run the guard test to verify the shader still compiles**

Run:
```bash
GODOT_BIN=/usr/bin/godot addons/gdUnit4/runtest.sh -a tests/unit/test_render_chunk_shader.gd
```
Expected: both tests PASS (no compile regression).

- [ ] **Step 3: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: wall-face ambient occlusion"
```

---

## Task 4: Cap AO (corners) via `near_air` → `disc_ao` refactor

Replace the boolean `near_air` with a disc scan that also returns the solid fraction, then
use it to darken concave corners on solid tops at **zero** added samples.

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader` (`near_air` `:148-161`; its call site in the solid branch `:229-233`)

- [ ] **Step 1: Replace `near_air` with `disc_ao`**

Find the existing `near_air` function (`:148-161`):

```glsl
// Check if any air pixel exists within euclidean distance 3 of pos.
bool near_air(ivec2 pos) {
	for (int dy = -3; dy <= 3; dy++) {
		for (int dx = -3; dx <= 3; dx++) {
			if (dx == 0 && dy == 0) continue;
			if (dx * dx + dy * dy > 9) continue;
			ivec2 check = pos + ivec2(dx, dy);
			if (!is_solid(check)) {
				return true;
			}
		}
	}
	return false;
}
```

Replace it entirely with:

```glsl
// Scan the radius-3 disc around pos. Returns:
//   x = 1.0 if any air cell exists in the disc (else 0.0) — surface-visibility cull.
//   y = fraction of in-bounds disc cells that are solid — drives concave-corner AO.
// Tallying in-bounds cells only keeps chunk borders seam-free (matches is_solid_ao policy).
vec2 disc_ao(ivec2 pos) {
	bool any_air = false;
	int total = 0;
	int solid = 0;
	for (int dy = -3; dy <= 3; dy++) {
		for (int dx = -3; dx <= 3; dx++) {
			if (dx == 0 && dy == 0) continue;
			if (dx * dx + dy * dy > 9) continue;
			ivec2 check = pos + ivec2(dx, dy);
			if (check.x < 0 || check.x >= CHUNK_SIZE || check.y < 0 || check.y >= CHUNK_SIZE) {
				continue;
			}
			total++;
			if (is_solid_ao(check)) {
				solid++;
			} else {
				any_air = true;
			}
		}
	}
	float frac = total > 0 ? float(solid) / float(total) : 0.0;
	return vec2(any_air ? 1.0 : 0.0, frac);
}
```

- [ ] **Step 2: Update the call site to apply cap AO**

In `fragment()`, find the solid-cell render block (currently `:229-233`):

```glsl
				if (near_air(px)) {
					base_color = vec4(material_color(data, px), 1.0);
				} else {
					base_color = vec4(0.0, 0.0, 0.0, 1.0);
				}
```

Replace it with:

```glsl
				vec2 ao = disc_ao(px);
				if (ao.x > 0.0) {
					vec3 top_rgb = material_color(data, px);
					float occ = smoothstep(0.5, 0.85, ao.y) * ao_strength;
					top_rgb *= (1.0 - occ);
					base_color = vec4(top_rgb, 1.0);
				} else {
					base_color = vec4(0.0, 0.0, 0.0, 1.0);
				}
```

- [ ] **Step 3: Run the guard test to verify the shader still compiles**

Run:
```bash
GODOT_BIN=/usr/bin/godot addons/gdUnit4/runtest.sh -a tests/unit/test_render_chunk_shader.gd
```
Expected: both tests PASS (no compile regression; `near_air` has no other callers).

- [ ] **Step 4: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: concave-corner ambient occlusion on solid caps"
```

---

## Task 5: Wire the AO uniforms from `chunk_manager.gd`

The uniforms have shader defaults, but set them explicitly on both materials so they are
tunable from one place.

**Files:**
- Modify: `src/core/chunk_manager.gd` (after `:88` for `mat`; after `:105` for `wall_mat`)

- [ ] **Step 1: Set AO params on the faces material**

In `src/core/chunk_manager.gd`, find the faces material setup. After the line:

```gdscript
	mat.set_shader_parameter("layer_mode", 1)
```

add:

```gdscript
	mat.set_shader_parameter("ao_strength", 0.6)
	mat.set_shader_parameter("ao_reach", 3.0)
```

- [ ] **Step 2: Set AO params on the caps material**

After the line:

```gdscript
	wall_mat.set_shader_parameter("layer_mode", 0)
```

add:

```gdscript
	wall_mat.set_shader_parameter("ao_strength", 0.6)
	wall_mat.set_shader_parameter("ao_reach", 3.0)
```

- [ ] **Step 3: Run the full unit suite to confirm no regressions**

Run:
```bash
GODOT_BIN=/usr/bin/godot addons/gdUnit4/runtest.sh -a tests/unit
```
Expected: PASS, including `test_render_chunk_shader.gd` and the unchanged `test_floor_chunk.gd`.

- [ ] **Step 4: Commit**

```bash
git add src/core/chunk_manager.gd
git commit -m "feat: set ambient occlusion params on chunk materials"
```

---

## Task 6: In-engine visual verification

Fragment shaders cannot be asserted programmatically here, so confirm the look by running
the game.

**Files:** none (verification only)

- [ ] **Step 1: Launch the project and reach gameplay**

Run:
```bash
godot --path .
```
Play into a generated level with walls (use a level that spawns terrain).

- [ ] **Step 2: Confirm the AO reads correctly**

Verify all of the following:
- A dark contact shadow hugs the base of walls on the floor (~3px).
- Concave (inner) corners are visibly darker than straight wall edges; convex corners stay light.
- Vertical wall faces are darker where the wall is more enclosed.
- **No dark grid seams** appear along the 256px chunk boundaries.

- [ ] **Step 3: Confirm AO can be disabled cleanly**

Temporarily set `ao_strength` to `0.0` in `src/core/chunk_manager.gd:` (both materials),
relaunch, and confirm the render matches pre-AO behavior (no darkening anywhere). Then
restore `0.6` and relaunch to confirm AO returns. Do not commit the temporary `0.0`.

- [ ] **Step 4: Final confirmation**

No code changes to commit in this task. If Step 3 left edits, ensure `git status` is clean
(values restored to `0.6`).

---

## Self-review notes (for the implementer)

- **Sample budget:** the only new samples are `ring_occlusion` (≤8, with a 4-tap early
  reject) on floor and wall-face pixels. Cap AO reuses the `disc_ao` loop that `near_air`
  already ran (0 added). No pixel exceeds +8.
- **Edge safety:** every AO read goes through `is_solid_ao` (OOB = air) or skips OOB cells
  in `disc_ao`. Never reintroduce `is_solid` (OOB = solid) into AO paths — that causes
  border seams.
- **Disable path:** `ao_strength = 0.0` makes every AO term `* 0.0`; floor AO then writes
  alpha 0 (transparent, original behavior). The `ring_occlusion` early reject keeps open
  floor cheap regardless.
