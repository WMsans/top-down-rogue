# Part 1: Walkable Space — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guarantee every cave-type chunk contains a contiguous open pocket of ≥150×150 px reachable through ≥24-px openings, regardless of seed or biome.

**Architecture:** Two new GPU compute stages appended to the chunk generation pipeline — `stage_walkability_probe` (JFA distance transform writing per-cell inscribed-disk radius into the chunk's alpha scratch channel) and `stage_walkability_enforce` (strip pool deposits, then dilate, until largest pocket reaches 75-px inscribed radius). Tunnel chunks become rarer (chunk-type threshold 55→85) and the inter-chunk tunnel carving widens (radius 10→14). Biomes get a `cave_threshold` clamp.

**Tech Stack:** Godot 4, GDExtension (C++), GLSL compute shaders, GdUnit4.

---

## File Structure

**New:**
- `shaders/include/walkability_probe_stage.glslinc` — JFA distance transform
- `shaders/include/walkability_enforce_stage.glslinc` — strip pools + dilate
- `tests/unit/test_walkability_invariant.gd` — invariant + connectivity tests

**Modified:**
- `shaders/compute/generation.glsl`, `shaders/compute/generation_simplex_cave.glsl` — wire new stages
- `shaders/include/cave_utils.glslinc` — `TYPE_CAVE_THRESHOLD: 55u → 85u`
- `shaders/include/cave_stage.glslinc` — `TUNNEL_RADIUS: 10.0 → 14.0`
- `shaders/include/biome_pools_stage.glslinc` — tag pool-deposited cells in alpha bit 7
- `shaders/include/simplex_cave_stage.glslinc` — same pool-tagging concept if it deposits pools
- `assets/biomes/*.tres` — clamp `cave_threshold ≤ 0.42`
- `gdextension/src/compute_device.*` (or equivalent) — no functional change, but verify alpha-channel is preserved across stage dispatches

**Conventions used:**
- Alpha channel of `chunk_tex` is the scratch channel during gen. Bits 0–6 = inscribed-disk radius (0–127), bit 7 = pool-origin flag. **Must be reset to 0 before gen finishes** (last sub-stage clears the alpha).
- Probe writes "Chebyshev distance to nearest solid cell" since that's what a 150×150 square pocket's inscribed-square-radius corresponds to (Chebyshev radius 75).
- Probe runs JFA in 8 passes of stride `128, 64, 32, 16, 8, 4, 2, 1`.

---

## Task 1: Tag pool-deposited cells with alpha bit 7

**Files:**
- Modify: `shaders/include/biome_pools_stage.glslinc`

Pool deposits need to be identifiable later so `stage_walkability_enforce` can strip them selectively. Bit 7 of the alpha channel marks "this cell's current material came from `stage_biome_pools`."

- [ ] **Step 1: Modify the pool-deposit write to set alpha bit 7.**

Replace the `imageStore` in `biome_pools_stage.glslinc`:

```glsl
// OLD:
// imageStore(chunk_tex, pos, vec4(float(pool_mat) / 255.0, 0.0, 0.0, 0.0));

// NEW (sets bit 7 of alpha = pool-origin tag; lower bits stay 0):
imageStore(chunk_tex, pos, vec4(float(pool_mat) / 255.0, 0.0, 0.0, 128.0 / 255.0));
return;
```

- [ ] **Step 2: Hand-test in editor** — generate a level, save a chunk render, confirm visuals look unchanged. The alpha bit doesn't affect the existing rendering (which reads only the RGB channels for material/health/temperature display).

- [ ] **Step 3: Commit.**

```bash
git add shaders/include/biome_pools_stage.glslinc
git commit -m "feat(gen): tag pool-deposited cells with alpha bit 7"
```

---

## Task 2: Add JFA distance transform stage scaffold

**Files:**
- Create: `shaders/include/walkability_probe_stage.glslinc`

The probe writes Chebyshev distance to the nearest solid cell into alpha bits 0–6 (clamped to 127). Uses Jump-Flood Algorithm — 8 passes of decreasing stride. Each cell stores the coords of the nearest solid seed it's found so far in two adjacent scratch buffers; after 8 passes, distance = Chebyshev distance from cell to its stored seed.

**Design:** Since we only have the `chunk_tex` available, and reusing alpha for the seed-coordinate during the 8 passes would clobber other data, we allocate a separate JFA scratch buffer. Two passes (ping-pong) of an `ivec2` per cell = 256×256×8 bytes = 512 KB per chunk × ~25 chunks = 12.5 MB GPU. Acceptable.

Allocate ping-pong scratch in `compute_device` (GDExtension), pass as additional bindings.

- [ ] **Step 1: Create the include file with a stub probe and the seed-pack helpers.** This is a skeleton; we'll fill in the JFA logic over the next two tasks.

```glsl
// shaders/include/walkability_probe_stage.glslinc
//
// Jump-Flood Algorithm distance transform.
//
// For each air cell, computes the Chebyshev distance to the nearest solid cell
// and stores it (clamped to 127) into alpha bits 0-6 of chunk_tex.
//
// Uses an ivec2 ping-pong scratch buffer (jfa_a, jfa_b) — at each cell stores
// the world-space (chunk-local) coords of the nearest solid seed found so far,
// or ivec2(-1, -1) for "unknown."

// Bindings (added in gen shader): jfa_a, jfa_b as image2D rg32i.
// Pass index 0 = solid-init; passes 1..8 = JFA strides 128, 64, 32, 16, 8, 4, 2, 1;
// pass 9 = finalize (write distance to alpha 0..6).

void stage_walkability_init(ivec2 pos) {
    vec4 current = imageLoad(chunk_tex, pos);
    int mat_id = int(round(current.r * 255.0));
    if (mat_id != MAT_AIR) {
        imageStore(jfa_a, pos, ivec4(pos, 0, 0));
    } else {
        imageStore(jfa_a, pos, ivec4(-1, -1, 0, 0));
    }
}

void stage_walkability_jump(ivec2 pos, int stride, int read_idx) {
    // Read 9 candidates (self + 8 neighbors at +/-stride) from read buffer,
    // pick the one nearest to `pos` (Chebyshev), write to write buffer.
    ivec2 best = ivec2(-1, -1);
    int best_dist = 1 << 30;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 sample_pos = pos + ivec2(dx, dy) * stride;
            if (sample_pos.x < 0 || sample_pos.x >= 256 || sample_pos.y < 0 || sample_pos.y >= 256) continue;
            ivec2 seed;
            if (read_idx == 0) {
                seed = imageLoad(jfa_a, sample_pos).xy;
            } else {
                seed = imageLoad(jfa_b, sample_pos).xy;
            }
            if (seed.x < 0) continue;
            int dist = max(abs(seed.x - pos.x), abs(seed.y - pos.y));
            if (dist < best_dist) {
                best_dist = dist;
                best = seed;
            }
        }
    }
    if (read_idx == 0) {
        imageStore(jfa_b, pos, ivec4(best, 0, 0));
    } else {
        imageStore(jfa_a, pos, ivec4(best, 0, 0));
    }
}

void stage_walkability_finalize(ivec2 pos, int final_buf_idx) {
    ivec2 seed;
    if (final_buf_idx == 0) {
        seed = imageLoad(jfa_a, pos).xy;
    } else {
        seed = imageLoad(jfa_b, pos).xy;
    }
    int dist = 0;
    if (seed.x >= 0) {
        dist = clamp(max(abs(seed.x - pos.x), abs(seed.y - pos.y)), 0, 127);
    }
    // Write dist into alpha bits 0-6, preserve bit 7 (pool-origin).
    vec4 cur = imageLoad(chunk_tex, pos);
    int alpha_byte = int(round(cur.a * 255.0));
    int new_alpha = (alpha_byte & 0x80) | (dist & 0x7F);
    cur.a = float(new_alpha) / 255.0;
    imageStore(chunk_tex, pos, cur);
}
```

- [ ] **Step 2: Commit the skeleton.** No call site yet; this is just defining the functions.

```bash
git add shaders/include/walkability_probe_stage.glslinc
git commit -m "feat(gen): scaffold JFA distance transform stage"
```

---

## Task 3: Allocate JFA ping-pong scratch buffers in compute device

**Files:**
- Modify: `gdextension/src/compute_device.cpp` (or `.gd` equivalent — check existing pattern for `chunk_tex` allocation)

Two new RG32I storage textures per chunk: `jfa_a` and `jfa_b`. Bound as image2D at set 0 bindings 1 and 2 (or whichever next available slot).

- [ ] **Step 1: Locate existing chunk_tex allocation.** Run:

```bash
grep -rn "chunk_tex\|create_texture_for_chunk\|TextureFormat" gdextension/src/ src/core/
```

- [ ] **Step 2: Add jfa_a, jfa_b allocations parallel to chunk_tex.** Format: `RD::DATA_FORMAT_R32G32_SINT`, same dimensions (256×256). Add to the chunk's resource bundle and to the uniform set passed to gen dispatch.

Pattern (adapt to actual struct layout in the codebase):

```cpp
// In chunk init:
chunk.jfa_a = create_storage_texture(256, 256, RD::DATA_FORMAT_R32G32_SINT);
chunk.jfa_b = create_storage_texture(256, 256, RD::DATA_FORMAT_R32G32_SINT);

// In gen-dispatch uniform-set build:
add_image_binding(uniform_set, /*binding=*/1, chunk.jfa_a);
add_image_binding(uniform_set, /*binding=*/2, chunk.jfa_b);

// In chunk free:
free_rid(chunk.jfa_a);
free_rid(chunk.jfa_b);
```

- [ ] **Step 3: Update gen shader bindings** in both `generation.glsl` and `generation_simplex_cave.glsl`:

```glsl
layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;
layout(rg32i, set = 0, binding = 1) uniform iimage2D jfa_a;
layout(rg32i, set = 0, binding = 2) uniform iimage2D jfa_b;
```

- [ ] **Step 4: Rebuild GDExtension, launch game, verify no errors.** Walk around generating a few chunks. The buffers should be allocated and bound but unused so far.

```bash
cd gdextension && ./build.sh   # or whatever the build invocation is
```

- [ ] **Step 5: Commit.**

```bash
git add -A gdextension/ shaders/compute/generation.glsl shaders/compute/generation_simplex_cave.glsl
git commit -m "feat(gen): allocate JFA ping-pong scratch buffers per chunk"
```

---

## Task 4: Wire walkability_probe into gen pipeline

**Files:**
- Modify: `shaders/compute/generation.glsl`, `shaders/compute/generation_simplex_cave.glsl`

Insert calls to `stage_walkability_init`, then 8 jumps of decreasing stride, then `stage_walkability_finalize`. The JFA passes need barriers between them — since each gen.glsl invocation today does the whole chunk in a single dispatch, we need to either (a) split gen into multiple dispatches with barriers between JFA passes, or (b) use `memoryBarrierImage()` between passes within a single dispatch.

Option (a) is the standard JFA approach but requires reworking how gen is dispatched. Option (b) only works if we can keep all 256×256 cells synchronized — which we can't across workgroups in a single compute dispatch.

**Decision: split into multiple dispatches.** Add a new `gen_pass_idx` push constant; dispatch the gen compute pipeline 11 times per chunk (1 base, 1 init, 8 jumps, 1 finalize). Compute device's `dispatch_generation` becomes a loop.

- [ ] **Step 1: Add `gen_pass_idx` to push constants** in both gen shaders:

```glsl
layout(push_constant) uniform PushConstants {
    ivec2 chunk_coord;
    uint world_seed;
    uint gen_pass_idx;  // 0=base, 1=init, 2..9=jumps stride 128..1, 10=finalize
} push_ctx;
```

- [ ] **Step 2: Update `main()` in `generation_simplex_cave.glsl`** to branch on `gen_pass_idx`:

```glsl
#include "res://shaders/include/walkability_probe_stage.glslinc"

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    Context ctx;
    ctx.chunk_coord = push_ctx.chunk_coord;
    ctx.world_seed = push_ctx.world_seed;

    uint pass = push_ctx.gen_pass_idx;
    if (pass == 0) {
        stage_stone_fill(ctx);
        stage_simplex_cave(ctx);
        // (pools / stamps / secret_ring inserted here when those branches are integrated)
    } else if (pass == 1) {
        stage_walkability_init(pos);
    } else if (pass >= 2 && pass <= 9) {
        int stride = 1 << (9 - int(pass));  // pass 2 → stride 128, …, pass 9 → stride 1
        int read_idx = int(pass - 2) % 2;
        stage_walkability_jump(pos, stride, read_idx);
    } else if (pass == 10) {
        int final_buf_idx = 8 % 2;  // after 8 jumps, latest data is in jfa_b? Check: pass 2 reads jfa_a writes jfa_b (read_idx=0); pass 9 read_idx=7%2=1, reads jfa_b writes jfa_a. So final_buf_idx = 0 (jfa_a).
        stage_walkability_finalize(pos, 0);
    }
}
```

Apply the same change to `generation.glsl` (with its existing base-pass stages).

- [ ] **Step 3: Update compute_device dispatch loop.** Locate the existing `dispatch_generation` call and replace its single dispatch with a loop:

```cpp
for (uint32_t pass = 0; pass <= 10; pass++) {
    push_ctx.gen_pass_idx = pass;
    rd->compute_list_set_push_constant(compute_list, &push_ctx, sizeof(push_ctx));
    rd->compute_list_dispatch(compute_list, 32, 32, 1);  // 256/8 = 32 workgroups
    if (pass >= 1 && pass <= 9) {
        rd->compute_list_add_barrier(compute_list);  // ensure JFA write visible to next pass
    }
}
```

- [ ] **Step 4: Run a test scene, capture a chunk readback of the alpha channel, inspect a histogram.** Most cells should now have non-zero alpha (=their inscribed-disk radius). Add a temporary debug print in `world_manager.gd` if needed.

- [ ] **Step 5: Commit.**

```bash
git add -A shaders/ gdextension/
git commit -m "feat(gen): wire JFA walkability probe into gen pipeline"
```

---

## Task 5: Add atomic max-radius reduction

**Files:**
- Modify: `shaders/include/walkability_probe_stage.glslinc`
- Modify: gen shader bindings + compute_device allocation

For the enforce stage we need to know the chunk's max inscribed-disk radius and the coords of its argmax. Use one additional buffer: a single `ivec4` per chunk = `(max_radius, argmax_x, argmax_y, _)`.

Atomic reduction: each cell in finalize compares its computed radius against the buffer's current max via `atomicMax`. To also capture argmax, we pack radius into the upper 16 bits and a packed coord into the lower 16 — `atomicMax` on the combined value gives us both.

- [ ] **Step 1: Allocate `chunk_max_radius_buf` as a SSBO** (4 ints per chunk; we only use the first ivec4 entry).

In compute_device (similar pattern to jfa_a/b allocation):

```cpp
chunk.max_radius_buf = create_storage_buffer(/*size_bytes=*/16, /*data=*/nullptr);
```

Bind as set 0 binding 3.

- [ ] **Step 2: Add binding to gen shaders.**

```glsl
layout(std430, set = 0, binding = 3) buffer ChunkMaxRadius {
    int max_radius_packed;  // upper 16 bits = radius, lower 16 = packed (x<<8 | y)
    int pad0;
    int pad1;
    int pad2;
} chunk_max;
```

- [ ] **Step 3: Update `stage_walkability_finalize`** to also reduce:

```glsl
void stage_walkability_finalize(ivec2 pos, int final_buf_idx) {
    ivec2 seed;
    if (final_buf_idx == 0) {
        seed = imageLoad(jfa_a, pos).xy;
    } else {
        seed = imageLoad(jfa_b, pos).xy;
    }
    int dist = 0;
    if (seed.x >= 0) {
        dist = clamp(max(abs(seed.x - pos.x), abs(seed.y - pos.y)), 0, 127);
    }
    vec4 cur = imageLoad(chunk_tex, pos);
    int alpha_byte = int(round(cur.a * 255.0));
    int new_alpha = (alpha_byte & 0x80) | (dist & 0x7F);
    cur.a = float(new_alpha) / 255.0;
    imageStore(chunk_tex, pos, cur);

    int packed = (dist << 16) | ((pos.x & 0xFF) << 8) | (pos.y & 0xFF);
    atomicMax(chunk_max.max_radius_packed, packed);
}
```

- [ ] **Step 4: Add a clear-pass for the buffer before pass 1.** In compute_device dispatch loop:

```cpp
int zero[4] = {0,0,0,0};
rd->buffer_update(chunk.max_radius_buf, 0, sizeof(zero), zero);
```

(Before the `for` loop over passes.)

- [ ] **Step 5: Readback the buffer in a debug test** — generate a chunk, read `max_radius_packed`, unpack. Expected: most chunks have `(max_radius >> 16) >= 30`-ish given current cave noise.

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(gen): atomic-reduce chunk max-radius for walkability enforce"
```

---

## Task 6: Implement walkability_enforce — strip pools step

**Files:**
- Create: `shaders/include/walkability_enforce_stage.glslinc`

If `chunk_max_radius < 75`, identify cells within `argmax_radius + 80` of the centroid, and if their alpha bit 7 is set (pool-origin), revert them to MAT_AIR.

- [ ] **Step 1: Write the strip-pools stage.**

```glsl
// shaders/include/walkability_enforce_stage.glslinc

const int WALKABILITY_TARGET_RADIUS = 75;

void stage_walkability_strip_pools(ivec2 pos) {
    int packed = chunk_max.max_radius_packed;
    int max_r = packed >> 16;
    if (max_r >= WALKABILITY_TARGET_RADIUS) return;  // already satisfies invariant
    int cx = (packed >> 8) & 0xFF;
    int cy = packed & 0xFF;
    int range = max_r + 80;
    if (max(abs(pos.x - cx), abs(pos.y - cy)) > range) return;

    vec4 cur = imageLoad(chunk_tex, pos);
    int alpha = int(round(cur.a * 255.0));
    bool was_pool = (alpha & 0x80) != 0;
    if (!was_pool) return;

    // Revert to AIR. Clear pool-origin bit; keep radius bits 0-6 (will be recomputed).
    imageStore(chunk_tex, pos, vec4(0.0, 0.0, 0.0, float(alpha & 0x7F) / 255.0));
}
```

- [ ] **Step 2: Add pass index 11 = strip_pools to the gen shader and dispatch loop.**

In `generation_simplex_cave.glsl`:

```glsl
#include "res://shaders/include/walkability_enforce_stage.glslinc"

// in main():
} else if (pass == 11) {
    stage_walkability_strip_pools(pos);
}
```

In compute_device dispatch loop, extend to `pass <= 11`, with a barrier after pass 11.

- [ ] **Step 3: After strip-pools runs, we need to re-run JFA to recompute radius.** Add passes 12 (re-init), 13–20 (re-jumps), 21 (re-finalize) to the dispatch loop. Pass index decoding stays similar — extract via modular arithmetic or branch:

```glsl
} else if (pass == 12) {
    stage_walkability_init(pos);
} else if (pass >= 13 && pass <= 20) {
    int stride = 1 << (20 - int(pass));
    int read_idx = int(pass - 13) % 2;
    stage_walkability_jump(pos, stride, read_idx);
} else if (pass == 21) {
    stage_walkability_finalize(pos, 0);
}
```

In compute_device dispatch loop, before pass 12 also clear `chunk_max.max_radius_packed` back to 0.

- [ ] **Step 4: Test by generating a chunk in a biome with aggressive pools (mines).** Inspect: after the new pipeline, pool-deposited cells inside cramped pockets should be reverted to AIR.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(gen): walkability strip-pools step + JFA retry"
```

