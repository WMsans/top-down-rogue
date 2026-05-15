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
#include "res://shaders/include/walkability_probe_stage.glslinc"
#include "res://shaders/include/walkability_enforce_stage.glslinc"

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    uint pass = push_ctx.gen_pass_idx;
    if (pass == 0u) {
        stage_wood_fill(ctx);
        stage_biome_cave(ctx);
        stage_biome_pools(ctx);
        stage_pixel_scene_stamp(ctx);
        stage_secret_ring(ctx);
    } else if (pass == 1u) {
        stage_walkability_init(pos);
    } else if (pass >= 2u && pass <= 9u) {
        int stride = 1 << int(9u - pass);
        int read_idx = int(pass - 2u) % 2;
        stage_walkability_jump(pos, stride, read_idx);
    } else if (pass == 10u) {
        stage_clear_chunk_max(pos);
    } else if (pass == 11u) {
        stage_walkability_finalize(pos, 0);
    } else if (pass == 12u) {
        stage_walkability_strip_pools(pos);
    } else if (pass == 13u) {
        stage_clear_chunk_max(pos);
    } else if (pass == 14u) {
        stage_walkability_init(pos);
    } else if (pass >= 15u && pass <= 22u) {
        int stride = 1 << int(22u - pass);
        int read_idx = int(pass - 15u) % 2;
        stage_walkability_jump(pos, stride, read_idx);
    } else if (pass == 23u) {
        stage_clear_chunk_max(pos);
    } else if (pass == 24u) {
        stage_walkability_finalize(pos, 0);
    } else if (pass >= 25u) {
        uint iter_pass = pass - 25u;
        uint iter_kind = iter_pass % 12u;
        if (iter_kind == 0u) {
            stage_walkability_dilate(pos);
        } else if (iter_kind == 1u) {
            stage_clear_chunk_max(pos);
        } else if (iter_kind == 2u) {
            stage_walkability_init(pos);
        } else if (iter_kind >= 3u && iter_kind <= 10u) {
            int stride = 1 << int(10u - iter_kind);
            int read_idx = int(iter_kind - 3u) % 2;
            stage_walkability_jump(pos, stride, read_idx);
        } else if (iter_kind == 11u) {
            stage_walkability_finalize(pos, 0);
        }
    } else if (pass == 385u) {
        vec4 cur = imageLoad(chunk_tex, pos);
        cur.a = 0.0;
        imageStore(chunk_tex, pos, cur);
    }
}
