# Wall Ambient Occlusion — Design

## Problem

Walls in the top-down view read as flat cut-outs pasted onto the floor. There is
no soft darkening where walls meet the floor, in concave corners, or down the
extruded wall faces, so geometry lacks grounding and depth. We want a cheap,
fully dynamic ambient-occlusion (AO) effect that darkens these regions.

All terrain is carveable, so AO must be computed live from the chunk texture
every frame rather than baked — see the destructibility philosophy memory.

## Goals

- **Floor contact shadow**: darken the floor in a band hugging the base of walls.
- **Inner-corner darkening**: stronger darkening in concave corners where wall
  edges meet — emerges for free from the same occlusion measure.
- **Wall-face gradient**: darken the extruded vertical wall faces toward their
  bottom edge.
- Fully dynamic: updates as terrain is carved, no baking, no extra textures or
  compute passes.
- Tunable live in the editor via shader uniforms (reach + intensities).

## Non-goals

- **No top-cap edge shading** (soft bevel on wall tops) — explicitly excluded.
- No directional/baked lighting; AO is uniform (ambient), independent of the
  existing dynamic light system.
- No cross-chunk neighbor sampling for AO. A faint loss of shadow at chunk seams
  is accepted (see Edge Cases).
- No new compute pass, storage buffer, or AO texture. Everything lives in
  `shaders/visual/render_chunk.gdshader`.

## Background — how wall rendering works today

`render_chunk.gdshader` (`canvas_item`) is applied twice per chunk on the same
`chunk_data` RGBA8 texture (`src/core/chunk_manager.gd:83-108`):

- `mesh_instance` — `layer_mode = 1`, default z. Draws the **extruded wall faces**:
  for each `MAT_AIR` pixel it scans downward `d = 1..wall_height` (`px.y + d`) for
  the first solid and renders that wall's side texture via
  `sample_material_texture(material, px.x, d, ...)`. Solid pixels output transparent.
- `wall_mesh_instance` — `layer_mode = 0`, `z_index = 1` (drawn **above** faces).
  Draws the **top caps**: solid pixels render the material top color (only if
  `near_air`, else black); `MAT_AIR` pixels currently return `vec4(0.0)`
  (transparent), letting the separate `FloorChunk` sprite floor show through.

`is_solid(pos)` returns true and treats **out-of-bounds as solid**. Fluids/dust/
explode-wave remap `mat` to `MAT_AIR` and composite a tint at the end of
`fragment()`; the AO branches run before that composite, so fluid overlays are
preserved.

## Design

All changes are in `shaders/visual/render_chunk.gdshader`.

### New uniforms

```glsl
uniform bool  ao_enabled        = true;
uniform float ao_radius         = 3.5;   // reach of floor/corner shadow, in px
uniform float ao_intensity      = 0.4;   // max floor/corner darkening (0..1)
uniform float face_ao_intensity = 0.4;   // max darkening at bottom of wall face
const   int   AO_MAX_RADIUS     = 6;      // compile-time loop bound
```

Defaults match the chosen "medium" look. `ao_radius` is the tunable reach; the
loop iterates the fixed `AO_MAX_RADIUS` box and skips offsets beyond `ao_radius`,
so reach is adjustable up to 6 px without recompiling.

### Occlusion sampler

A distance-weighted disk over the live terrain:

```glsl
// OOB treated as AIR here (unlike is_solid), so chunk borders don't self-shadow.
bool is_solid_ao(ivec2 pos) {
    if (pos.x < 0 || pos.x >= CHUNK_SIZE || pos.y < 0 || pos.y >= CHUNK_SIZE)
        return false;
    return HAS_COLLIDER[get_material(read_pixel(pos))];
}

// 0 in open floor, ~0.5 beside a flat wall, ~0.75 in a concave corner.
float ao_occlusion(ivec2 pos) {
    float occ = 0.0;
    float total = 0.0;
    for (int dy = -AO_MAX_RADIUS; dy <= AO_MAX_RADIUS; dy++) {
        for (int dx = -AO_MAX_RADIUS; dx <= AO_MAX_RADIUS; dx++) {
            if (dx == 0 && dy == 0) continue;
            float dist = sqrt(float(dx*dx + dy*dy));
            if (dist > ao_radius) continue;
            float w = 1.0 - dist / ao_radius;   // closer cells weigh more
            total += w;
            if (is_solid_ao(pos + ivec2(dx, dy))) occ += w;
        }
    }
    return total > 0.0 ? occ / total : 0.0;
}
```