---

## Task 7: Implement walkability_enforce — dilate step

**Files:**
- Modify: `shaders/include/walkability_enforce_stage.glslinc`
- Modify: gen shader main, dispatch loop

If `chunk_max_radius < 75` after strip-pools, repeatedly dilate. Each dilate pass: any solid cell within the pocket-bounded region (the square of side `2*(75+30) = 210` centered on argmax) that has at least one air neighbor in the largest air component becomes air.

The "largest air component" detection is annoying without flood fill. Simpler proxy: dilate any solid cell within range that has at least one air neighbor *and* that air neighbor's radius ≥ 1 (i.e. is reachable air, not a noise speckle). Combined with the radius limit, this naturally grows the dominant pocket.

After each dilate pass, re-run JFA.

Cap at 30 iterations.

- [ ] **Step 1: Add the dilate stage function.**

```glsl
// In walkability_enforce_stage.glslinc

void stage_walkability_dilate(ivec2 pos) {
    int packed = chunk_max.max_radius_packed;
    int max_r = packed >> 16;
    if (max_r >= WALKABILITY_TARGET_RADIUS) return;
    int cx = (packed >> 8) & 0xFF;
    int cy = packed & 0xFF;
    int range = 75 + 30;  // pocket-bounded region half-side
    if (max(abs(pos.x - cx), abs(pos.y - cy)) > range) return;

    vec4 cur = imageLoad(chunk_tex, pos);
    int mat = int(round(cur.r * 255.0));
    if (mat == MAT_AIR) return;

    // Check 4-neighbors for "reachable air" (air with radius >= 1).
    bool has_reachable_air = false;
    for (int d = 0; d < 4; d++) {
        ivec2 n = pos;
        if (d == 0) n.x -= 1;
        else if (d == 1) n.x += 1;
        else if (d == 2) n.y -= 1;
        else n.y += 1;
        if (n.x < 0 || n.x >= 256 || n.y < 0 || n.y >= 256) continue;
        vec4 ncur = imageLoad(chunk_tex, n);
        int nmat = int(round(ncur.r * 255.0));
        int nrad = int(round(ncur.a * 255.0)) & 0x7F;
        if (nmat == MAT_AIR && nrad >= 1) {
            has_reachable_air = true;
            break;
        }
    }

    if (has_reachable_air) {
        // Carve to air. Clear alpha (radius will be recomputed next JFA).
        imageStore(chunk_tex, pos, vec4(0.0, 0.0, 0.0, 0.0));
    }
}
```

