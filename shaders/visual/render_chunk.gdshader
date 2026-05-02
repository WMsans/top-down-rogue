shader_type canvas_item;

// Material constants. Mirrors MaterialTable::_populate() in
// gdextension/src/sim/material_table.cpp — keep IDs and per-material values
// in sync when adding or reordering materials there.
const int MAT_AIR = 0;
const int MAT_WOOD = 1;
const int MAT_STONE = 2;
const int MAT_GAS = 3;
const int MAT_LAVA = 4;
const int MAT_DIRT = 5;
const int MAT_COAL = 6;
const int MAT_ICE = 7;
const int MAT_WATER = 8;

const bool HAS_COLLIDER[9] = bool[9](
	false, true, true, false, false, true, true, true, true
);

const vec4 MATERIAL_TINT[9] = vec4[9](
	vec4(0.0, 0.0, 0.0, 0.0),
	vec4(0.0, 0.0, 0.0, 0.0),
	vec4(0.0, 0.0, 0.0, 0.0),
	vec4(0.4, 0.9, 0.3, 1.0),
	vec4(0.9, 0.4, 0.1, 1.0),
	vec4(0.45, 0.32, 0.18, 1.0),
	vec4(0.12, 0.12, 0.14, 1.0),
	vec4(0.7, 0.85, 0.95, 1.0),
	vec4(0.2, 0.45, 0.75, 1.0)
);

const float MATERIAL_GLOW[9] = float[9](
	0.0, 0.0, 0.0, 0.0, 10.0, 0.0, 20.0, 0.0, 0.0
);

uniform sampler2DArray chunk_data : filter_nearest;
uniform sampler2DArray neighbor_data : filter_nearest;
uniform bool has_neighbor = false;
uniform int wall_height = 16;
uniform sampler2DArray material_textures : filter_nearest;
uniform int layer_mode = 0;

const int CHUNK_SIZE = 256;
const int TILE_SIZE = 64;
const int TILES_PER_SIDE = 4;

vec3 srgb_to_linear(vec3 srgb) {
	return mix(
		srgb / 12.92,
		pow((srgb + 0.055) / 1.055, vec3(2.4)),
		greaterThan(srgb, vec3(0.04045))
	);
}

// Read material data at a pixel position in the chunk texture.
// Returns vec4(material, health, temperature, reserved) in 0-255 range conceptually,
// but as normalized floats from the RGBA8 texture.
vec4 read_pixel(ivec2 pos) {
	int tile_x = pos.x / TILE_SIZE;
	int tile_y = pos.y / TILE_SIZE;
	int layer = tile_y * TILES_PER_SIDE + tile_x;
	ivec2 local = pos - ivec2(tile_x * TILE_SIZE, tile_y * TILE_SIZE);
	vec2 uv = (vec2(local) + 0.5) / float(TILE_SIZE);
	uv.y = 1.0 - uv.y;
	return texture(chunk_data, vec3(uv, float(layer)));
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
	return HAS_COLLIDER[m];
}

// Read from neighboring chunk texture (for wall face scan overflow).
// neighbor_pos is in the neighbor's local px coordinate space.
vec4 read_neighbor(ivec2 neighbor_pos) {
	int tile_x = neighbor_pos.x / TILE_SIZE;
	int tile_y = neighbor_pos.y / TILE_SIZE;
	int layer = tile_y * TILES_PER_SIDE + tile_x;
	ivec2 local = neighbor_pos - ivec2(tile_x * TILE_SIZE, tile_y * TILE_SIZE);
	vec2 uv = (vec2(local) + 0.5) / float(TILE_SIZE);
	uv.y = 1.0 - uv.y;
	return texture(neighbor_data, vec3(uv, float(layer)));
}

// Read pixel data, crossing into neighbor chunk when pos.y >= CHUNK_SIZE.
vec4 read_pixel_extended(ivec2 pos) {
	if (pos.y < CHUNK_SIZE) {
		return read_pixel(pos);
	}
	if (!has_neighbor) {
		return vec4(0.0); // air fallback
	}
	return read_neighbor(ivec2(pos.x, pos.y - CHUNK_SIZE));
}

bool is_solid_extended(ivec2 pos) {
	if (pos.x < 0 || pos.x >= CHUNK_SIZE) {
		return true;
	}
	if (pos.y < 0) {
		return true;
	}
	if (pos.y < CHUNK_SIZE) {
		int m = get_material(read_pixel(pos));
		return HAS_COLLIDER[m];
	}
	if (!has_neighbor) {
		return false; // no neighbor = treat as air (no fake wall faces)
	}
	int m = get_material(read_neighbor(ivec2(pos.x, pos.y - CHUNK_SIZE)));
	return HAS_COLLIDER[m];
}

