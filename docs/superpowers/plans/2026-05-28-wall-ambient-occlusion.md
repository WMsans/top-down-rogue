# Wall Ambient Occlusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dynamic ambient occlusion to wall rendering — a floor contact shadow, inner-corner darkening, and a wall-face depth gradient — entirely within the existing canvas shader.

**Architecture:** All changes live in `shaders/visual/render_chunk.gdshader`. A distance-weighted disk sampler (`ao_occlusion`) over the live `chunk_data` texture drives the floor shadow + corner darkening in the `layer_mode == 0` air branch; a depth factor darkens extruded faces in the `layer_mode == 1` scan. New uniforms (`ao_enabled`, `ao_radius`, `ao_intensity`, `face_ao_intensity`) make it tweakable and let us prove byte-for-byte parity with today's output when disabled. No new textures, buffers, or compute passes.

**Tech Stack:** Godot 4.6.3, GDShader (`canvas_item`).

---

## Verification note (read first)

GDShaders have no unit-test harness in this repo (the GUT suite under `tests/unit/` is GDScript only, and canvas shaders compile lazily at draw time). So each task is verified two ways:

1. **Load smoke check** — `godot --headless --path . --quit-after 2 2>&1 | grep -i -E "error|shader" ` must print no shader parse/compile errors. This catches syntax errors at resource import.
2. **Visual check in the editor** — open `scenes/game.tscn`, run it (F5), and observe the rendered walls. This is the real correctness check; the steps say exactly what to look for.

The **regression guard** is the spec's parity requirement: with `ao_enabled = false` the render must look identical to today's. We verify that explicitly in Task 4.

Throughout, the existing shader uses these already-defined helpers (do not redefine them): `read_pixel(ivec2)`, `get_material(vec4)`, `is_solid(ivec2)` (treats OOB as **solid**), `HAS_COLLIDER[]`, `CHUNK_SIZE` (256), `wall_height` (uniform, 16), `MAT_AIR`, `sample_material_texture(...)`, `near_air(ivec2)`.

---

## Task 1: Add uniforms and the AO occlusion helpers (no behavior change yet)

Adds the uniforms and two helper functions. The functions are unused after this task, so rendering is unchanged — this isolates "does it still compile and load" from "does it look right".

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader`

- [ ] **Step 1: Add the uniforms**

In `shaders/visual/render_chunk.gdshader`, the uniform block currently ends at line 9. Find:

```glsl
uniform int layer_mode = 0;

const int CHUNK_SIZE = 256;
```

Replace with:

```glsl
uniform int layer_mode = 0;
uniform bool ao_enabled = true;
uniform float ao_radius = 3.5;          // reach of floor/corner shadow, in px
uniform float ao_intensity = 0.4;       // max floor/corner darkening (0..1)
uniform float face_ao_intensity = 0.4;  // max darkening at bottom of wall face

const int CHUNK_SIZE = 256;
const int AO_MAX_RADIUS = 6;            // compile-time loop bound for ao_occlusion
```

- [ ] **Step 2: Add `is_solid_ao` and `ao_occlusion`**

Find the end of the existing `is_solid` function (lines 34-41):

```glsl
bool is_solid(ivec2 pos) {
	// Out-of-bounds treated as solid
	if (pos.x < 0 || pos.x >= CHUNK_SIZE || pos.y < 0 || pos.y >= CHUNK_SIZE) {
		return true;
	}
	int m = get_material(read_pixel(pos));
	return HAS_COLLIDER[m];
}
```

Immediately after it, insert:

```glsl
// Like is_solid, but treats out-of-bounds as AIR. Used only for AO so that
// chunk borders do not self-shadow (the accepted seam: edges lose a little
// shadow rather than gaining a false dark grid line).
bool is_solid_ao(ivec2 pos) {
	if (pos.x < 0 || pos.x >= CHUNK_SIZE || pos.y < 0 || pos.y >= CHUNK_SIZE) {
		return false;
	}
	return HAS_COLLIDER[get_material(read_pixel(pos))];
}

// Distance-weighted disk occlusion of a cell by nearby solids.
// 0 in open floor, ~0.5 beside a flat wall, ~0.75 in a concave corner.
float ao_occlusion(ivec2 pos) {
	float occ = 0.0;
	float total = 0.0;
	for (int dy = -AO_MAX_RADIUS; dy <= AO_MAX_RADIUS; dy++) {
		for (int dx = -AO_MAX_RADIUS; dx <= AO_MAX_RADIUS; dx++) {
			if (dx == 0 && dy == 0) continue;
			float dist = sqrt(float(dx * dx + dy * dy));
			if (dist > ao_radius) continue;
			float w = 1.0 - dist / ao_radius;  // closer cells weigh more
			total += w;
			if (is_solid_ao(pos + ivec2(dx, dy))) occ += w;
		}
	}
	return total > 0.0 ? occ / total : 0.0;
}
```

- [ ] **Step 3: Load smoke check**

Run: `godot --headless --path . --quit-after 2 2>&1 | grep -i -E "error|shader render_chunk|parser"`
Expected: no lines mentioning a shader error in `render_chunk.gdshader`. (Unrelated pre-existing warnings are fine; a shader **parse error** would name the file and a line number.)

- [ ] **Step 4: Visual check — no change**

Run the game (`godot --path . scenes/game.tscn`, or F5 in the editor). Walls and floor must look exactly as before — the helpers are not yet called.
Expected: identical to current rendering.

- [ ] **Step 5: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: add AO uniforms and occlusion helpers to render_chunk shader"
```

