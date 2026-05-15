#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform PushConstants {
    ivec2 chunk_coord;
    uint world_seed;
    uint padding;
} push_ctx;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rg32i, set = 0, binding = 1) uniform iimage2D jfa_a;
layout(rg32i, set = 0, binding = 2) uniform iimage2D jfa_b;
layout(std430, set = 0, binding = 3) buffer ChunkMaxRadius {
    int max_radius_packed;
    int pad0;
    int pad1;
    int pad2;
} chunk_max;

#include "res://shaders/generated/materials.glslinc"
#include "res://shaders/include/simplex_2d.glslinc"
#include "res://shaders/include/wood_fill_stage.glslinc"
#include "res://shaders/include/simplex_cave_utils.glslinc"
#include "res://shaders/include/biome_cave_stage.glslinc"
#include "res://shaders/include/biome_pools_stage.glslinc"
#include "res://shaders/include/pixel_scene_stamp.glslinc"
#include "res://shaders/include/secret_ring_stage.glslinc"

void main() {
    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    stage_wood_fill(ctx);
    stage_biome_cave(ctx);
    stage_biome_pools(ctx);
    stage_pixel_scene_stamp(ctx);
    stage_secret_ring(ctx);
}
