# Temperature-Driven Burning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove FIRE material type and make wood burn based on temperature while staying as WOOD material.

**Architecture:** Wood with temperature above IGNITION_TEMP is "burning" - it spreads heat to neighbors, consumes health, and eventually becomes air. No material conversion happens.

**Tech Stack:** GLSL compute shaders, Godot 4.x

---

## File Structure

| File | Change |
|------|--------|
| `shaders/simulation.glsl` | Remove MAT_FIRE, update wood burning logic |
| `shaders/render_chunk.gdshader` | Remove FIRE material handling |
| `scripts/world_manager.gd` | Update place_fire to heat wood instead of creating FIRE |

---

### Task 1: Update simulation.glsl - Remove FIRE Material

**Files:**
- Modify: `shaders/simulation.glsl`

- [ ] **Step 1: Remove MAT_FIRE constant and update wood burning logic**

Replace the constants and update the simulation logic. The key changes:
1. Remove `MAT_FIRE` constant
2. Remove counting of fire neighbors (replaced by burning wood neighbors)
3. Wood with high temp spreads heat and burns down

```glsl
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rgba8, set = 0, binding = 1) readonly uniform image2D neighbor_top;
layout(rgba8, set = 0, binding = 2) readonly uniform image2D neighbor_bottom;
layout(rgba8, set = 0, binding = 3) readonly uniform image2D neighbor_left;
layout(rgba8, set = 0, binding = 4) readonly uniform image2D neighbor_right;

layout(push_constant, std430) uniform PushConstants {
	int phase;
	int _pad1;
	int _pad2;
	int _pad3;
} pc;

const int CHUNK_SIZE = 256;
const int MAT_AIR = 0;
const int MAT_WOOD = 1;
const int IGNITION_TEMP = 180;
const int FIRE_TEMP = 255;
const int HEAT_DISSIPATION = 2;
const int HEAT_SPREAD = 10;

int get_material(vec4 p) { return int(round(p.r * 255.0)); }
int get_health(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature(vec4 p) { return int(round(p.b * 255.0)); }

vec4 make_pixel(int mat, int hp, int temp) {
	return vec4(float(mat) / 255.0, float(hp) / 255.0, float(temp) / 255.0, 0.0);
}

vec4 read_neighbor(ivec2 pos) {
	if (pos.x >= 0 && pos.x < CHUNK_SIZE && pos.y >= 0 && pos.y < CHUNK_SIZE) {
		return imageLoad(chunk_tex, pos);
	}
	if (pos.y < 0) {
		return imageLoad(neighbor_top, ivec2(pos.x, CHUNK_SIZE + pos.y));
	}
	if (pos.y >= CHUNK_SIZE) {
		return imageLoad(neighbor_bottom, ivec2(pos.x, pos.y - CHUNK_SIZE));
	}
	if (pos.x < 0) {
		return imageLoad(neighbor_left, ivec2(CHUNK_SIZE + pos.x, pos.y));
	}
	if (pos.x >= CHUNK_SIZE) {
		return imageLoad(neighbor_right, ivec2(pos.x - CHUNK_SIZE, pos.y));
	}
	return vec4(0.0);
}

bool is_burning(vec4 p) {
	return get_material(p) == MAT_WOOD && get_temperature(p) > IGNITION_TEMP;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

	// Checkerboard: skip if not this phase
	if ((pos.x + pos.y) % 2 != pc.phase) return;

	vec4 pixel = imageLoad(chunk_tex, pos);
	int material = get_material(pixel);
	int health = get_health(pixel);
	int temperature = get_temperature(pixel);

	// Read cardinal neighbors
	vec4 n_up = read_neighbor(pos + ivec2(0, -1));
	vec4 n_down = read_neighbor(pos + ivec2(0, 1));
	vec4 n_left = read_neighbor(pos + ivec2(-1, 0));
	vec4 n_right = read_neighbor(pos + ivec2(1, 0));

	// Count burning neighbors (wood with high temperature)
	int burning_neighbors = 0;
	if (is_burning(n_up)) burning_neighbors++;
	if (is_burning(n_down)) burning_neighbors++;
	if (is_burning(n_left)) burning_neighbors++;
	if (is_burning(n_right)) burning_neighbors++;

	if (material == MAT_AIR) {
		temperature = max(0, temperature - HEAT_DISSIPATION);
	} else if (material == MAT_WOOD) {
		temperature = min(255, temperature + burning_neighbors * HEAT_SPREAD);
		temperature = max(0, temperature - HEAT_DISSIPATION);
		if (temperature > IGNITION_TEMP) {
			health = health - 1;
			temperature = FIRE_TEMP;
			if (health <= 0) {
				material = MAT_AIR;
				health = 0;
				temperature = 0;
			}
		}
	}

	imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
}
```

