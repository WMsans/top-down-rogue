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