- [ ] **Step 2: Extend gen shader main and dispatch loop with the iterative dilate.**

Pattern per iteration: 1 dilate pass + 8 JFA passes + 1 finalize. 30 iterations × 10 passes = 300 passes. Use passes 22+.

To keep the shader readable, use a single "iteration_pass_kind" decode:

```glsl
} else if (pass >= 22) {
    uint iter_pass = pass - 22;
    uint iter_kind = iter_pass % 10;
    if (iter_kind == 0) {
        stage_walkability_dilate(pos);
    } else if (iter_kind == 1) {
        stage_walkability_init(pos);
    } else if (iter_kind >= 2 && iter_kind <= 8) {
        int stride = 1 << int(8 - iter_kind);
        int read_idx = int(iter_kind - 2) % 2;
        stage_walkability_jump(pos, stride, read_idx);
    } else if (iter_kind == 9) {
        stage_walkability_finalize(pos, 0);
    }
}
```

Wait — there's still an off-by-one because stride 1 means we only ran 7 jumps, not 8. Adjust: include stride 256 (no-op) by extending iter_kind 2–9 (8 strides). Or just accept that 7 jumps gets to a stable state for the small radius increments produced by dilation. Verify empirically.

In compute_device, after pass 21 add the iteration loop (passes 22 to 22 + 30*10 - 1 = 321), clearing `chunk_max.max_radius_packed` before each iteration's finalize and adding barriers between sub-passes. Crucially, on the host side we cannot easily early-out based on GPU state without a readback — so just run all 30 iterations unconditionally; the dilate is idempotent once max_radius ≥ 75 (the stage early-returns).

