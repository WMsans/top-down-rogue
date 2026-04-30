#[compute]
#version 450

const int TILE_SIZE = 64;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) readonly uniform image2D src_tile;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D dst_grid;

layout(push_constant, std430) uniform PushConstants {
	int dst_x;
	int dst_y;
	int _pad0;
	int _pad1;
} pc;

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	if (local.x >= TILE_SIZE || local.y >= TILE_SIZE) return;
	vec4 v = imageLoad(src_tile, local);
	imageStore(dst_grid, ivec2(pc.dst_x, pc.dst_y) + local, v);
}
