#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

struct HitEntry {
	int world_x;
	int world_y;
	uint mat_id;
	float scale;
};

layout(set = 0, binding = 1, std430) buffer HitList {
	uint count;
	uint _pad[3];
	HitEntry entries[];
} hit_list;

layout(push_constant, std430) uniform PushConstants {
	ivec2 chunk_origin;
	vec2 origin;
	vec2 direction;
	float radius;
	float inner_radius;
	float arc_half_angle;
	float push_speed;
	float damage;
	uint target_mask_low;
	uint hit_capacity;
	uint _pad0;
	uint _pad1;
	uint _pad2;
} pc;

bool is_target(uint mat_id) {
	if (mat_id >= 32u) return false;
	return (pc.target_mask_low & (1u << mat_id)) != 0u;
}

const int DUST_SPAWN_PERCENT = 35;   // % of destroyed wall pixels that become dust
const float DUST_BURST_SPEED = 120.0; // outward burst speed (world units/sec)
const int DUST_BURST_DENSITY = 200;   // initial density of spawned dust

uint dust_hash(uint n) {
	n = (n >> 16) ^ n;
	n *= 0xed5ad0bbu;
	n = (n >> 16) ^ n;
	n *= 0xac4c1b51u;
	n = (n >> 16) ^ n;
	return n;
}

float hardness_for(uint mat_id) {
	if (mat_id == uint(MAT_DIRT)) return 0.5;
	if (mat_id == uint(MAT_WOOD)) return 2.0;
	if (mat_id == uint(MAT_COAL)) return 3.0;
	if (mat_id == uint(MAT_ICE)) return 4.0;
	if (mat_id == uint(MAT_STONE)) return 5.0;
	return 0.0;
}

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	if (local.x < 0 || local.x >= 256 || local.y < 0 || local.y >= 256) return;

	vec2 world_pos = vec2(pc.chunk_origin) + vec2(local);
	vec2 to_pixel = world_pos - pc.origin;
	float dist_sq = dot(to_pixel, to_pixel);
	float r_sq = pc.radius * pc.radius;
	if (dist_sq > r_sq) return;

	float pixel_angle = atan(to_pixel.y, to_pixel.x);
	float dir_angle = atan(pc.direction.y, pc.direction.x);
	float delta = pixel_angle - dir_angle;
	delta = atan(sin(delta), cos(delta));
	if (abs(delta) > pc.arc_half_angle) return;

	vec4 pix = imageLoad(chunk_tex, local);
	uint mat = uint(pix.r * 255.0 + 0.5);
	if (!is_target(mat)) return;

	bool do_clear = dist_sq < pc.inner_radius * pc.inner_radius;
	bool is_solid_pass = pc.damage >= 0.0;

	if (is_solid_pass) {
		float hardness = hardness_for(mat);
		float scale_clamped = clamp(pc.damage / (pc.damage + hardness), 0.1, 1.0);
		float effective_r = pc.radius * scale_clamped;
		if (dist_sq > effective_r * effective_r) return;

		uint idx = atomicAdd(hit_list.count, 1u);
		if (idx < pc.hit_capacity) {
			hit_list.entries[idx].world_x = int(world_pos.x);
			hit_list.entries[idx].world_y = int(world_pos.y);
			hit_list.entries[idx].mat_id = mat;
			hit_list.entries[idx].scale = scale_clamped;
		}

		uint h = dust_hash(uint(int(world_pos.x)) ^ dust_hash(uint(int(world_pos.y))));
		if (int(h % 100u) < DUST_SPAWN_PERCENT) {
			float len = length(to_pixel);
			vec2 outward = (len > 0.0001) ? to_pixel / len : pc.direction;
			float vx_f = outward.x * DUST_BURST_SPEED / 60.0;
			float vy_f = outward.y * DUST_BURST_SPEED / 60.0;
			int vx_enc = clamp(int(round(vx_f)) + 8, 0, 15);
			int vy_enc = clamp(int(round(vy_f)) + 8, 0, 15);
			float packed = float((vx_enc << 4) | vy_enc) / 255.0;
			imageStore(chunk_tex, local, vec4(
				float(MAT_DUST) / 255.0,
				float(DUST_BURST_DENSITY) / 255.0,
				float(mat) / 255.0,
				packed
			));
		} else {
			imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));
		}
	} else if (do_clear) {
		imageStore(chunk_tex, local, vec4(0.0, 0.0, 0.0, 0.0));
	} else {
		float dist = sqrt(dist_sq);
		vec2 push_dir = (dist > 0.0001) ? to_pixel / dist : pc.direction;
		float vx_f = push_dir.x * pc.push_speed / 60.0;
		float vy_f = push_dir.y * pc.push_speed / 60.0;
		int vx_enc = clamp(int(round(vx_f)) + 8, 0, 15);
		int vy_enc = clamp(int(round(vy_f)) + 8, 0, 15);
		float packed = float((vx_enc << 4) | vy_enc) / 255.0;
		imageStore(chunk_tex, local, vec4(pix.r, pix.g, pix.b, packed));
	}
}
