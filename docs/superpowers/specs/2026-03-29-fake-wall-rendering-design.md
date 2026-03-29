# Fake Wall Rendering Design

## Overview

Add a classic top-down wall extrusion effect to the existing pixel terrain renderer. Solid pixels (wood, fire) appear as vertical walls that stretch downward on screen, textured from a wall texture atlas. Interior wall tops far from any air pixel render as black. No changes to the compute pipeline or data format — all rendering logic lives in the fragment shader.

## Approach

**Fragment shader only (Approach A).** The render shader (`render_chunk.gdshader`) is modified to scan the chunk data texture and determine per-fragment whether to draw a wall face, a wall top, black interior, or transparent air. No new compute shaders, no additional textures per chunk, no geometry changes.

## New Uniforms

| Uniform | Type | Default | Purpose |
|---------|------|---------|---------|
| `wall_texture` | `sampler2D` (filter_nearest) | — | Wall face texture (e.g., 16x16 stone/brick tile) |
| `wall_height` | `int` | 16 | Wall extrusion height in pixels |

Both are set once per `ShaderMaterial` and shared across all chunks. The chunk texture size (256) is derived via `textureSize()`.

## Fragment Shader Logic

For each fragment at pixel position `(px, py)` derived from UV and chunk size:

### Step 1: Sample current pixel

Read `chunk_data` at `(px, py)`. Determine material type (air, wood, fire).

### Step 2: Air pixel — wall face check

If the current pixel is **air**:

1. Scan upward (incrementing `py` in texture space, which corresponds to upward on screen due to Y-flip) from distance 1 to `wall_height`.
2. On the first solid pixel found at distance `d`:
   - **Texture sampling:** U = `(px % tex_width + 0.5) / tex_width`, V = `(d - 1 + 0.5) / wall_height`. This selects the column by world x-position (adjacent pixels get adjacent columns for continuity) and maps the row within the wall face height.
   - **Tinting:** Multiply the sampled texture color by the material color of the source solid pixel (existing temperature/health-based coloring for wood and fire).
   - Output the tinted texture color. Done.
3. If no solid pixel found within `wall_height`: output transparent `vec4(0.0)`.

### Step 3: Solid pixel — wall top or black

If the current pixel is **solid**:

1. **Check pixel below** (decrementing `py` in texture space = downward on screen): is it solid?
   - **If solid below AND not close to air:** skip drawing — output black `vec4(0.0, 0.0, 0.0, 1.0)`. This pixel is hidden interior.
   - **If solid below AND close to air:** render **wall top** with normal material color.
   - **If air below (or at bottom edge of chunk, py == 0 in texture space):** this pixel's wall face will be drawn by air fragments below via Step 2. Render the **wall top**:
     - Close to air: normal material color.
     - Not close to air: black.

### Air Proximity Check

A solid pixel is "close to air" if any pixel within euclidean distance 3 is air.

**Implementation:** Loop over a 7x7 box (`dx` and `dy` from -3 to +3). Skip pixels where `dx*dx + dy*dy > 9`. Sample `chunk_data` at each offset. Early-exit on the first air pixel found.

**Out-of-bounds handling:** Pixels outside the 256x256 chunk boundary are treated as **solid**. This means chunk-edge interior walls stay black, avoiding false positives at boundaries.

**Maximum lookups per fragment:** Up to 28 samples for the air check (7x7 box minus corners minus center), plus up to 16 samples for the wall face scan. Total ~44 lookups worst case — well within GPU capability at 256x256 resolution.

## Texture Mapping Details

The wall texture is a standard image asset (e.g., 16x16 pixels). Each wall pixel's 16px vertical extrusion samples **one column** from the texture:

- Column index = `pixel_x % texture_width`
- Row 0 = top of the wall face (closest to the solid pixel), row `wall_height - 1` = bottom
- Adjacent pixels sample adjacent columns, producing a horizontally continuous wall surface
- `filter_nearest` preserves pixel-crisp rendering

## Coordinate System

The existing render shader flips Y: `texture(chunk_data, vec2(UV.x, 1.0 - UV.y))`. In texture pixel coordinates:

- **"Below" on screen** = decreasing `py` in texture space
- **"Above" on screen** = increasing `py` in texture space
- Scanning "upward" for wall face sources = incrementing `py`
- Wall faces extrude "downward" on screen from their source solid pixel

## Occlusion

Handled implicitly by the scan logic. Each air fragment finds the **first** (closest) solid pixel above it and draws that wall face. Farther wall faces are never reached. This is equivalent to back-to-front (painter's algorithm) rendering without explicit sorting.

## Material Color Functions

The existing material coloring is extracted into reusable logic within the shader:

- **Wood:** base brown `vec3(0.55, 0.35, 0.17)` mixed toward hot red `vec3(0.8, 0.2, 0.1)` by temperature
- **Fire:** dim red `vec3(0.8, 0.1, 0.0)` mixed toward bright orange `vec3(1.0, 0.6, 0.1)` by health

Wall faces multiply the texture sample by this color. Wall tops use the color directly.

## GDScript Changes

**`world_manager.gd`:**

1. Load wall texture at startup (e.g., `var wall_texture := preload("res://textures/wall.png")`)
2. In `_create_chunk()`, add two `set_shader_parameter()` calls on the `ShaderMaterial`:
   - `mat.set_shader_parameter("wall_texture", wall_texture)`
   - `mat.set_shader_parameter("wall_height", 16)`

No other script changes required.

## Asset Requirements

One wall texture image file (e.g., `res://textures/wall.png`), 16x16 pixels, stone/brick pattern. A placeholder can be used for initial development.

## Files Modified

| File | Change |
|------|--------|
| `shaders/render_chunk.gdshader` | Rewrite fragment function with wall rendering logic, add uniforms |
| `scripts/world_manager.gd` | Load wall texture, pass uniforms to chunk materials |

## Files Added

| File | Purpose |
|------|---------|
| `textures/wall.png` | Wall face texture asset (placeholder or final) |
