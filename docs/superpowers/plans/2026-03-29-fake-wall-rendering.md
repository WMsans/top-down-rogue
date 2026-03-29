# Fake Wall Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add classic top-down wall extrusion with texture sampling and black interior tops to the existing pixel terrain renderer.

**Architecture:** All rendering logic lives in the fragment shader (`render_chunk.gdshader`). No compute pipeline changes. The shader scans the chunk data texture to determine wall faces, visible tops, and black interiors per fragment. A wall texture uniform provides the face texturing.

**Tech Stack:** Godot 4.6, GLSL (canvas_item shader), GDScript

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `textures/wall.png` | Create | 16x16 placeholder wall face texture |
| `shaders/render_chunk.gdshader` | Modify | Fragment shader with wall extrusion, air proximity, texture sampling |
| `scripts/world_manager.gd` | Modify | Load wall texture, pass `wall_texture` and `wall_height` uniforms |

---

### Task 1: Create placeholder wall texture

**Files:**
- Create: `textures/wall.png`

This is a GPU-rendered game with no automated test framework — all verification is visual. We create the asset first so the shader can reference it.

- [ ] **Step 1: Create the textures directory and a 16x16 placeholder PNG**

Generate a simple 16x16 stone brick pattern programmatically using ImageMagick. The pattern has horizontal mortar lines at rows 0 and 8, vertical mortar at columns 0 and 8 (offset by 4 on the second row), creating a classic brick layout. Mortar is dark gray `#3a3a3a`, bricks are medium gray `#7a7a7a` with slight variation.

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
mkdir -p textures
convert -size 16x16 xc:'#7a7a7a' \
  -fill '#6e6e6e' -draw "rectangle 1,1 7,7" \
  -fill '#7a7a7a' -draw "rectangle 9,1 15,7" \
  -fill '#6e6e6e' -draw "rectangle 5,9 11,15" \
  -fill '#7a7a7a' -draw "rectangle 13,9 15,15" \
  -fill '#7a7a7a' -draw "rectangle 0,9 3,15" \
  -fill '#3a3a3a' -draw "line 0,0 15,0" \
  -fill '#3a3a3a' -draw "line 0,8 15,8" \
  -fill '#3a3a3a' -draw "point 0,1 0,2 0,3 0,4 0,5 0,6 0,7" \
  -fill '#3a3a3a' -draw "point 8,1 8,2 8,3 8,4 8,5 8,6 8,7" \
  -fill '#3a3a3a' -draw "point 4,9 4,10 4,11 4,12 4,13 4,14 4,15" \
  -fill '#3a3a3a' -draw "point 12,9 12,10 12,11 12,12 12,13 12,14 12,15" \
  textures/wall.png
```

If ImageMagick is not available, use Python PIL or manually create a 16x16 PNG with any image tool. The exact pattern doesn't matter for development — it just needs to be a visible non-uniform 16x16 image.

- [ ] **Step 2: Verify the file exists**

```bash
file textures/wall.png
```

Expected: `textures/wall.png: PNG image data, 16 x 16, ...`

- [ ] **Step 3: Commit**

```bash
git add textures/wall.png
git commit -m "asset: add placeholder 16x16 wall texture"
```

---

### Task 2: Rewrite the fragment shader with wall rendering logic

**Files:**
- Modify: `shaders/render_chunk.gdshader` (complete rewrite of file)

- [ ] **Step 1: Write the new shader**

Replace the entire contents of `shaders/render_chunk.gdshader` with:

```glsl
shader_type canvas_item;

uniform sampler2D chunk_data : filter_nearest;
uniform sampler2D wall_texture : filter_nearest;
uniform int wall_height = 16;

const int CHUNK_SIZE = 256;
const int AIR = 0;

// Read material data at a pixel position in the chunk texture.
// Returns vec4(material, health, temperature, reserved) in 0-255 range conceptually,
// but as normalized floats from the RGBA8 texture.
vec4 read_pixel(ivec2 pos) {
	vec2 uv = (vec2(pos) + 0.5) / float(CHUNK_SIZE);
	uv.y = 1.0 - uv.y; // Y-flip: texture y=0 is top, screen y=0 is top
	return texture(chunk_data, uv);
}

int get_material(vec4 data) {
	return int(round(data.r * 255.0));
}

bool is_solid(ivec2 pos) {
	// Out-of-bounds treated as solid
	if (pos.x < 0 || pos.x >= CHUNK_SIZE || pos.y < 0 || pos.y >= CHUNK_SIZE) {
		return true;
	}
	return get_material(read_pixel(pos)) != AIR;
}

// Compute material color from pixel data (same logic as original shader).
vec3 material_color(vec4 data) {
	int mat = get_material(data);
	float health = data.g;
	float temperature = data.b;

	if (mat == 1) {
		// Wood — tint toward red with temperature
		vec3 wood_color = vec3(0.55, 0.35, 0.17);
		vec3 hot_color = vec3(0.8, 0.2, 0.1);
		return mix(wood_color, hot_color, temperature);
	} else if (mat == 2) {
		// Fire — orange to red based on health
		vec3 fire_bright = vec3(1.0, 0.6, 0.1);
		vec3 fire_dim = vec3(0.8, 0.1, 0.0);
		return mix(fire_dim, fire_bright, health);
	}
	// Fallback (unknown solid material)
	return vec3(1.0, 0.0, 1.0);
}

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

