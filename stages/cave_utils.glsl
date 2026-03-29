// ----- Hash utilities -----

const int CHUNK_SIZE = 256;

const int TYPE_CAVE = 0;
const int TYPE_MULTI_PRIMARY = 1;
const int TYPE_MULTI_SECONDARY = 2;
const int TYPE_TUNNEL = 3;

// Direction constants: 0=left, 1=right, 2=up, 3=down
const int DIR_LEFT = 0;
const int DIR_RIGHT = 1;
const int DIR_UP = 2;
const int DIR_DOWN = 3;

const ivec2 DIR_OFFSETS[4] = ivec2[4](
    ivec2(-1, 0),  // left
    ivec2(1, 0),   // right
    ivec2(0, -1),  // up
    ivec2(0, 1)    // down
);

// Opposite direction lookup: left<->right, up<->down
const int DIR_OPPOSITE[4] = int[4](1, 0, 3, 2);

uint hash_uint(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

uint hash_combine(uint a, uint b) {
    return hash_uint(a ^ (b * 0x9e3779b9u + 0x9e3779b9u + (a << 6u) + (a >> 2u)));
}

uint hash_ivec2(ivec2 v, uint seed) {
    uint hx = hash_uint(uint(v.x) + 0x10000u);
    uint hy = hash_uint(uint(v.y) + 0x10000u);
    return hash_combine(hash_combine(hx, hy), seed);
}

// Hash 4 ints + seed into a single uint
uint hash_edge(int a, int b, int c, int d, uint seed) {
    uint h = hash_uint(uint(a) + 0x10000u);
    h = hash_combine(h, uint(b) + 0x10000u);
    h = hash_combine(h, uint(c) + 0x10000u);
    h = hash_combine(h, uint(d) + 0x10000u);
    return hash_combine(h, seed);
}

// Returns a float in [0, 1] from a hash
float hash_to_float(uint h) {
    return float(h & 0xFFFFu) / 65535.0;
}

// ----- 2D Value Noise -----

// Lattice-based value noise: hash at integer corners, bilinear interpolate
float value_noise_2d(vec2 p, uint seed) {
    ivec2 i = ivec2(floor(p));
    vec2 f = fract(p);

    // Smoothstep interpolation (Hermite)
    vec2 u = f * f * (3.0 - 2.0 * f);

    float c00 = hash_to_float(hash_combine(hash_ivec2(i, seed), 0u));
    float c10 = hash_to_float(hash_combine(hash_ivec2(i + ivec2(1, 0), seed), 0u));
    float c01 = hash_to_float(hash_combine(hash_ivec2(i + ivec2(0, 1), seed), 0u));
    float c11 = hash_to_float(hash_combine(hash_ivec2(i + ivec2(1, 1), seed), 0u));

    return mix(mix(c00, c10, u.x), mix(c01, c11, u.x), u.y);
}

// Fractal Brownian Motion — 3 octaves for organic shapes
float fbm_2d(vec2 p, uint seed) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 3; i++) {
        value += amplitude * value_noise_2d(p * frequency, hash_combine(seed, uint(i)));
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// ----- Chunk Type Detection -----

const uint TYPE_MULTI_THRESHOLD = 15u;
const uint TYPE_CAVE_THRESHOLD = 55u;

// Returns the raw type roll for a coordinate (before secondary override)
int _raw_chunk_type(ivec2 coord, uint seed) {
    uint h = hash_ivec2(coord, seed);
    uint type_roll = h % 100u;
    if (type_roll < TYPE_MULTI_THRESHOLD) {
        return TYPE_MULTI_PRIMARY;
    } else if (type_roll < TYPE_CAVE_THRESHOLD) {
        return TYPE_CAVE;
    } else {
        return TYPE_TUNNEL;
    }
}

// Returns which direction a multi-primary pairs toward (0-3)
int get_pair_direction(ivec2 coord, uint seed) {
    return int(hash_ivec2(coord, seed + 1u) % 4u);
}

// Returns the paired neighbor coord for a multi-primary
ivec2 get_pair_neighbor(ivec2 primary_coord, uint seed) {
    int dir = get_pair_direction(primary_coord, seed);
    return primary_coord + DIR_OFFSETS[dir];
}

// Check if coord_a < coord_b lexicographically (x first, then y)
bool coord_less_than(ivec2 a, ivec2 b) {
    return (a.x < b.x) || (a.x == b.x && a.y < b.y);
}

// Full chunk type determination including secondary override and conflict resolution
int determine_chunk_type(ivec2 coord, uint seed) {
    // Step 1: Check if any neighbor claims me as its secondary
    for (int d = 0; d < 4; d++) {
        ivec2 neighbor = coord + DIR_OFFSETS[d];
        int neighbor_raw = _raw_chunk_type(neighbor, seed);
        if (neighbor_raw == TYPE_MULTI_PRIMARY) {
            int neighbor_pair_dir = get_pair_direction(neighbor, seed);
            ivec2 neighbor_target = neighbor + DIR_OFFSETS[neighbor_pair_dir];
            if (neighbor_target == coord) {
                // Neighbor wants to claim me. But check conflict:
                // If I'm also a primary trying to claim them, lower coord wins primary.
                int my_raw = _raw_chunk_type(coord, seed);
                if (my_raw == TYPE_MULTI_PRIMARY) {
                    ivec2 my_target = get_pair_neighbor(coord, seed);
                    if (my_target == neighbor) {
                        // Mutual claim — lower coord wins primary
                        if (coord_less_than(coord, neighbor)) {
                            return TYPE_MULTI_PRIMARY;  // I win primary
                        } else {
                            return TYPE_MULTI_SECONDARY;  // They win, I'm secondary
                        }
                    }
                }
                // Non-mutual: neighbor claims me. But verify the neighbor
                // won't be demoted to CAVE (happens when its target — me — is
                // also a raw primary pointing elsewhere).
                int my_raw2 = _raw_chunk_type(coord, seed);
                if (my_raw2 == TYPE_MULTI_PRIMARY) {
                    // I'm a raw primary not pointing at neighbor — neighbor
                    // will be demoted to CAVE in its own Step 2, so skip.
                    continue;
                }
                return TYPE_MULTI_SECONDARY;
            }
        }
    }

    // Step 2: My own roll
    int my_raw = _raw_chunk_type(coord, seed);

    // If I'm a primary, check if my target is also a primary with a conflict
    if (my_raw == TYPE_MULTI_PRIMARY) {
        ivec2 my_target = get_pair_neighbor(coord, seed);
        int target_raw = _raw_chunk_type(my_target, seed);
        if (target_raw == TYPE_MULTI_PRIMARY) {
            // My target is also a primary — do they point at me?
            ivec2 target_target = get_pair_neighbor(my_target, seed);
            if (target_target == coord) {
                // Mutual — lower coord keeps primary (handled above for secondary)
                if (coord_less_than(coord, my_target)) {
                    return TYPE_MULTI_PRIMARY;
                } else {
                    return TYPE_MULTI_SECONDARY;
                }
            }
            // Non-mutual: both are primaries pointing elsewhere. I stay primary,
            // but my target won't become my secondary (they're their own primary).
            // Fall back to CAVE since pairing fails.
            return TYPE_CAVE;
        }
    }

    return my_raw;
}

// For a secondary chunk, find which neighbor is its primary
ivec2 get_primary_coord(ivec2 coord, uint seed) {
    for (int d = 0; d < 4; d++) {
        ivec2 neighbor = coord + DIR_OFFSETS[d];
        int neighbor_raw = _raw_chunk_type(neighbor, seed);
        if (neighbor_raw == TYPE_MULTI_PRIMARY) {
            int neighbor_pair_dir = get_pair_direction(neighbor, seed);
            ivec2 neighbor_target = neighbor + DIR_OFFSETS[neighbor_pair_dir];
            if (neighbor_target == coord) {
                return neighbor;
            }
        }
    }
    // Shouldn't reach here for a valid secondary
    return coord;
}

// Returns the direction from primary to secondary
int get_shared_edge_dir(ivec2 primary_coord, uint seed) {
    return get_pair_direction(primary_coord, seed);
}

// ----- Connector System -----

const int CORNER_DEADZONE = 32;
const int CONNECTOR_MIN_WIDTH = 8;
const int CONNECTOR_MAX_WIDTH = 23;
const int CONNECTOR_RANGE = CHUNK_SIZE - 2 * CORNER_DEADZONE;  // 192
const int MAX_CONNECTORS_PER_EDGE = 2;

struct Connector {
    int pos;    // pixel offset along the edge [32, 223]
    int width;  // opening width [8, 23]
};

// Canonical edge key: always order by lower coord first
uint edge_key(ivec2 coordA, ivec2 coordB, uint seed) {
    ivec2 lo, hi;
    if (coord_less_than(coordA, coordB)) {
        lo = coordA;
        hi = coordB;
    } else {
        lo = coordB;
        hi = coordA;
    }
    return hash_edge(lo.x, lo.y, hi.x, hi.y, seed);
}

// Get connectors for a shared edge between two chunks.
// Returns count (0-2), fills connectors array.
int get_edge_connectors(ivec2 coordA, ivec2 coordB, uint seed, out Connector connectors[2]) {
    uint key = edge_key(coordA, coordB, seed);
    int count = int(hash_combine(key, 0u) % 3u);  // 0, 1, or 2

    for (int i = 0; i < count; i++) {
        int pos = int(hash_combine(key, uint(i + 1)) % uint(CONNECTOR_RANGE)) + CORNER_DEADZONE;
        int w = int(hash_combine(key, uint(i + 100)) % uint(CONNECTOR_MAX_WIDTH - CONNECTOR_MIN_WIDTH + 1)) + CONNECTOR_MIN_WIDTH;
        connectors[i] = Connector(pos, w);
    }

    // If 2 connectors overlap, discard the second
    if (count == 2) {
        int half_a = connectors[0].width / 2;
        int half_b = connectors[1].width / 2;
        if (abs(connectors[0].pos - connectors[1].pos) < half_a + half_b) {
            count = 1;
        }
    }

    return count;
}

// Collect all connectors for a chunk across all 4 edges.
// edge_pos stores connectors as 2D positions within the chunk.
// Returns total count. Max 8 connectors (2 per edge).
struct ConnectorPoint {
    vec2 pos;  // 2D position within the chunk
};

int collect_all_connectors(ivec2 coord, uint seed, int chunk_type, out ConnectorPoint points[8]) {
    int total = 0;

    // For multi-caves, skip the shared edge
    int shared_dir = -1;
    if (chunk_type == TYPE_MULTI_PRIMARY) {
        shared_dir = get_shared_edge_dir(coord, seed);
    } else if (chunk_type == TYPE_MULTI_SECONDARY) {
        ivec2 primary = get_primary_coord(coord, seed);
        // Shared edge dir from my perspective is opposite of primary's pair dir
        int primary_dir = get_shared_edge_dir(primary, seed);
        shared_dir = DIR_OPPOSITE[primary_dir];
    }

    for (int d = 0; d < 4; d++) {
        if (d == shared_dir) continue;  // Skip shared edge for multi-caves

        ivec2 neighbor = coord + DIR_OFFSETS[d];
        Connector conns[2];
        int count = get_edge_connectors(coord, neighbor, seed, conns);

        for (int i = 0; i < count; i++) {
            vec2 p;
            if (d == DIR_LEFT) {
                p = vec2(0.0, float(conns[i].pos));
            } else if (d == DIR_RIGHT) {
                p = vec2(float(CHUNK_SIZE - 1), float(conns[i].pos));
            } else if (d == DIR_UP) {
                p = vec2(float(conns[i].pos), 0.0);
            } else {  // DIR_DOWN
                p = vec2(float(conns[i].pos), float(CHUNK_SIZE - 1));
            }
            if (total < 8) {
                points[total] = ConnectorPoint(p);
                total++;
            }
        }
    }

    return total;
}
