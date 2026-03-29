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

// ----- Multi-Cave Carving -----

void carve_multi_cave(ivec2 pos, ivec2 coord, uint seed) {
    // Find the primary coord
    ivec2 primary;
    int chunk_type = determine_chunk_type(coord, seed);
    if (chunk_type == TYPE_MULTI_PRIMARY) {
        primary = coord;
    } else {
        primary = get_primary_coord(coord, seed);
    }

    int pair_dir = get_shared_edge_dir(primary, seed);

    // Convert pixel pos to primary-relative coordinates
    // This creates a 256x512 or 512x256 noise space
    vec2 world_pos = vec2(coord * CHUNK_SIZE) + vec2(pos);
    vec2 origin = vec2(primary * CHUNK_SIZE);
    vec2 rel_pos = world_pos - origin;

    // Noise using primary coord as seed basis for seamless result
    float n = fbm_2d(rel_pos * CAVE_NOISE_SCALE, hash_combine(seed, 200u));

    // Edge fade on OUTER edges only. Shared edge has no fade.
    float dx_min = float(pos.x);
    float dx_max = float(CHUNK_SIZE - 1 - pos.x);
    float dy_min = float(pos.y);
    float dy_max = float(CHUNK_SIZE - 1 - pos.y);

    // Determine which edges are outer (not the shared edge)
    // From this chunk's perspective, the shared edge direction:
    int my_shared_dir;
    if (chunk_type == TYPE_MULTI_PRIMARY) {
        my_shared_dir = pair_dir;
    } else {
        my_shared_dir = DIR_OPPOSITE[pair_dir];
    }

    // Start with all edge distances
    float edge_dist = min(min(dx_min, dx_max), min(dy_min, dy_max));

    // Remove shared edge from fade calculation by setting its distance high
    if (my_shared_dir == DIR_LEFT) {
        edge_dist = min(min(dx_max, dy_min), dy_max);
    } else if (my_shared_dir == DIR_RIGHT) {
        edge_dist = min(min(dx_min, dy_min), dy_max);
    } else if (my_shared_dir == DIR_UP) {
        edge_dist = min(min(dx_min, dx_max), dy_max);
    } else {  // DIR_DOWN
        edge_dist = min(min(dx_min, dx_max), dy_min);
    }

    float fade = smoothstep(0.0, EDGE_FADE_DIST, edge_dist);

    // Boost near connectors on outer edges
    ConnectorPoint points[8];
    int conn_count = collect_all_connectors(coord, seed, chunk_type, points);
    for (int i = 0; i < conn_count; i++) {
        float d = distance(vec2(pos), points[i].pos);
        fade = max(fade, smoothstep(CONNECTOR_BOOST_RADIUS, 0.0, d));
    }

    if (n * fade > CAVE_THRESHOLD) {
        imageStore(chunk_tex, pos, vec4(0.0));
    }
}

// ----- Stage Entry Point -----

void stage_cave(Context ctx) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= CHUNK_SIZE || pos.y >= CHUNK_SIZE) return;

    int chunk_type = determine_chunk_type(ctx.chunk_coord, ctx.world_seed);

    if (chunk_type == TYPE_CAVE) {
        carve_cave(pos, ctx.chunk_coord, ctx.world_seed);
    } else if (chunk_type == TYPE_MULTI_PRIMARY || chunk_type == TYPE_MULTI_SECONDARY) {
        carve_multi_cave(pos, ctx.chunk_coord, ctx.world_seed);
    }
    // Tunnel carving added in next task
}
