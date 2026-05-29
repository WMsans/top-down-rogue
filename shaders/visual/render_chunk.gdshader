shader_type canvas_item;
#include "res://shaders/generated/materials.gdshaderinc"

uniform sampler2D chunk_data : filter_nearest;
uniform sampler2D neighbor_data : filter_nearest;
uniform bool has_neighbor = false;
uniform int wall_height = 16;
uniform sampler2DArray material_textures : filter_nearest;
uniform int layer_mode = 0;
uniform bool ao_enabled = true;
uniform float ao_radius = 3.5;          // reach of floor/corner shadow, in px
uniform float ao_intensity = 0.4;       // max floor/corner darkening (0..1)
uniform float face_ao_intensity = 0.4;  // max darkening at bottom of wall face

const int CHUNK_SIZE = 256;
const int AO_MAX_RADIUS = 6;            // compile-time loop bound for ao_occlusion

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
	return HAS_COLLIDER[m];
}

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

// Read from neighboring chunk texture (for wall face scan overflow).
// neighbor_pos is in the neighbor's local px coordinate space.
vec4 read_neighbor(ivec2 neighbor_pos) {
	vec2 uv = (vec2(neighbor_pos) + 0.5) / float(CHUNK_SIZE);
	uv.y = 1.0 - uv.y;
	return texture(neighbor_data, uv);
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

float effective_glow(int mat, float temperature) {
	float base_glow = MATERIAL_GLOW[mat];
	if (IS_FLAMMABLE[mat] && temperature > float(IGNITION_TEMP[mat]) / 255.0) {
		float ignition = float(IGNITION_TEMP[mat]) / 255.0;
		float burn_intensity = (temperature - ignition) / (1.0 - ignition);
		return max(base_glow, mix(1.0, 10.0, burn_intensity));
	}
	return base_glow;
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
	return apply_temperature_tint(base_color, data.b) * effective_glow(mat, data.b);
}

vec3 sample_material_texture(int material, int src_x, int depth, vec4 src_data, ivec2 pixel_pos) {
	vec2 tex_size = vec2(textureSize(material_textures, 0).xy);
	float u = (float(src_x % int(tex_size.x)) + 0.5) / tex_size.x;
	float v = (float(depth - 1) + 0.5) / float(wall_height);
	vec3 srgb = texture(material_textures, vec3(u, v, float(material))).rgb;
	vec3 tex_color = srgb_to_linear(srgb);
	vec3 tint = get_temperature_tint(src_data.b);
	return tex_color * tint * effective_glow(material, src_data.b);
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
	if (mat == MAT_GAS || mat == MAT_LAVA || mat == MAT_BLOOD) {
		vec4 tint = MATERIAL_TINT[mat];
		fluid_tint = vec4(tint.rgb * MATERIAL_GLOW[mat], 1.0);
		// Ensure visibility even at low density: minimum 25% alpha, scales to tint.a at max
		fluid_alpha = mix(0.25, tint.a, data.g);
		mat = MAT_AIR;
	}

	if (mat == MAT_DUST) {
		int dust_src = int(round(data.b * 255.0));
		vec3 dust_rgb = get_material_top_color(dust_src, px.x);
		dust_rgb = mix(dust_rgb, vec3(1.0), 0.25);
		fluid_tint = vec4(dust_rgb, 1.0);
		fluid_alpha = mix(0.4, 0.95, data.g);
		mat = MAT_AIR;
	}

	// Explode wave: fiery flash that fades from white-hot core to orange edge as
	// wave power decays. data.b carries the wave's remaining power (0..1).
	if (mat == MAT_EXPLODE_WAVE) {
		// data.b stores wave power / 255. Initial power is ~100/255≈0.39 and
		// decays to 0 at the edge, so remap to a 0..1 intensity for the gradient.
		float t = clamp(data.b * 2.6, 0.0, 1.0);
		vec3 core_color = vec3(1.0, 0.98, 0.75);   // white-yellow
		vec3 edge_color = vec3(1.0, 0.45, 0.10);   // deep orange
		vec3 flash_rgb = mix(edge_color, core_color, t);
		float boost = MATERIAL_GLOW[MAT_EXPLODE_WAVE] * (1.4 + t * 1.5);
		fluid_tint = vec4(flash_rgb * boost, 1.0);
		fluid_alpha = 1.0;
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