---

## Task 2: Wall-face depth gradient (`layer_mode == 1`)

Darkens the extruded wall faces toward their bottom edge.

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader`

- [ ] **Step 1: Apply the depth factor in the face scan**

Find the face-scan loop (currently lines 211-220) inside the `if (mat == MAT_AIR)` / `else` (layer_mode != 0) branch:

```glsl
			bool found_wall = false;
			for (int d = 1; d <= wall_height; d++) {
				if (found_wall) break;
				ivec2 check_pos = ivec2(px.x, px.y + d);
				vec4 src_data = read_pixel_extended(check_pos);
				if (is_solid_extended(check_pos)) {
					base_color = vec4(sample_material_texture(get_material(src_data), px.x, d, src_data, px), 1.0);
					found_wall = true;
				}
			}
```

Replace with (darken by depth, gated on `ao_enabled`):

```glsl
			bool found_wall = false;
			for (int d = 1; d <= wall_height; d++) {
				if (found_wall) break;
				ivec2 check_pos = ivec2(px.x, px.y + d);
				vec4 src_data = read_pixel_extended(check_pos);
				if (is_solid_extended(check_pos)) {
					vec3 face_rgb = sample_material_texture(get_material(src_data), px.x, d, src_data, px);
					if (ao_enabled) {
						float face_factor = mix(1.0, 1.0 - face_ao_intensity,
							float(d) / float(wall_height));
						face_rgb *= face_factor;
					}
					base_color = vec4(face_rgb, 1.0);
					found_wall = true;
				}
			}
```

- [ ] **Step 2: Load smoke check**

Run: `godot --headless --path . --quit-after 2 2>&1 | grep -i -E "error|shader render_chunk|parser"`
Expected: no shader errors for `render_chunk.gdshader`.

- [ ] **Step 3: Visual check — faces darken toward bottom**

Run the game. Find a wall with a visible extruded face (a wall edge facing the camera). The face should be full-bright at the top and visibly darker at its bottom edge.
Expected: a smooth vertical darkening on faces; floor and top caps unchanged.

- [ ] **Step 4: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: darken extruded wall faces toward bottom edge (AO gradient)"
```

---

## Task 3: Floor contact shadow + inner corners (`layer_mode == 0`)

Replaces the transparent air output in the top-cap pass with a semi-transparent black shadow whose darkness comes from `ao_occlusion`. Skips cells the face pass already covers, and short-circuits open floor.

**Files:**
- Modify: `shaders/visual/render_chunk.gdshader`

- [ ] **Step 1: Add a cheap "near any wall" pre-check helper**

Insert this directly **after** the `ao_occlusion` function added in Task 1:

```glsl
// Cheap test: is there any solid close enough to possibly occlude `pos`?
// Samples the 4 axis neighbors and 4 diagonals at the AO reach. May rarely miss
// a lone solid pixel between sample points (<=1px shadow gap) — acceptable.
bool ao_has_nearby_solid(ivec2 pos) {
	int r = int(ceil(ao_radius));
	if (is_solid_ao(pos + ivec2(1, 0))) return true;
	if (is_solid_ao(pos + ivec2(-1, 0))) return true;
	if (is_solid_ao(pos + ivec2(0, 1))) return true;
	if (is_solid_ao(pos + ivec2(0, -1))) return true;
	if (is_solid_ao(pos + ivec2(r, r))) return true;
	if (is_solid_ao(pos + ivec2(-r, r))) return true;
	if (is_solid_ao(pos + ivec2(r, -r))) return true;
	if (is_solid_ao(pos + ivec2(-r, -r))) return true;
	return false;
}

// True if a wall sits within wall_height directly below `pos`, meaning the
// layer_mode==1 face pass already paints (and darkens) this air pixel. The floor
// shadow must skip these so the two effects never stack on one pixel.
bool ao_covered_by_face(ivec2 pos) {
	for (int d = 1; d <= wall_height; d++) {
		if (is_solid_extended(ivec2(pos.x, pos.y + d))) return true;
	}
	return false;
}
```

Note: `ao_covered_by_face` calls `is_solid_extended`, which is defined later in the file (lines 62-78). GDShader resolves functions across the whole translation unit regardless of order, so this is fine — but if the compiler complains about an undeclared identifier, move both new helpers to just below `is_solid_extended` instead.

- [ ] **Step 2: Replace the transparent air output in the top-cap branch**

Find this branch (currently lines 207-210):

```glsl
	if (mat == MAT_AIR) {
		if (layer_mode == 0) {
			base_color = vec4(0.0);
		} else {
```

Replace the `layer_mode == 0` body:

