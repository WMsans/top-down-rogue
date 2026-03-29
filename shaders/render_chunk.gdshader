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