- [ ] **Step 3: Test with previously-failing chunks (deep mines floors).** Verify post-gen chunk has max_radius ≥ 75.

- [ ] **Step 4: Commit.**

```bash
git add -A
git commit -m "feat(gen): walkability dilate step with iterative JFA refresh"
```

---

## Task 8: Clear alpha at end of gen

**Files:**
- Modify: gen shaders main

After all gen passes, the alpha channel must be cleared so downstream readers (rendering, collision, etc.) see clean alpha.

- [ ] **Step 1: Add a final pass = 322 that clears alpha.**

```glsl
} else if (pass == 322) {
    vec4 cur = imageLoad(chunk_tex, pos);
    cur.a = 0.0;
    imageStore(chunk_tex, pos, cur);
}
```

Extend dispatch loop to `pass <= 322`.

- [ ] **Step 2: Verify visuals are unchanged from before walkability work.**

- [ ] **Step 3: Commit.**

```bash
git add -A
git commit -m "feat(gen): clear scratch alpha after walkability pipeline"
```

---

## Task 9: Chunk-type redistribution (TYPE_CAVE_THRESHOLD)

**Files:**
- Modify: `shaders/include/cave_utils.glslinc:93`

- [ ] **Step 1: Change the threshold constant.**

```glsl
// Was: const uint TYPE_CAVE_THRESHOLD = 55u;
const uint TYPE_CAVE_THRESHOLD = 85u;
```

