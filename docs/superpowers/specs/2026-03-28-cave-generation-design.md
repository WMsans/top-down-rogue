# Cave Generation Stage Design

## Overview

A GPU compute shader stage that carves caves, multi-chunk caves, and tunnels into the terrain. Runs after `wood_fill_stage` (or any future fill stage) and is purely subtractive — it only writes air pixels. Each chunk independently determines its type and carves accordingly, with no CPU-side coordination or multi-pass dispatches.

## Chunk Types

Each chunk is one of four types, determined by `hash(chunk_coord, world_seed)`:

| Type | Description |
|------|-------------|
| **Cave** | Single-chunk open cavity carved from noise. Exposes 0-2 connectors per edge. |
| **Multi-Primary** | First half of a 2-chunk cave. Claims one neighbor as its secondary. |
| **Multi-Secondary** | Second half of a 2-chunk cave. Detected by checking if any neighbor claims it. |
| **Tunnel** | Narrow passage connecting connectors from adjacent chunks. |

### Type Assignment Algorithm

```
determine_chunk_type(coord, seed):
    // Step 1: Am I claimed as a multi-cave secondary?
    for each neighbor in [left, right, up, down]:
        h = hash(neighbor_coord, seed)
        if h marks neighbor as MULTI_PRIMARY
           and neighbor's pair direction points at me:
            return MULTI_SECONDARY

    // Step 2: What does my own hash say?
    h = hash(coord, seed)
    type_roll = h % 100

    if type_roll < 15 → MULTI_PRIMARY
        pair_dir = hash(coord, seed + 1) % 4
        // Conflict: if paired neighbor is also a primary → lower coord wins, other becomes CAVE
    else if type_roll < 55 → CAVE
    else → TUNNEL
```

### Type Distribution

- ~15% Multi-Primary
- ~40% Cave
- ~45% Tunnel

Multi-Secondary is not a roll — it overrides whatever the chunk would have been when a neighbor claims it.

### Multi-Cave Conflict Resolution

If a primary's paired neighbor is also a primary, the chunk with the lower coordinate (compare x first, then y) keeps primary status. The other falls back to a regular CAVE.

## Connector System

### Shared Edge Key

Two adjacent chunks compute identical connectors for their shared edge using a canonical key:

```
edge_key(coordA, coordB, seed):
    lo = min(coordA, coordB)    // compare x first, then y
    hi = max(coordA, coordB)
    return hash(lo.x, lo.y, hi.x, hi.y, seed)
```

### Connector Properties

Each connector has:
- **position**: pixel offset along the edge, range [32, 223] (32px dead zone at corners)
- **width**: range [8, 23] pixels

### Connector Count

Per edge: 0, 1, or 2 connectors, determined by `hash(edge_key, 0) % 3`.

### Connector Generation

```
get_edge_connectors(coordA, coordB, seed):
    key = edge_key(coordA, coordB, seed)
    count = hash(key, 0) % 3    // 0, 1, or 2

    for i in 0..count:
        pos = hash(key, i+1) % 192 + 32      // [32, 223]
        width = hash(key, i+100) % 16 + 8    // [8, 23]
        // If 2 connectors overlap (positions within sum of half-widths), discard the second
```

### Who Uses Connectors

- **Cave**: Carves openings at connector positions on its edges. Cave noise shape is blended to meet the openings via a boost factor near connector positions.
- **Tunnel**: Reads connectors from all 4 edges. Pairs them deterministically (seed-based shuffle, then pair adjacent items) and carves noise-displaced paths between each pair. Unpaired connectors (odd count) get a short dead-end stub extending ~32px inward from the edge. If 0 connectors exist on all edges, the chunk is left solid (no carving).
- **Multi-Cave**: Shared edge between primary and secondary has no connectors — it's fully open. Outer edges use normal connector logic.

## Carving Algorithms

### Cave Carving (Single-Chunk)

```
carve_cave(pos, coord, seed):
    // Base cave shape from 2D value noise
    n = value_noise(pos * scale, coord, seed)

    // Fade toward edges — caves shrink near chunk borders
    edge_dist = min distance to any chunk edge
    fade = smoothstep(0, 48, edge_dist)

    // Boost near connectors — ensure openings reach the edge
    for each connector on this chunk's edges:
        d = distance(pos, connector_pos)
        fade = max(fade, smoothstep(24, 0, d))

    if n * fade > threshold → carve air
```

### Multi-Cave Carving

