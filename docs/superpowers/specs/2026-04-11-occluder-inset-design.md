# Occluder Inset Design

**Date**: 2026-04-11
**Status**: Draft

## Overview

Shrink light occluder polygons inward by a configurable distance so that the outer "ring" of wall tops receives light instead of being fully shadowed.

## Problem

Currently, light occluder polygons cover all solid terrain pixels, including boundary pixels near air. This causes wall tops to be fully shadowed, even though their outer ring (pixels within 3 units of air) should receive light.

The shader's `near_air()` function checks a 7-pixel radius for air proximity to determine if a wall top should be visible. The occluder should inset by a matching distance to allow light to reach these boundary pixels.

## Solution

Offset the occluder polygon vertices inward by 3 pixels (configurable) using vertex normal averaging. This shrinks the occluder polygon so the outer ring of wall tops falls outside the shadow region.

## Architecture

### Occluder Polygon Flow

```
Marching squares segment generation
        ↓
Trace closed polygon chains
        ↓
Shrink polygon vertices inward (NEW)
        ↓
Create OccluderPolygon2D
```

### Vertex Offset Algorithm

For each vertex in a closed polygon:
1. Get adjacent edge vectors (prev→current, current→next)
2. Compute perpendicular vectors for each edge
3. Choose inward-facing direction based on winding order
4. Average perpendiculars to get vertex normal
5. Offset vertex: `v' = v + normal * distance`

Winding order detection via signed area calculation determines whether the polygon is counter-clockwise (positive area) or clockwise (negative area).

## Implementation Details

### File: `src/physics/terrain_collider.gd`

**New constant:**
```gdscript
const OCCLUDER_INSET := 3.0
```

**New static function:**
```gdscript
static func shrink_polygon(points: PackedVector2Array, distance: float) -> PackedVector2Array
```

Implementation:
- Handle edge cases: polygons with < 3 vertices return unchanged
- Calculate signed area: `sum((x[i+1]-x[i])*(y[i+1]+y[i]))` for winding direction
- For each vertex, compute inward normal from adjacent edge perpendiculars
- Return new PackedVector2Array with offset vertices

**Modified function:** `create_occluder_polygons()`
- After successfully tracing a closed chain, apply `shrink_polygon(chain, OCCLUDER_INSET)` before creating OccluderPolygon2D

## Edge Cases

1. **Small polygons:** If shrinking produces degenerate polygons (< 3 vertices or self-intersecting), skip creating occluder for that chain
2. **Concave polygons:** Vertex offset can cause self-intersection on highly concave shapes. Accept this limitation for now - Godot's shadow system will handle gracefully
3. **Multiple chains:** Each closed loop is shrunk independently

## Testing

1. **Visual verification:** Wall tops near terrain edges should receive light, interior walls remain dark
2. **Dynamic updates:** Destroy terrain, verify occluder updates within 0.2s
3. **Edge cases:** Small terrain islands, complex concave shapes