- [ ] **Step 2: Hand-test: walk through a generated level, confirm tunnel chunks are now rare** (eye-test: roughly 1 in 7 chunks should still look narrow/corridor-shaped).

- [ ] **Step 3: Commit.**

```bash
git add shaders/include/cave_utils.glslinc
git commit -m "feat(gen): reduce tunnel chunk share 45% -> 15%"
```

---

## Task 10: Widen inter-chunk tunnels

**Files:**
- Modify: `shaders/include/cave_stage.glslinc:104`

- [ ] **Step 1: Change tunnel radius.**

```glsl
// Was: const float TUNNEL_RADIUS = 10.0;
const float TUNNEL_RADIUS = 14.0;
```

- [ ] **Step 2: Hand-test: confirm cross-chunk passages feel wider in play.**

- [ ] **Step 3: Commit.**

```bash
git add shaders/include/cave_stage.glslinc
git commit -m "feat(gen): widen inter-chunk tunnel radius 10 -> 14"
```

---

## Task 11: Clamp biome cave_threshold ≤ 0.42

**Files:**
- Modify: `assets/biomes/caves.tres`, `mines.tres`, `magma.tres`, `frozen.tres`, `vault.tres`

For each biome resource, open and inspect the `cave_threshold` value. Any value > 0.42, change to 0.42.

