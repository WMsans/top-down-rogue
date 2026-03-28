#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform PushConstants {
	ivec2 chunk_coord;
	uint world_seed;
	uint padding;
} push_ctx;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

#include "res://stages/wood_fill_stage.glsl"

void main() {
	Context ctx;
	ctx.chunk_coord = push_ctx.chunk_coord;
	ctx.world_seed = push_ctx.world_seed;

	stage_wood_fill(ctx);
}
