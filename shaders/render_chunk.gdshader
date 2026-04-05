shader_type canvas_item;

uniform sampler2D chunk_data : filter_nearest;
uniform int wall_height = 16;
uniform sampler2DArray material_textures : filter_nearest;
uniform int layer_mode = 0;

const int CHUNK_SIZE = 256;
const int AIR = 0;
const int WOOD = 1;
const int STONE = 2;

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

vec3 ember_color(float temp_norm, float flicker_amt) {
	vec3 dark_red = vec3(0.3, 0.0, 0.0);
	vec3 orange = vec3(0.9, 0.4, 0.0);
	vec3 yellow_white = vec3(1.0, 0.9, 0.5);
	
	float adjusted = clamp(temp_norm + flicker_amt * 0.15, 0.0, 1.0);
	if (adjusted < 0.85) {
		float t = (adjusted - 0.7) / 0.15;
		return mix(dark_red, orange, t);
	} else {
		float t = (adjusted - 0.85) / 0.15;
		return mix(orange, yellow_white, t);
	}
}

float flicker_amount(ivec2 pixel_pos, float time, float temp_norm) {
	float px = float(pixel_pos.x);
	float py = float(pixel_pos.y);
	float a = sin(time * 8.0 + px * 0.05) * 0.5;
	float b = sin(time * 12.0 + py * 0.03) * 0.3;
	float c = sin(time * 15.0 + (px + py) * 0.04) * 0.2;
	float flicker = a + b + c;
	return flicker * (1.0 - temp_norm * 0.3);
}

vec3 get_material_top_color(int material, int src_x) {
	vec2 tex_size = vec2(textureSize(material_textures, 0).xy);
	float u = (float(src_x % int(tex_size.x)) + 0.5) / tex_size.x;
	float v = 0.5 / float(wall_height);
	return texture(material_textures, vec3(u, v, float(material))).rgb;
}

vec3 get_temperature_tint(float temperature, ivec2 pixel_pos) {
	if (temperature > 180.0 / 255.0) {
		float temp_norm = temperature;
		float flicker = flicker_amount(pixel_pos, TIME, temp_norm);
		return ember_color(temp_norm, flicker);
	}
	return vec3(1.0);
}

vec3 apply_temperature_tint(vec3 base_color, float temperature, ivec2 pixel_pos) {
	if (temperature > 180.0 / 255.0) {
		float temp_norm = temperature;
		float flicker = flicker_amount(pixel_pos, TIME, temp_norm);
		return ember_color(temp_norm, flicker);
	}
	float temp_norm = temperature;
	float temp_affected = temp_norm * 0.7;
	vec3 hot_tint = vec3(1.0, 0.3, 0.1);
	return mix(base_color, base_color * hot_tint + vec3(0.2, 0.0, 0.0), temp_affected);
}

vec3 material_color(vec4 data, ivec2 pixel_pos) {
	int mat = get_material(data);
	if (mat == AIR) {
		return vec3(1.0, 0.0, 1.0);
	}
	vec3 base_color = get_material_top_color(mat);
	return apply_temperature_tint(base_color, data.b, pixel_pos);
}

vec3 sample_material_texture(int material, int src_x, int depth, vec4 src_data, ivec2 pixel_pos) {
	vec2 tex_size = vec2(textureSize(material_textures, 0).xy);
	float u = (float(src_x % int(tex_size.x)) + 0.5) / tex_size.x;
	float v = (float(depth - 1) + 0.5) / float(wall_height);
	vec3 tex_color = texture(material_textures, vec3(u, v, float(material))).rgb;
	vec3 tint = get_temperature_tint(src_data.b, pixel_pos);
	return tex_color * tint;
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
		if (layer_mode == 0) {
			// Ground layer: air pixels are transparent
			COLOR = vec4(0.0);
		} else {
			// Wall face layer: scan upward for wall source
			bool found_wall = false;
			for (int d = 1; d <= wall_height; d++) {
				if (found_wall) break;
				ivec2 check_pos = ivec2(px.x, px.y + d);
				if (check_pos.y >= CHUNK_SIZE) break;
				vec4 src_data = read_pixel(check_pos);
				if (is_solid(check_pos)) {
					COLOR = vec4(sample_material_texture(get_material(src_data), px.x, d, src_data, px), 1.0);
					found_wall = true;
				}
			}
			if (!found_wall) {
				COLOR = vec4(0.0);
			}
		}
	} else {
		if (layer_mode == 1) {
			// Wall face layer: solid pixels are transparent
			COLOR = vec4(0.0);
		} else {
			// Ground layer: wall top or black
			if (near_air(px)) {
				COLOR = vec4(material_color(data, px), 1.0);
			} else {
				COLOR = vec4(0.0, 0.0, 0.0, 1.0);
			}
		}
	}
}
