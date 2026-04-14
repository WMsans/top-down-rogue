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

#include "res://shaders/include/sim/common.glslinc"
#include "res://shaders/include/sim/gas.glslinc"
#include "res://shaders/include/sim/lava.glslinc"
#include "res://shaders/include/sim/injection.glslinc"
#include "res://shaders/include/sim/burning.glslinc"

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

	vec4 pixel = imageLoad(chunk_tex, pos);
	int material = get_material(pixel);

	if (try_inject_rigidbody_velocity(pos, material, pixel)) return;

	vec4 n_up    = read_neighbor(pos + ivec2(0, -1));
	vec4 n_down  = read_neighbor(pos + ivec2(0,  1));
	vec4 n_left  = read_neighbor(pos + ivec2(-1, 0));
	vec4 n_right = read_neighbor(pos + ivec2( 1, 0));

	// Fluid dispatch — each simulate_* returns true if the cell is fully processed.
	// Add new fluids here in priority order (higher priority first).
	if (simulate_lava(pos, pixel, material, n_up, n_down, n_left, n_right)) return;
	if (simulate_gas(pos, pixel, material, n_up, n_down, n_left, n_right))  return;

	simulate_burning(pos, pixel, n_up, n_down, n_left, n_right);
}