```
carve_multi_cave(pos, coord, seed):
    // Find the primary coord (might be self or neighbor)
    primary = get_primary_coord(coord, seed)
    pair_dir = get_pair_direction(primary, seed)

    // Convert pos to primary-relative coordinates
    // This gives a 256x512 or 512x256 noise space
    world_pos = coord * 256 + pos
    rel_pos = world_pos - primary * 256

    // Same noise, same origin → seamless across boundary
    n = value_noise(rel_pos * scale, primary, seed)

    // Edge fade on OUTER edges only
    // Shared edge between primary/secondary: no fade (fully open)
    if n * fade > threshold → carve air
```

### Tunnel Carving

```
carve_tunnel(pos, coord, seed):
    connectors = collect from all 4 edges
    pairs = pair_connectors(connectors, seed)

    for each (entry, exit) in pairs:
        // Parametric line from entry to exit
        t = closest_t(pos, entry, exit)
        base_pt = lerp(entry, exit, t)

        // Displace perpendicular with noise
        offset = value_noise(t * freq, seed) * amplitude
        curve_pt = base_pt + perpendicular * offset

        d = distance(pos, curve_pt)
        if d < tunnel_radius → carve air
```

## File Structure

### New Files

| File | Purpose |
|------|---------|
| `stages/cave_utils.glsl` | Shared utility functions: hash, value noise, chunk type detection, connector computation |
| `stages/cave_stage.glsl` | Cave stage entry point: determines chunk type and dispatches to appropriate carving function |

### Modified Files

| File | Change |
|------|--------|
| `shaders/generation.glsl` | Add `#include "res://stages/cave_stage.glsl"` and call `stage_cave(ctx)` after `stage_wood_fill(ctx)` |

### cave_utils.glsl Contents

- `hash_uint(uint)` — deterministic uint-to-uint hash
- `hash_uvec2(uvec2)` — 2D coordinate hash
- `hash_combine(uint, uint)` — combine two hash values
- `value_noise_2d(vec2, uint)` — 2D value noise from hash lattice
- `determine_chunk_type(ivec2, uint)` — coord + seed → chunk type enum
- `get_edge_connectors(ivec2, ivec2, uint)` — shared edge → connector array
- `pair_connectors(...)` — deterministic connector pairing for tunnels

### cave_stage.glsl Contents

- `stage_cave(Context ctx)` — entry point, branches on chunk type
- `carve_cave(ivec2, ivec2, uint)` — single-chunk cave noise carving
- `carve_multi_cave(ivec2, ivec2, uint)` — multi-chunk cave with shared origin
- `carve_tunnel(ivec2, ivec2, uint)` — noise-displaced tunnel paths

## Tunable Constants

| Constant | Default | Description |
|----------|---------|-------------|
| `CAVE_NOISE_SCALE` | 0.03 | Noise sampling frequency for cave shapes |
| `CAVE_THRESHOLD` | 0.45 | Noise cutoff for carving (higher = smaller caves) |
| `EDGE_FADE_DIST` | 48 | Pixels from edge where cave starts fading |
| `CONNECTOR_BOOST_RADIUS` | 24 | Radius around connectors where fade is overridden |
| `TUNNEL_RADIUS` | 10 | Half-width of tunnel passages |
| `TUNNEL_NOISE_FREQ` | 3.0 | Frequency of tunnel path displacement |
| `TUNNEL_NOISE_AMP` | 30.0 | Max perpendicular displacement of tunnel path |
| `CORNER_DEADZONE` | 32 | Pixels from corner where connectors cannot spawn |
| `CONNECTOR_MIN_WIDTH` | 8 | Minimum connector opening width |
| `CONNECTOR_MAX_WIDTH` | 23 | Maximum connector opening width |
| `TYPE_MULTI_THRESHOLD` | 15 | % chance of multi-primary |
| `TYPE_CAVE_THRESHOLD` | 55 | % cumulative chance of cave (minus multi) |

## Key Properties

- **Deterministic**: Every pixel computes independently from `(pos, coord, seed)`. No shared state, no synchronization.
- **Seamless**: Connectors use shared edge keys, multi-caves use shared noise origin. No visible seams at chunk boundaries.
- **Subtractive only**: Cave stage never writes material, only air. Composable with any prior fill stage.
- **Single-pass**: No extra GPU dispatches or intermediate buffers. Runs in the existing generation pipeline.
- **No CPU changes**: Only GLSL files are added/modified. WorldManager, push constants, and pipeline setup remain unchanged.
