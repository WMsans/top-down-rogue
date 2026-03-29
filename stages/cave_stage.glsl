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

// ----- Tunnel Carving -----

const float TUNNEL_RADIUS = 10.0;
const float TUNNEL_NOISE_FREQ = 3.0;
const float TUNNEL_NOISE_AMP = 30.0;
const float TUNNEL_STUB_LENGTH = 32.0;

// Find closest point on line segment A->B, return parametric t clamped to [0,1]
float closest_t_on_segment(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float len_sq = dot(ab, ab);
    if (len_sq < 0.001) return 0.0;
    return clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
}

// Carve a single tunnel path between two connector points
void carve_tunnel_path(ivec2 pos, vec2 entry, vec2 exit, uint path_seed) {
    vec2 p = vec2(pos);
    vec2 ab = exit - entry;
    float t = closest_t_on_segment(p, entry, exit);

    // Base point on the straight line
    vec2 base_pt = entry + ab * t;

    // Perpendicular direction
    vec2 perp = normalize(vec2(-ab.y, ab.x));

    // Noise displacement: varies along t, zero at endpoints for clean connections
    float noise_val = value_noise_2d(vec2(t * TUNNEL_NOISE_FREQ, 0.0), path_seed);
    float endpoint_fade = sin(t * 3.14159265);  // 0 at t=0 and t=1
    float offset = (noise_val - 0.5) * 2.0 * TUNNEL_NOISE_AMP * endpoint_fade;

    vec2 curve_pt = base_pt + perp * offset;

    float d = distance(p, curve_pt);
    if (d < TUNNEL_RADIUS) {
        imageStore(chunk_tex, pos, vec4(0.0));
    }
}

// Carve a dead-end stub extending inward from an unpaired connector
void carve_tunnel_stub(ivec2 pos, vec2 connector_pos, uint stub_seed) {
    // Determine inward direction based on which edge the connector is on
    vec2 inward;
    if (connector_pos.x < 1.0) {
        inward = vec2(1.0, 0.0);
    } else if (connector_pos.x > float(CHUNK_SIZE - 2)) {
        inward = vec2(-1.0, 0.0);
    } else if (connector_pos.y < 1.0) {
        inward = vec2(0.0, 1.0);
    } else {
        inward = vec2(0.0, -1.0);
    }

    vec2 stub_end = connector_pos + inward * TUNNEL_STUB_LENGTH;
    carve_tunnel_path(pos, connector_pos, stub_end, stub_seed);
}

void carve_tunnel(ivec2 pos, ivec2 coord, uint seed) {
    ConnectorPoint points[8];
    int count = collect_all_connectors(coord, seed, TYPE_TUNNEL, points);

    if (count == 0) {
        // No connectors — leave solid
        return;
    }

    // Deterministic pairing: use seed-based pseudo-shuffle then pair adjacent
    // Simple approach: sort by hash value, then pair [0,1], [2,3], etc.
    // We implement a minimal insertion sort on indices by hash value
    int indices[8];
    uint sort_keys[8];
    for (int i = 0; i < count; i++) {
        indices[i] = i;
        sort_keys[i] = hash_combine(seed, uint(i) + 500u);
    }
    // Insertion sort (max 8 elements)
    for (int i = 1; i < count; i++) {
        int j = i;
        while (j > 0 && sort_keys[indices[j - 1]] > sort_keys[indices[j]]) {
            int tmp = indices[j];
            indices[j] = indices[j - 1];
            indices[j - 1] = tmp;
            j--;
        }
    }

    // Pair adjacent sorted connectors and carve paths
    int pair_count = count / 2;
    for (int i = 0; i < pair_count; i++) {
        int a = indices[i * 2];
        int b = indices[i * 2 + 1];
        uint path_seed = hash_combine(seed, uint(i) + 600u);
        carve_tunnel_path(pos, points[a].pos, points[b].pos, path_seed);
    }

    // If odd count, last connector gets a dead-end stub
    if (count % 2 == 1) {
        int last = indices[count - 1];
        carve_tunnel_stub(pos, points[last].pos, hash_combine(seed, 700u));
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
    } else if (chunk_type == TYPE_TUNNEL) {
        carve_tunnel(pos, ctx.chunk_coord, ctx.world_seed);
    }
}
