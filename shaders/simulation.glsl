#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rgba8, set = 0, binding = 1) readonly uniform image2D neighbor_top;
layout(rgba8, set = 0, binding = 2) readonly uniform image2D neighbor_bottom;
layout(rgba8, set = 0, binding = 3) readonly uniform image2D neighbor_left;
layout(rgba8, set = 0, binding = 4) readonly uniform image2D neighbor_right;
layout(r8, set = 0, binding = 5) readonly uniform image2D occupancy_tex;

layout(push_constant, std430) uniform PushConstants {
	int phase;
	int frame_seed;
	int _pad2;
	int _pad3;
} pc;

const int CHUNK_SIZE = 256;
const int FIRE_TEMP = 255;
const int HEAT_DISSIPATION = 2;
const int HEAT_SPREAD = 10;
const float SPREAD_PROB_MAX = 0.7;

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
int get_density(vec4 p) { return int(round(p.g * 255.0)); }

vec4 make_pixel(int mat, int hp, int temp) {
    return vec4(float(mat) / 255.0, float(hp) / 255.0, float(temp) / 255.0, 0.0);
}

vec2 unpack_velocity(int packed) {
    int encoded_vx = (packed >> 4) & 0x0F;
    int encoded_vy = packed & 0x0F;
    float vx = float(encoded_vx - 8);
    float vy = float(encoded_vy - 8);
    return vec2(vx, vy);
}

int pack_velocity(vec2 vel) {
    int encoded_vx = int(clamp(vel.x + 8.0, 0.0, 15.0));
    int encoded_vy = int(clamp(vel.y + 8.0, 0.0, 15.0));
    return (encoded_vx << 4) | encoded_vy;
}

vec4 make_gas_pixel(int mat, int density, int temp, int packed_vel) {
    return vec4(
        float(mat) / 255.0,
        float(density) / 255.0,
        float(temp) / 255.0,
        float(packed_vel) / 255.0
    );
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

int read_occupancy(ivec2 pos) {
    if (pos.x < 0 || pos.x >= CHUNK_SIZE || pos.y < 0 || pos.y >= CHUNK_SIZE) {
        return 0;
    }
    vec4 occ = imageLoad(occupancy_tex, pos);
    return int(round(occ.r * 255.0));
}

bool is_burning(vec4 p) {
    int mat = get_material(p);
    return IS_FLAMMABLE[mat] && get_temperature(p) > IGNITION_TEMP[mat];
}

bool is_blocked(ivec2 pos) {
    vec4 neighbor_data = read_neighbor(pos);
    int neighbor_mat = get_material(neighbor_data);
    if (HAS_COLLIDER[neighbor_mat]) {
        return true;
    }
    if (read_occupancy(pos) > 0) {
        return true;
    }
    return false;
}

vec4 simulate_gas(ivec2 pos, vec4 pixel, uint rng) {
    int mat = get_material(pixel);
    int density = get_density(pixel);
    int temp = get_temperature(pixel);
    int packed_vel = int(round(pixel.a * 255.0));
    vec2 vel = unpack_velocity(packed_vel);
    
    float new_density = float(density);
    vec2 new_vel = vel;
    int new_temp = temp;
    
    new_vel *= 0.98;
    
    int free_neighbors = 0;
    ivec2 neighbors[4] = ivec2[4](
        pos + ivec2(0, -1),
        pos + ivec2(0, 1),
        pos + ivec2(-1, 0),
        pos + ivec2(1, 0)
    );
    
    for (int i = 0; i < 4; i++) {
        if (!is_blocked(neighbors[i])) {
            vec4 n_data = read_neighbor(neighbors[i]);
            int n_mat = get_material(n_data);
            if (n_mat == MAT_AIR || n_mat == mat) {
                free_neighbors++;
            }
        }
    }
    
    if (read_occupancy(pos) > 0) {
        int push_count = 0;
        vec2 push_dir = vec2(0.0);
        for (int i = 0; i < 4; i++) {
            if (!is_blocked(neighbors[i])) {
                push_dir += normalize(vec2(neighbors[i] - pos));
                push_count++;
            }
        }
        if (push_count > 0) {
            push_dir /= float(push_count);
            new_vel += push_dir * 2.0;
            new_density = max(0.0, new_density - 20.0);
        }
    }
    
    new_vel = clamp(new_vel, vec2(-8.0), vec2(8.0));
    new_density = max(0.0, min(255.0, new_density));
    new_temp = max(0, min(255, new_temp));
    
    int new_packed_vel = pack_velocity(new_vel);
    int new_density_int = int(round(new_density));
    
    if (new_density_int <= 0) {
        return make_pixel(MAT_AIR, 0, 0);
    }
    
    return make_gas_pixel(mat, new_density_int, new_temp, new_packed_vel);
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

    if (IS_GAS[material]) {
        uint base_rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
        vec4 result = simulate_gas(pos, pixel, base_rng);
        imageStore(chunk_tex, pos, result);
        return;
    }

    // Accumulate random heat from each burning neighbor (with probability)
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

	if (material == MAT_AIR) {
		temperature = max(0, temperature - HEAT_DISSIPATION);
	} else if (IS_FLAMMABLE[material]) {
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