vec3 ember_color(float temp_norm) {
	vec3 dark_red = vec3(0.3, 0.0, 0.0);
	vec3 orange = vec3(0.9, 0.4, 0.0);
	vec3 yellow_white = vec3(1.0, 0.9, 0.5);
	
	if (temp_norm < 0.85) {
		float t = (temp_norm - 0.7) / 0.15;
		return mix(dark_red, orange, t);
	} else {
		float t = (temp_norm - 0.85) / 0.15;
		return mix(orange, yellow_white, t);
	}
}

vec3 get_material_top_color(int material, int src_x) {
	vec2 tex_size = vec2(textureSize(material_textures, 0).xy);
	float u = (float(src_x % int(tex_size.x)) + 0.5) / tex_size.x;
	float v = 0.5 / float(wall_height);
	vec3 srgb = texture(material_textures, vec3(u, v, float(material))).rgb;
	return srgb_to_linear(srgb);
}

vec3 get_temperature_tint(float temperature) {
	if (temperature > 180.0 / 255.0) {
		return ember_color(temperature);
	}
	return vec3(1.0);
}

vec3 apply_temperature_tint(vec3 base_color, float temperature) {
	if (temperature > 180.0 / 255.0) {
		return ember_color(temperature);
	}
	float temp_norm = temperature;
	float temp_affected = temp_norm * 0.7;
	vec3 hot_tint = vec3(1.0, 0.3, 0.1);
	return mix(base_color, base_color * hot_tint + vec3(0.2, 0.0, 0.0), temp_affected);
}

vec3 material_color(vec4 data, ivec2 pixel_pos) {
	int mat = get_material(data);
	if (mat == MAT_AIR) {
		return vec3(1.0, 0.0, 1.0);
	}
	vec3 base_color = get_material_top_color(mat, pixel_pos.x);
	// Glow is additive emissive on top of the base color: 0 for ordinary
	// materials, >0 for emitters (lava, coal) so they bloom under HDR.
	return apply_temperature_tint(base_color, data.b) * (1.0 + MATERIAL_GLOW[mat]);
}

vec3 sample_material_texture(int material, int src_x, int depth, vec4 src_data, ivec2 pixel_pos) {
	vec2 tex_size = vec2(textureSize(material_textures, 0).xy);
	float u = (float(src_x % int(tex_size.x)) + 0.5) / tex_size.x;
	float v = (float(depth - 1) + 0.5) / float(wall_height);
	vec3 srgb = texture(material_textures, vec3(u, v, float(material))).rgb;
	vec3 tex_color = srgb_to_linear(srgb);
	vec3 tint = get_temperature_tint(src_data.b);
	return tex_color * tint * (1.0 + MATERIAL_GLOW[material]);
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
	ivec2 px = ivec2(UV * float(CHUNK_SIZE));
	px = clamp(px, ivec2(0), ivec2(CHUNK_SIZE - 1));

	vec4 data = read_pixel(px);
	int mat = get_material(data);

	// --- Fluid overlay: remember the tint and fall through as if this cell were air. ---
	vec4 fluid_tint = vec4(0.0);
	float fluid_alpha = 0.0;
	if (mat == MAT_GAS || mat == MAT_LAVA) {
		vec4 tint = MATERIAL_TINT[mat];
		fluid_tint = vec4(tint.rgb * MATERIAL_GLOW[mat], 1.0);
		// Ensure visibility even at low density: minimum 25% alpha, scales to tint.a at max
		fluid_alpha = mix(0.25, tint.a, data.g);
		mat = MAT_AIR;
	}

	vec4 base_color = vec4(0.0);

	if (mat == MAT_AIR) {
		if (layer_mode == 0) {
			base_color = vec4(0.0);
		} else {
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
			if (!found_wall) {
				base_color = vec4(0.0);
			}
		}
	} else {
		if (layer_mode == 1) {
			base_color = vec4(0.0);
		} else {
			if (near_air(px)) {
				base_color = vec4(material_color(data, px), 1.0);
			} else {
				base_color = vec4(0.0, 0.0, 0.0, 1.0);
			}
		}
	}

	// --- Composite fluid tint over base color. Preserves wall faces behind fluid. ---
	if (fluid_alpha > 0.0) {
		// Straight-alpha over: out.rgb = mix(base.rgb, tint.rgb, fluid_alpha);
		//                     out.a   = base.a + (1 - base.a) * fluid_alpha
		//                             = max(base.a, fluid_alpha) for our base.a ∈ {0,1}
		vec3 rgb = mix(base_color.rgb, fluid_tint.rgb, fluid_alpha);
		float a = max(base_color.a, fluid_alpha);
		COLOR = vec4(rgb, a);
	} else {
		COLOR = base_color;
	}
}