Contact-shadow falloff (fades over `ao_radius` as you move away from a wall) and
corner darkening (more surrounding solids → higher `occ`) both fall out of this
single value. No special-casing of corners is needed.

### Floor contact shadow — `layer_mode == 0`, `MAT_AIR` branch

Today this returns `vec4(0.0)`. Replace with:

1. **Skip face cells.** If a wall exists within `wall_height` below this air pixel
   (the same downward scan the face pass uses), this pixel is covered by a wall
   face in the other pass — leave it transparent so the two effects never stack on
   the same pixel. The face gradient handles darkening there.
2. **Cheap pre-check.** Sample `is_solid_ao` at the 4 immediate neighbors and the
   4 diagonal points at distance `int(ceil(ao_radius))`. If all are air, skip the
   full disk and return transparent (keeps open floor at ~0 cost). This can in rare
   cases miss a lone solid pixel sitting between sample points, producing a ≤1px
   gap in the shadow band — an acceptable tradeoff for the cost saving.
3. Otherwise compute `ao_alpha = ao_occlusion(px) * ao_intensity` and output
   `base_color = vec4(0.0, 0.0, 0.0, ao_alpha)`.

Because this pass draws above the floor sprite (z_index 1) with straight-alpha
black, the floor darkens by `ao_alpha` underneath. The existing fluid composite at
the end of `fragment()` still runs (`max(base.a, fluid_alpha)`), so fluids over
near-wall floor remain visible.

When `ao_enabled` is false, the branch returns `vec4(0.0)` as before.

### Wall-face gradient — `layer_mode == 1`, face scan

When the downward scan finds the wall at depth `d`, multiply the sampled face
color by a depth factor before assigning `base_color`:

```glsl
float face_factor = mix(1.0, 1.0 - face_ao_intensity,
                        float(d) / float(wall_height));
vec3 face_rgb = sample_material_texture(...) * face_factor;
```

Top of the face (small `d`) stays full-bright; the bottom edge is darkest. Gated
by `ao_enabled` (factor = 1.0 when disabled).

## Edge cases

- **Chunk seams (accepted).** `is_solid_ao` treats out-of-bounds as air, so a wall
  in a neighbor chunk casts no contact shadow across the boundary — edges lose a
  little shadow rather than gaining a false dark grid line. This is the
  deliberately accepted seam.
- **Fluid / dust / explode-wave cells.** These are remapped to `MAT_AIR` before the
  AO branch. They are non-colliding, so `is_solid_ao` already excludes them from
  occlusion, and the floor-shadow branch composites under their tint normally.
- **Fully open chunk.** The pre-check short-circuits every air pixel, so AO adds
  negligible cost where there are no walls.
- **Solid interiors.** Unchanged — the `near_air` black-fill path for deep solid
  pixels is untouched.

## Performance

The disk adds up to ~`π·ao_radius²` (~38 at radius 3.5) texture taps per
near-wall air pixel in the top-cap pass, comparable to the existing `near_air`
(~29 taps) already run per surface solid pixel. The face-cell skip costs one
extra downward scan (≤ `wall_height` taps) on air pixels, and the pre-check keeps
open floor at near-zero cost. Net cost is concentrated in the thin band of floor
within `ao_radius` of walls.

## Testing

- Visual: load a level, confirm a soft dark band hugs wall bases, corners read
  darker than straight edges, and wall faces fade toward their bottom.
- Carve a wall and confirm the shadow updates immediately (dynamic, not baked).
- Toggle `ao_enabled` off and confirm rendering matches today's output exactly.
- Sweep `ao_radius` (2→6) and `ao_intensity` (0→0.6) in the editor and confirm
  reach/darkness respond live.
- Inspect a chunk boundary: confirm no dark grid line appears (seam loses shadow,
  not gains it).
