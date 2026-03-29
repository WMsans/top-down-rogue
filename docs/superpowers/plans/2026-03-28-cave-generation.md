# Cave Generation Stage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cave generation stage that carves caves, multi-chunk caves, and tunnels into the terrain using deterministic GPU compute shaders.

**Architecture:** Two new GLSL files (`cave_utils.glsl` for hash/noise/connector utilities, `cave_stage.glsl` for carving logic) included by the existing `generation.glsl`. Each pixel independently determines its chunk type and carves air accordingly. No CPU-side changes — only GLSL files are created/modified.

**Tech Stack:** GLSL 450 compute shaders, Godot 4.6 RenderingDevice API

---

### Task 1: Hash Utilities in cave_utils.glsl

**Files:**
- Create: `stages/cave_utils.glsl`

- [ ] **Step 1: Create `stages/cave_utils.glsl` with hash functions**

```glsl
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
```

- [ ] **Step 2: Commit**

```bash
git add stages/cave_utils.glsl
git commit -m "feat(cave): add hash utilities in cave_utils.glsl"
```

---

### Task 2: Value Noise

**Files:**
- Modify: `stages/cave_utils.glsl`

- [ ] **Step 1: Add 2D value noise function to `stages/cave_utils.glsl`**

Append after the hash functions:

```glsl
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
```

- [ ] **Step 2: Commit**

```bash
git add stages/cave_utils.glsl
git commit -m "feat(cave): add value noise and FBM to cave_utils"
```

---

### Task 3: Chunk Type Detection

**Files:**
- Modify: `stages/cave_utils.glsl`

- [ ] **Step 1: Add chunk type detection functions to `stages/cave_utils.glsl`**

Append after the noise functions:

```glsl
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
                // Non-mutual: neighbor claims me, I become secondary
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
```

- [ ] **Step 2: Commit**

```bash
git add stages/cave_utils.glsl
git commit -m "feat(cave): add chunk type detection with multi-cave conflict resolution"
```

---

### Task 4: Connector System

**Files:**
- Modify: `stages/cave_utils.glsl`

- [ ] **Step 1: Add connector structures and functions to `stages/cave_utils.glsl`**

Append after the chunk type detection:

```glsl
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
```

- [ ] **Step 2: Commit**

```bash
git add stages/cave_utils.glsl
git commit -m "feat(cave): add connector system with edge keys and collection"
```

---

### Task 5: Cave Carving in cave_stage.glsl

**Files:**
- Create: `stages/cave_stage.glsl`

- [ ] **Step 1: Create `stages/cave_stage.glsl` with cave carving**

```glsl
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
```

- [ ] **Step 2: Commit**

```bash
git add stages/cave_stage.glsl
git commit -m "feat(cave): add cave_stage.glsl with single-chunk cave carving"
```

---

### Task 6: Wire Cave Stage into Generation Pipeline

**Files:**
- Modify: `shaders/generation.glsl`

- [ ] **Step 1: Add cave stage include and call to `shaders/generation.glsl`**

Replace the entire file with:

```glsl
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
#include "res://stages/cave_stage.glsl"

void main() {
	Context ctx;
	ctx.chunk_coord = push_ctx.chunk_coord;
	ctx.world_seed = push_ctx.world_seed;

	stage_wood_fill(ctx);
	stage_cave(ctx);
}
```

- [ ] **Step 2: Visual test — open Godot editor, select WorldPreview node, set `world_seed` to any value, click "Generate Preview"**

Expected: chunks show a mix of solid wood and carved-out cave shapes. Cave chunks should have organic blobby air pockets. Non-cave chunks (tunnels, multi-caves) are still solid wood since those carving functions aren't wired yet.

- [ ] **Step 3: Commit**

```bash
git add shaders/generation.glsl
git commit -m "feat(cave): wire cave stage into generation pipeline"
```

---

### Task 7: Multi-Cave Carving

**Files:**
- Modify: `stages/cave_stage.glsl`

- [ ] **Step 1: Add multi-cave carving function to `stages/cave_stage.glsl`**

Add after `carve_cave` and before the stage entry point:

```glsl
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
```

- [ ] **Step 2: Update the stage entry point to handle multi-cave types**

Replace the `stage_cave` function:

```glsl
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
```

- [ ] **Step 3: Visual test — Generate Preview in editor**

Expected: some chunk pairs should show connected cave shapes spanning two chunks with no visible seam at the shared boundary. The shared edge should be fully open between primary/secondary.

- [ ] **Step 4: Commit**

```bash
git add stages/cave_stage.glsl
git commit -m "feat(cave): add multi-cave carving with seamless cross-chunk shapes"
```

---

### Task 8: Tunnel Carving

**Files:**
- Modify: `stages/cave_stage.glsl`

- [ ] **Step 1: Add tunnel carving function to `stages/cave_stage.glsl`**

Add after `carve_multi_cave` and before the stage entry point:

```glsl
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
```

- [ ] **Step 2: Update the stage entry point to handle tunnels**

Replace the `stage_cave` function:

```glsl
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
```

- [ ] **Step 3: Visual test — Generate Preview in editor with `preview_size = 3` or larger**

Expected: full cave system visible — organic cave rooms, large multi-chunk caves spanning pairs, and winding tunnels connecting them through shared connectors. Tunnels should visibly connect to cave openings at chunk boundaries.

- [ ] **Step 4: Commit**

```bash
git add stages/cave_stage.glsl
git commit -m "feat(cave): add tunnel carving with noise-displaced paths"
```

---

### Task 9: Tuning Pass and Visual Verification

**Files:**
- Modify: `stages/cave_stage.glsl` (constants only)
- Modify: `stages/cave_utils.glsl` (constants only)

- [ ] **Step 1: Generate Preview with multiple seeds and preview sizes**

Test with at least 3 different `world_seed` values and `preview_size = 4` (9x9 grid). Check for:
- Cave shapes look organic and varied
- Multi-chunk caves are seamless across boundaries
- Tunnels visibly connect to cave connector openings
- No chunks are completely empty when they should have content
- No chunks are completely solid when they should be carved
- Connector openings at chunk edges line up between adjacent chunks

- [ ] **Step 2: Adjust constants if needed**

The default constants are starting points. Common adjustments:
- `CAVE_THRESHOLD` — increase for smaller caves, decrease for larger
- `CAVE_NOISE_SCALE` — increase for more detailed/smaller features, decrease for smoother
- `TUNNEL_RADIUS` — increase for wider passages
- `TUNNEL_NOISE_AMP` — increase for more winding tunnels
- `EDGE_FADE_DIST` — increase to keep caves further from edges

- [ ] **Step 3: Commit any tuning changes**

```bash
git add stages/cave_stage.glsl stages/cave_utils.glsl
git commit -m "chore(cave): tune generation constants after visual testing"
```