- [ ] **Step 1: List current values.**

```bash
grep -A1 'cave_threshold' assets/biomes/*.tres
```

- [ ] **Step 2: Edit each .tres** to set `cave_threshold = 0.42` for any biome where it's higher. Leave biomes that are already at 0.42 or below unchanged.

- [ ] **Step 3: Open the project in Godot, briefly walk through each biome to confirm caves feel airier than before.**

- [ ] **Step 4: Commit.**

```bash
git add assets/biomes/
git commit -m "tune(biomes): clamp cave_threshold to 0.42 across all biomes"
```

---

## Task 12: Walkability invariant unit test

**Files:**
- Create: `tests/unit/test_walkability_invariant.gd`

The test instantiates a `WorldManager`, generates a 5×5 chunk patch around origin (skipping the boss-ring), and asserts every cave chunk has max_radius ≥ 75. Uses `read_region` to inspect chunk data.

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_walkability_invariant.gd
extends GdUnitTestSuite

const CHUNK_SIZE := 256
const TARGET_RADIUS := 75

func test_invariant_holds_across_biomes_and_seeds() -> void:
    var failures: Array[String] = []
    for biome_idx in range(BiomeRegistry.biomes.size()):
        LevelManager.current_biome = BiomeRegistry.biomes[biome_idx]
        for seed_val in [1, 42, 1337, 9001]:
            LevelManager.world_seed = seed_val
            var wm := _spawn_world_manager()
            wm.tracking_position = Vector2(CHUNK_SIZE * 3, CHUNK_SIZE * 3)
            await _wait_for_chunks(wm, 30)
            for cx in range(2, 5):
                for cy in range(2, 5):
                    var coord := Vector2i(cx, cy)
                    if not wm.chunks.has(coord):
                        continue
                    var max_r := _measure_max_inscribed_radius(wm, coord)
                    if max_r < TARGET_RADIUS:
                        failures.append("biome=%d seed=%d chunk=%s max_r=%d" % [biome_idx, seed_val, str(coord), max_r])
            wm.queue_free()
    assert_that(failures).is_empty()

