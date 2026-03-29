#include "res://stages/cave_utils.glsl"

// ----- Tunable Constants -----

const float CAVE_NOISE_SCALE = 0.03;
const float CAVE_THRESHOLD = 0.45;
const float EDGE_FADE_DIST = 48.0;
const float CONNECTOR_BOOST_RADIUS = 24.0;

// ----- Cave Carving (Single-Chunk) -----

void carve_cave(ivec2 pos, ivec2 coord, uint seed) {
    // Base cave shape from FBM noise
    vec2 noise_pos = (vec2(coord * CHUNK_SIZE) + vec2(pos)) * CAVE_NOISE_SCALE;
    float n = fbm_2d(noise_pos, hash_combine(seed, 100u));

    // Fade toward edges — caves shrink near chunk borders
    float dx = min(float(pos.x), float(CHUNK_SIZE - 1 - pos.x));
    float dy = min(float(pos.y), float(CHUNK_SIZE - 1 - pos.y));
    float edge_dist = min(dx, dy);
    float fade = smoothstep(0.0, EDGE_FADE_DIST, edge_dist);

    // Boost near connectors — ensure openings reach the edge
    ConnectorPoint points[8];
    int conn_count = collect_all_connectors(coord, seed, TYPE_CAVE, points);
    for (int i = 0; i < conn_count; i++) {
        float d = distance(vec2(pos), points[i].pos);
        fade = max(fade, smoothstep(CONNECTOR_BOOST_RADIUS, 0.0, d));
    }

    if (n * fade > CAVE_THRESHOLD) {
        // Carve air: material=0, health=0, temperature=0, reserved=0
        imageStore(chunk_tex, pos, vec4(0.0));
    }
}

// ----- Stage Entry Point (cave only for now) -----

void stage_cave(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

    int chunk_type = determine_chunk_type(ctx.chunk_coord, ctx.world_seed);

    if (chunk_type == TYPE_CAVE) {
        carve_cave(pos, ctx.chunk_coord, ctx.world_seed);
    }
    // Multi-cave and tunnel carving added in subsequent tasks
}