void fragment() {
	// Convert UV to pixel coordinates in texture space.
	// UV (0,0) is top-left on screen. Texture pixel (0,0) is also top-left.
	// The Y-flip is handled inside read_pixel().
	ivec2 px = ivec2(UV * float(CHUNK_SIZE));
	px = clamp(px, ivec2(0), ivec2(CHUNK_SIZE - 1));

	vec4 data = read_pixel(px);
	int mat = get_material(data);

	if (mat == AIR) {
		// --- Wall face check ---
		// Scan "upward on screen" = decreasing py in texture space (since screen y=0 is top).
		// A solid pixel at py - d has its wall face extruding downward into this air pixel.
		for (int d = 1; d <= wall_height; d++) {
			ivec2 check_pos = ivec2(px.x, px.y - d);
			if (check_pos.y < 0) break; // past top of chunk
			vec4 src_data = read_pixel(check_pos);
			int src_mat = get_material(src_data);
			if (src_mat != AIR) {
				// Found the solid pixel casting a wall face here.
				// Sample wall texture: column from pixel x, row from distance.
				ivec2 tex_size = textureSize(wall_texture, 0);
				float u = (float(px.x % tex_size.x) + 0.5) / float(tex_size.x);
				float v = (float(d - 1) + 0.5) / float(wall_height);
				vec3 tex_color = texture(wall_texture, vec2(u, v)).rgb;
				vec3 tint = material_color(src_data);
				COLOR = vec4(tex_color * tint, 1.0);
				return;
			}
		}
		// No solid above within wall_height — transparent air
		COLOR = vec4(0.0);
	} else {
		// --- Solid pixel: wall top or black ---
		if (near_air(px)) {
			// Close to air: render visible wall top with material color
			COLOR = vec4(material_color(data), 1.0);
		} else {
			// Deep interior: black
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
	}
}
```

**Key details for the implementing engineer:**

- `read_pixel()` handles the Y-flip internally so all other code works in screen-space coordinates where `(0,0)` is top-left and `y` increases downward.
- `is_solid()` returns `true` for out-of-bounds positions (spec: treat as solid).
- The wall face scan goes from `d=1` to `wall_height`, checking `py - d` (upward on screen). The first solid hit draws the face.
- `near_air()` loops a 7x7 box with euclidean radius 3, early-exits on first air found.
- Per the spec, the wall top is drawn with material color if near air, black otherwise. The spec's distinction between "solid below" and "air below" cases both resolve to the same output (material color if near air, black if not), so the shader just checks `near_air()`.

- [ ] **Step 2: Verify the shader parses**

Open the project in Godot and check the shader editor for `render_chunk.gdshader`. There should be no parse errors. Alternatively, check the Godot console output for shader compilation errors.

```bash
# If running headless Godot is available:
cd /home/jeremy/Development/Godot/top-down-rogue
# Just verify the file is syntactically valid GLSL by opening in editor
```

- [ ] **Step 3: Commit**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat: rewrite render shader with fake wall extrusion"
```

---

### Task 3: Pass wall uniforms from world_manager.gd

**Files:**
- Modify: `scripts/world_manager.gd:28-29` (add wall texture preload)
- Modify: `scripts/world_manager.gd:188-191` (set shader parameters in `_create_chunk`)

- [ ] **Step 1: Add wall texture preload**

In `scripts/world_manager.gd`, add the wall texture preload after the existing `render_shader` variable declaration. After line 19 (`var _gen_uniform_sets_to_free: Array[RID] = []`), add:

```gdscript
var wall_texture: Texture2D = preload("res://textures/wall.png")
```

- [ ] **Step 2: Set wall uniforms on chunk materials**

In the `_create_chunk()` function, after the line `mat.set_shader_parameter("chunk_data", chunk.texture_2d_rd)` (line 190), add:

```gdscript
		mat.set_shader_parameter("wall_texture", wall_texture)
		mat.set_shader_parameter("wall_height", 16)
```

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: pass wall texture and height uniforms to render shader"
```

---

### Task 4: Visual verification

**Files:** None (verification only)

- [ ] **Step 1: Run the project and verify wall rendering**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue
# Open in Godot editor and run (F5), or:
# godot --path . --scene scenes/main.tscn
```

Verify the following visually:

1. **Cave interiors** (air areas) are transparent/empty as before
2. **Wall edges** adjacent to caves show their material color (brown for wood) on the top face
3. **Below wall edges** on screen, textured wall faces extrude downward (up to 16 pixels)
4. **Wall face texture** shows the brick/stone pattern from `wall.png`, tinted by the material color
5. **Deep interior walls** (>3px from any air) are solid black
6. **Adjacent wall face columns** are visually continuous (no tiling seams between neighboring pixels)
7. **Fire** near walls tints both the top face and any wall faces with the fire color gradient
8. **Chunk boundaries** don't show obvious visual artifacts (interior edges at boundaries should be black)

- [ ] **Step 2: Test edge cases**

- Place fire (left click) near a wall edge — verify the wall face updates to show fire tinting
- Move camera to chunk boundaries — verify no gaps or visual seams in wall extrusion
- Zoom in to verify pixel-crisp rendering (no blurring on wall faces)

- [ ] **Step 3: Commit any fixes if needed, or confirm done**

If everything looks correct, no additional commit needed. If coordinate conventions need adjusting (e.g., wall faces extrude the wrong direction), fix the scan direction in the shader and re-test.