func _spawn_world_manager() -> Node2D:
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    return wm

func _wait_for_chunks(wm: Node2D, frames: int) -> void:
    for _i in range(frames):
        await get_tree().process_frame

func _measure_max_inscribed_radius(wm: Node2D, coord: Vector2i) -> int:
    # Read the chunk's material data; for each air cell, compute Chebyshev distance to nearest solid via BFS.
    # Return max over all air cells. This is the GDScript-side ground truth.
    var rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
    var data := wm.read_region(rect)
    var best := 0
    # Brute-force: for each air cell, sample expanding rings until a solid is found.
    var step := 8  # sample stride for speed; good enough to detect >= 75 vs < 75
    for y in range(0, CHUNK_SIZE, step):
        for x in range(0, CHUNK_SIZE, step):
            if data[y * CHUNK_SIZE + x] != MaterialRegistry.MAT_AIR:
                continue
            var r := _chebyshev_to_nearest_solid(data, x, y)
            if r > best:
                best = r
    return best

func _chebyshev_to_nearest_solid(data: PackedByteArray, x: int, y: int) -> int:
    for r in range(1, 128):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                var nx := x + dx
                var ny := y + dy
                if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE:
                    return r
                if data[ny * CHUNK_SIZE + nx] != MaterialRegistry.MAT_AIR:
                    return r
    return 128