- [ ] **Step 2: Commit simulation.glsl changes**

```bash
git add shaders/simulation.glsl
git commit -m "feat: remove MAT_FIRE, make wood burn based on temperature"
```

---

### Task 2: Update render_chunk.gdshader - Remove FIRE Rendering

**Files:**
- Modify: `shaders/render_chunk.gdshader`

- [ ] **Step 1: Remove FIRE constant and fire rendering case**

```glsl
shader_type canvas_item;

uniform sampler2D chunk_data : filter_nearest;
uniform sampler2D wall_texture : filter_nearest;
uniform int wall_height = 16;

const int CHUNK_SIZE = 256;
const int AIR = 0;
const int WOOD = 1;

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
	int m = get_material(read_pixel(pos));
	return m != AIR;
}

// Compute material color from pixel data (same logic as original shader).
vec3 material_color(vec4 data) {
	int mat = get_material(data);
	float health = data.g;
	float temperature = data.b;

	if (mat == WOOD) {
		// Wood — tint toward red with temperature
		vec3 wood_color = vec3(0.55, 0.35, 0.17);
		vec3 hot_color = vec3(0.8, 0.2, 0.1);
		return mix(wood_color, hot_color, temperature);
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
		// Scan upward on screen: due to Y-flip in read_pixel, "above on screen" is px.y + d.
		ivec2 tex_size = textureSize(wall_texture, 0);
		bool found_wall = false;
		for (int d = 1; d <= wall_height; d++) {
			if (found_wall) break;
			ivec2 check_pos = ivec2(px.x, px.y + d);
			if (check_pos.y >= CHUNK_SIZE) break;
			vec4 src_data = read_pixel(check_pos);
			if (is_solid(check_pos)) {
				// Found the solid pixel casting a wall face here.
				// V stretches the texture to fill wall_height, not tex_size.y.
				float u = (float(px.x % tex_size.x) + 0.5) / float(tex_size.x);
				float v = (float(d - 1) + 0.5) / float(wall_height);
				vec3 tex_color = texture(wall_texture, vec2(u, v)).rgb;
				vec3 tint = material_color(src_data);
				COLOR = vec4(tex_color * tint, 1.0);
				found_wall = true;
			}
		}
		if (!found_wall) {
			COLOR = vec4(0.0);
		}
	} else {
		// --- Solid pixel (wood etc.): wall top or black ---
		if (near_air(px)) {
			COLOR = vec4(material_color(data), 1.0);
		} else {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		}
	}
}
```

- [ ] **Step 2: Commit render shader changes**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat: remove FIRE material handling from render shader"
```

---

### Task 3: Update world_manager.gd - Modify place_fire

**Files:**
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Update place_fire to heat wood instead of creating FIRE material**

The only change is in the `place_fire` function. Replace lines 338-344:

```gdscript
func place_fire(world_pos: Vector2, radius: float) -> void:
	var center_x := int(floor(world_pos.x))
	var center_y := int(floor(world_pos.y))
	var r := int(ceil(radius))

	# Group affected pixels by chunk
	var affected: Dictionary = {}  # Vector2i -> Array[Vector2i]
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var wx := center_x + dx
			var wy := center_y + dy
			var chunk_coord := Vector2i(floori(float(wx) / CHUNK_SIZE), floori(float(wy) / CHUNK_SIZE))
			if not chunks.has(chunk_coord):
				continue
			var local := Vector2i(posmod(wx, CHUNK_SIZE), posmod(wy, CHUNK_SIZE))
			if not affected.has(chunk_coord):
				affected[chunk_coord] = []
			affected[chunk_coord].append(local)

	for chunk_coord in affected:
		var chunk: Chunk = chunks[chunk_coord]
		var data := rd.texture_get_data(chunk.rd_texture, 0)
		for pixel_pos: Vector2i in affected[chunk_coord]:
			var idx := (pixel_pos.y * CHUNK_SIZE + pixel_pos.x) * 4
			var material := data[idx]
			if material != 1:  # Only heat wood (material=1)
				continue
			data[idx + 2] = 255  # temperature = 255 (max heat)
		rd.texture_update(chunk.rd_texture, 0, data)
```

- [ ] **Step 2: Commit world_manager changes**

```bash
git add scripts/world_manager.gd
git commit -m "feat: place_fire heats wood instead of creating FIRE material"
```

---

## Testing

After implementing all changes, manually test in the Godot editor:

1. Run the project
2. Click to place fire on wood - should see wood turn red/orange and start burning
3. Fire should spread to adjacent wood
4. Burning wood should eventually disappear (become air)
5. No FIRE material pixels should ever appear