#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rgba8, set = 0, binding = 1) readonly uniform image2D neighbor_top;
layout(rgba8, set = 0, binding = 2) readonly uniform image2D neighbor_bottom;
layout(rgba8, set = 0, binding = 3) readonly uniform image2D neighbor_left;
layout(rgba8, set = 0, binding = 4) readonly uniform image2D neighbor_right;

layout(push_constant, std430) uniform PushConstants {
	int phase;
	int frame_seed;
	int _pad2;
	int _pad3;
} pc;

struct InjectionAABB {
	ivec2 aabb_min;
	ivec2 aabb_max;
	ivec2 velocity;
	int _pad0;
	int _pad1;
};

layout(set = 0, binding = 5, std430) readonly buffer InjectionBuffer {
	int count;
	int _pad[3];
	InjectionAABB bodies[];
} injections;

const int CHUNK_SIZE = 256;
const int FIRE_TEMP = 255;
const int HEAT_DISSIPATION = 2;
const int HEAT_SPREAD = 10;
const float SPREAD_PROB_MAX = 0.7;
// --- Gas simulation constants ---
const int V_MAX_OUTFLOW = 8;
const int THRESHOLD_BECOME_GAS = 4;
const int THRESHOLD_DISSIPATE = 4;
const int MAX_INJECTIONS_PER_CHUNK = 32;

uint hash(uint n) {
	n = (n >> 16) ^ n;
	n *= 0xed5ad0bb;
	n = (n >> 16) ^ n;
	n *= 0xac4c1b51;
	n = (n >> 16) ^ n;
	return n;
}

int get_material(vec4 p) { return int(round(p.r * 255.0)); }
int get_health(vec4 p) { return int(round(p.g * 255.0)); }
int get_temperature(vec4 p) { return int(round(p.b * 255.0)); }

vec4 make_pixel(int mat, int hp, int temp) {
	return vec4(float(mat) / 255.0, float(hp) / 255.0, float(temp) / 255.0, 0.0);
}

int get_density(vec4 p) { return int(round(p.g * 255.0)); }

ivec2 unpack_velocity(vec4 p) {
	uint a = uint(round(p.a * 255.0));
	return ivec2(int(a >> 4) - 8, int(a & 15u) - 8);
}

vec4 pack_gas(int density, ivec2 vel) {
	int vx = clamp(vel.x + 8, 0, 15);
	int vy = clamp(vel.y + 8, 0, 15);
	uint a = (uint(vx) << 4) | uint(vy);
	return vec4(
		float(MAT_GAS) / 255.0,
		float(clamp(density, 0, 255)) / 255.0,
		0.0,
		float(a) / 255.0
	);
}

// Returns true if this cell was overwritten by an injection and main() should return.
bool try_inject_rigidbody_velocity(ivec2 pos, int material, inout vec4 pixel) {
	return false;  // stub — Task 5
}

// Gas advection for gas AND air cells. Writes pixel via imageStore and returns.
void gas_advect_pull(
	ivec2 pos, vec4 pixel,
	vec4 n_up, vec4 n_down, vec4 n_left, vec4 n_right
) {
	// Stub — Task 4 replaces this body. For now, preserve existing behavior:
	int material = get_material(pixel);
	int health = get_health(pixel);
	int temperature = get_temperature(pixel);
	if (material == MAT_AIR) {
		temperature = max(0, temperature - HEAT_DISSIPATION);
	}
	imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
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
	int mat = get_material(p);
	return IS_FLAMMABLE[mat] && get_temperature(p) > IGNITION_TEMP[mat];
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

	vec4 pixel = imageLoad(chunk_tex, pos);
	int material = get_material(pixel);

	// 1. Rigidbody AABB injection — returns if the cell was written.
	if (try_inject_rigidbody_velocity(pos, material, pixel)) return;

	// 2. Neighbor reads used by both gas and burning.
	vec4 n_up    = read_neighbor(pos + ivec2(0, -1));
	vec4 n_down  = read_neighbor(pos + ivec2(0,  1));
	vec4 n_left  = read_neighbor(pos + ivec2(-1, 0));
	vec4 n_right = read_neighbor(pos + ivec2( 1, 0));

	// 3. Gas + air path — runs every frame, pull-based, no phase guard.
	if (material == MAT_GAS || material == MAT_AIR) {
		gas_advect_pull(pos, pixel, n_up, n_down, n_left, n_right);
		return;
	}

	// 4. Checkerboard burning logic for solids.
	if ((pos.x + pos.y) % 2 != pc.phase) return;

	int health = get_health(pixel);
	int temperature = get_temperature(pixel);

	// Accumulate random heat from each burning neighbor (with probability).
	int heat_gain = 0;
	uint base_rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
	if (is_burning(n_up)) {
		int n_mat = get_material(n_up);
		int n_temp = get_temperature(n_up);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 1u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_down)) {
		int n_mat = get_material(n_down);
		int n_temp = get_temperature(n_down);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 2u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_left)) {
		int n_mat = get_material(n_left);
		int n_temp = get_temperature(n_left);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 3u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 4 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_right)) {
		int n_mat = get_material(n_right);
		int n_temp = get_temperature(n_right);
		float prob = float(n_temp - IGNITION_TEMP[n_mat]) / float(FIRE_TEMP - IGNITION_TEMP[n_mat]) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 4u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}

	if (IS_FLAMMABLE[material]) {
		temperature = min(255, temperature + heat_gain);
		temperature = max(0, temperature - HEAT_DISSIPATION);
		if (temperature > IGNITION_TEMP[material]) {
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