```

- [ ] **Step 2: Run the test, expect PASS** (since we've already done tasks 1-12):

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_walkability_invariant.gd
```

- [ ] **Step 3: If it FAILS,** the chunks failing are likely the multi-cave variants. Investigate by inspecting which biome/seed/coord failed, render that chunk, and tweak either dilate iteration count or the JFA finalize pass index (the read_idx parity issue). Re-run until green.

- [ ] **Step 4: Commit.**

```bash
git add tests/unit/test_walkability_invariant.gd
git commit -m "test: walkability invariant across biomes and seeds"
```

---

## Task 13: Connectivity test

**Files:**
- Create: `tests/unit/test_walkability_connectivity.gd`

Assert that ≥95% of air cells in a generated region belong to the largest connected air component.

- [ ] **Step 1: Write the test.**

```gdscript
# tests/unit/test_walkability_connectivity.gd
extends GdUnitTestSuite

const CHUNK_SIZE := 256

func test_air_is_well_connected() -> void:
    LevelManager.current_biome = BiomeRegistry.biomes[0]
    LevelManager.world_seed = 12345
    var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
    add_child(wm)
    wm.tracking_position = Vector2(CHUNK_SIZE * 4, CHUNK_SIZE * 4)
    for _i in range(30):
        await get_tree().process_frame

    var rect := Rect2i(CHUNK_SIZE * 2, CHUNK_SIZE * 2, CHUNK_SIZE * 4, CHUNK_SIZE * 4)
    var data := wm.read_region(rect)
    var w := rect.size.x
    var h := rect.size.y
    var visited := PackedByteArray()
    visited.resize(w * h)

    var total_air := 0
    var largest_component := 0
    for y in range(h):
        for x in range(w):
            if visited[y * w + x] != 0:
                continue
            if data[y * w + x] != MaterialRegistry.MAT_AIR:
                continue
            var size := _flood_fill(data, visited, w, h, x, y)
            total_air += size
            if size > largest_component:
                largest_component = size

    var ratio := float(largest_component) / float(max(1, total_air))
    wm.queue_free()
    assert_that(ratio).is_greater_equal(0.95)

func _flood_fill(data: PackedByteArray, visited: PackedByteArray, w: int, h: int, sx: int, sy: int) -> int:
    var stack: Array[Vector2i] = [Vector2i(sx, sy)]
    var size := 0
    while not stack.is_empty():
        var p: Vector2i = stack.pop_back()
        if p.x < 0 or p.x >= w or p.y < 0 or p.y >= h:
            continue
        var idx := p.y * w + p.x
        if visited[idx] != 0:
            continue
        if data[idx] != MaterialRegistry.MAT_AIR:
            continue
        visited[idx] = 1
        size += 1
        stack.append(Vector2i(p.x + 1, p.y))
        stack.append(Vector2i(p.x - 1, p.y))
        stack.append(Vector2i(p.x, p.y + 1))
        stack.append(Vector2i(p.x, p.y - 1))
    return size
```

- [ ] **Step 2: Run and verify PASS.**

- [ ] **Step 3: Commit.**

```bash
git add tests/unit/test_walkability_connectivity.gd
git commit -m "test: air connectivity >= 95% largest-component ratio"
```

---

## Done Criteria

- [ ] `tests/unit/test_walkability_invariant.gd` and `tests/unit/test_walkability_connectivity.gd` both pass on every biome
- [ ] Hand-playtest in editor: caves feel walkable on every floor (test through floor 5+)
- [ ] Cross-chunk tunnels look comfortably wide (no pinches)
- [ ] Tunnel chunks still appear occasionally (~1 in 7) but don't dominate
- [ ] Per-chunk gen time increase ≤ 5 ms on dev GPU (measure via existing perf instrumentation or add an ad-hoc `Time.get_ticks_usec()` around `dispatch_generation`)
