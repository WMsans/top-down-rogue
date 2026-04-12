# Occluder Inset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink light occluder polygons inward by 3 pixels so wall top outer rings receive light.

**Architecture:** Add vertex offset algorithm to marching squares polygon generation. Calculate winding order, compute inward normals from edge perpendiculars, offset each vertex.

**Tech Stack:** GDScript, Godot 4.x, PackedVector2Array

---

### Task 1: Add Occluder Inset Constant

**Files:**
- Modify: `src/physics/terrain_collider.gd:4-8` (after DP_EPSILON constant)

- [ ] **Step 1: Add the OCCLUDER_INSET constant**

Add after line 8 (after `const DP_EPSILON := 0.8`):

```gdscript
## Distance to inset occluder polygons (in pixels). Matches near_air() radius.
const OCCLUDER_INSET := 3.0
```

- [ ] **Step 2: Verify syntax**

Run: `godot --headless --script-check res://src/physics/terrain_collider.gd`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/physics/terrain_collider.gd
git commit -m "feat: add OCCLUDER_INSET constant"
```

---

### Task 2: Implement shrink_polygon Function

**Files:**
- Modify: `src/physics/terrain_collider.gd` (add after `_point_to_segment_distance`)

- [ ] **Step 1: Add shrink_polygon static function**

Add after the `_point_to_segment_distance` function (after line 197):

```gdscript


## Shrink a closed polygon by offsetting vertices inward along their normals.
## Points must form a closed loop (first and last are implicit neighbors).
## Returns a new polygon with inset vertices, or empty if degenerate.
static func shrink_polygon(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	
	# Calculate signed area to determine winding direction
	# Positive = counter-clockwise, negative = clockwise
	var signed_area := 0.0
	for i in points.size():
		var j := (i + 1) % points.size()
		signed_area += points[i].x * points[j].y - points[j].x * points[i].y
	signed_area *= 0.5
	
	# Inward direction multiplier: +1 for CCW (positive area), -1 for CW (negative area)
	var inward_mult := 1.0 if signed_area > 0 else -1.0
	
	var result := PackedVector2Array()
	result.resize(points.size())
	
	for i in points.size():
		var prev_idx := (i - 1 + points.size()) % points.size()
		var next_idx := (i + 1) % points.size()
		
		# Edgefrom prev to current, and current to next
		var edge1 := points[i] - points[prev_idx]
		var edge2 := points[next_idx] - points[i]
		
		# Perpendiculars (rotate90counter-clockwise)
		var perp1 := Vector2(-edge1.y, edge1.x)
		var perp2 := Vector2(-edge2.y, edge2.x)
		
		# Normalize and average for vertex normal
		var normal := (perp1.normalized() + perp2.normalized()).normalized()
		# Apply inward offset
		result[i] = points[i] + normal * distance * inward_mult
	
	return result
```

- [ ] **Step 2: Verify syntax**

Run: `godot --headless --script-check res://src/physics/terrain_collider.gd`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/physics/terrain_collider.gd
git commit -m "feat: add shrink_polygon function for occluder inset"
```

---

### Task 3: Apply Shrink to Occluder Polygons

**Files:**
- Modify: `src/physics/terrain_collider.gd:281-284` (in `create_occluder_polygons`)

- [ ] **Step 1: Apply shrink_polygon to closed chains**

Replace lines 281-284 (the block that creates OccluderPolygon2D):

```gdscript
		if chain.size() >= 3 and closed:
			var shrunk := shrink_polygon(chain, OCCLUDER_INSET)
			if shrunk.size() >= 3:
				var polygon := OccluderPolygon2D.new()
				polygon.polygon = shrunk
				result.append(polygon)
```

- [ ] **Step 2: Verify syntax**

Run: `godot --headless --script-check res://src/physics/terrain_collider.gd`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/physics/terrain_collider.gd
git commit -m "feat: apply shrink_polygon to occluder polygons"
```

---

### Task 4: Visual Verification

**Files:**
- None (manual testing)

- [ ] **Step 1: Run the game**

Run: `godot --path .`
Expected: Game launches

- [ ] **Step 2: Verify wall top lighting**

1. Place player near terrain wall
2. Observe that outer wall tops (near air) receive light
3. Observe that interior wall tops remain dark
4. Move around and verify shadows update correctly

- [ ] **Step 3: Test dynamic terrain**

1. Destroy terrain blocks
2. Verify occluder updates within 0.2s
3. Verify new wall tops receive light correctly