```glsl
	if (mat == MAT_AIR) {
		if (layer_mode == 0) {
			base_color = vec4(0.0);
			if (ao_enabled && !ao_covered_by_face(px) && ao_has_nearby_solid(px)) {
				float ao_alpha = ao_occlusion(px) * ao_intensity;
				base_color = vec4(0.0, 0.0, 0.0, ao_alpha);
			}
		} else {
```

- [ ] **Step 3: Load smoke check**

Run: `godot --headless --path . --quit-after 2 2>&1 | grep -i -E "error|shader render_chunk|parser"`
Expected: no shader errors for `render_chunk.gdshader`. If you see "undeclared identifier 'is_solid_extended'", apply the move described in Step 1's note, then re-run.

- [ ] **Step 4: Visual check — floor shadow + corners**

Run the game. Look at floor next to walls:
- A soft dark band hugs the base of walls and fades out over ~3-4px.
- Concave (inner) corners are visibly darker than straight wall edges.
- The shadow appears on the open-floor sides of walls, not stacked on top of the extruded faces (those are handled by Task 2's gradient).
- Open floor far from any wall is unchanged (no global dimming).

Expected: walls feel grounded; corners read darkest.

- [ ] **Step 5: Carve test — dynamic update**

In the running game, carve a wall (melee/normal play). The shadow band must redraw immediately around the new terrain shape — it is computed live, not baked.
Expected: shadow follows carved edges with no stale outline.

- [ ] **Step 6: Commit**

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "feat: add floor contact shadow and inner-corner AO to wall rendering"
```

---

## Task 4: Verify parity and chunk seams; lock in defaults

No code change unless a check fails. Confirms the spec's regression guard and seam behavior.

**Files:**
- (verification only; `shaders/visual/render_chunk.gdshader` only if a fix is needed)

- [ ] **Step 1: Parity check — `ao_enabled = false` matches today**

In the editor, select a chunk's `MeshInstance2D` material (or edit the uniform default temporarily) and set `ao_enabled = false`. Run the game.
Expected: rendering is identical to pre-feature output — no face gradient, no floor shadow. This confirms every AO code path is fully gated. If anything differs, find the ungated path and wrap it in `if (ao_enabled)`.

- [ ] **Step 2: Chunk-seam check**

Re-enable `ao_enabled = true`. Run the game and inspect boundaries between loaded chunks (move around so chunks tile).
Expected: **no** dark grid line along chunk edges. A wall straddling a seam may show slightly reduced shadow on the far side — that is the accepted seam, not a defect.

- [ ] **Step 3: Live-tweak check**

With the game running (or via the remote inspector / editing uniform defaults in `render_chunk.gdshader`), sweep `ao_radius` from 2.0 to 6.0 and `ao_intensity` from 0.0 to 0.6.
Expected: shadow reach grows/shrinks with `ao_radius`; darkness scales with `ao_intensity`; `face_ao_intensity` independently controls face darkness. Values respond without errors.

- [ ] **Step 4: Confirm defaults**

Ensure the committed uniform defaults are the "medium" values: `ao_radius = 3.5`, `ao_intensity = 0.4`, `face_ao_intensity = 0.4`, `ao_enabled = true`. If you changed any default while tweaking, restore them.

- [ ] **Step 5: Final smoke check + commit (only if a fix was made)**

Run: `godot --headless --path . --quit-after 2 2>&1 | grep -i -E "error|shader render_chunk|parser"`
Expected: no shader errors.

```bash
git add shaders/visual/render_chunk.gdshader
git commit -m "fix: ensure AO fully gated by ao_enabled and defaults at medium"
```

(If no fix was needed, skip the commit — the feature is complete after Task 3.)

---

## Self-review against the spec

- **Floor contact shadow** → Task 3, Step 2. ✓
- **Inner-corner darkening** → emerges from `ao_occlusion` (Task 1) used in Task 3; verified Task 3 Step 4. ✓
- **Wall-face gradient** → Task 2. ✓
- **Dynamic / no baking** → live texture sampling; verified Task 3 Step 5 (carve test). ✓
- **Tunable uniforms** (`ao_radius`, `ao_intensity`, `face_ao_intensity`, `ao_enabled`) → Task 1 Step 1; verified Task 4 Step 3. ✓
- **No top-cap edge shading** → no task touches the solid top-cap color path. ✓
- **No cross-chunk AO sampling; accepted seam via OOB=air** → `is_solid_ao` (Task 1); verified Task 4 Step 2. ✓
- **No new textures/buffers/compute** → all edits in one shader file. ✓
- **Face/floor never double-darken** → `ao_covered_by_face` skip (Task 3). ✓
- **Fluid overlays preserved** → AO writes `base_color` before the unchanged end-of-`fragment()` fluid composite; not separately re-verified but no fluid code path is modified. ✓
- **Parity when disabled** → every AO path gated by `ao_enabled`; verified Task 4 Step 1. ✓

Type/name consistency: `is_solid_ao`, `ao_occlusion`, `ao_has_nearby_solid`, `ao_covered_by_face`, and uniforms `ao_enabled`/`ao_radius`/`ao_intensity`/`face_ao_intensity` are used identically across all tasks. No placeholders remain.
