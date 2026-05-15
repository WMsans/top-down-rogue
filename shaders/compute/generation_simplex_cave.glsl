#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant) uniform PushConstants {
    ivec2 chunk_coord;
    uint world_seed;
    uint gen_pass_idx;
} push_ctx;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rg32i, set = 0, binding = 1) uniform iimage2D jfa_a;
layout(rg32i, set = 0, binding = 2) uniform iimage2D jfa_b;

#include "res://shaders/generated/materials.glslinc"
#include "res://shaders/include/simplex_2d.glslinc"
#include "res://shaders/include/simplex_cave_utils.glslinc"
#include "res://shaders/include/stone_fill_stage.glslinc"
#include "res://shaders/include/simplex_cave_stage.glslinc"
#include "res://shaders/include/walkability_probe_stage.glslinc"

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    uint pass = push_ctx.gen_pass_idx;
    if (pass == 0u) {
        stage_stone_fill(ctx);
        stage_simplex_cave(ctx);
    } else if (pass == 1u) {
        stage_walkability_init(pos);
    } else if (pass >= 2u && pass <= 9u) {
        int stride = 1 << int(9u - pass);
        int read_idx = int(pass - 2u) % 2;
        stage_walkability_jump(pos, stride, read_idx);
    } else if (pass == 10u) {
        stage_walkability_finalize(pos, 0);
    }
}