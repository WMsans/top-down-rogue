# Terrain Overlap Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the player from getting permanently stuck inside terrain when digging into walls.

**Architecture:** Add a `_resolve_terrain_overlap()` method to `PlayerController` that runs after `move_and_slide()`. It uses `PhysicsDirectSpaceState2D.intersect_shape()` to detect terrain overlaps, then iteratively pushes the player out using direction-priority stepwise recovery. A hard fallback snaps to the last known safe position if all steps fail.

**Tech Stack:** Godot 4.6, GDScript, built-in 2D physics API

---

### Task 1: Add terrain overlap recovery constants and state

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Add constants after the existing `HIT_FLASH_COLOR` constant (line 25)**

After line 25 (`const HIT_FLASH_COLOR := Color(2.5, 0.3, 0.1)`), add:

```gdscript
const MAX_RECOVERY_STEPS := 8
const RECOVERY_STEP := 2.0
```

- [ ] **Step 2: Add `_last_safe_position` instance variable after `_zoom_tween` (line 30)**

After line 30 (`var _zoom_tween: Tween`), add:

```gdscript
var _last_safe_position: Vector2 = Vector2.ZERO
```

- [ ] **Step 3: Initialize `_last_safe_position` in `_ready()`**

In `_ready()`, after the spawn position assignment (line 59: `position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)`), add:

```gdscript
	_last_safe_position = position
```

- [ ] **Step 4: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat(player): add terrain overlap recovery constants and state variables"
```

---

### Task 2: Add the `_resolve_terrain_overlap()` method

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Add the `_resolve_terrain_overlap()` method after `_is_blocked_by_terrain()` (after line 127)**

After the `_is_blocked_by_terrain` method, add the following method:

```gdscript
func _resolve_terrain_overlap() -> void:
	var shape_node: CollisionShape2D = $CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		_last_safe_position = global_position
		return
	var space_state := get_world_2d().direct_space_state
	var shape_params := PhysicsShapeQueryParameters2D.new()
	shape_params.shape = shape_node.shape
	shape_params.transform = global_transform
	shape_params.collision_mask = 1  # terrain layer
	shape_params.collide_with_areas = false
	shape_params.collide_with_bodies = true
	shape_params.margin = 0.0

	var overlaps := space_state.intersect_shape(shape_params, 1)
	if overlaps.is_empty():
		_last_safe_position = global_position
		return

	var priority_dir := _last_facing if _last_facing.length_squared() > 0.01 else Vector2.ZERO
	var directions: Array[Vector2] = []
	if priority_dir != Vector2.ZERO:
		directions.append(priority_dir.normalized())
	directions.append_array([
		Vector2.UP,
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.UP + Vector2.RIGHT,
		Vector2.DOWN + Vector2.RIGHT,
		Vector2.DOWN + Vector2.LEFT,
		Vector2.UP + Vector2.LEFT,
	])
	for d_idx in directions.size():
		directions[d_idx] = directions[d_idx].normalized()

	for step in MAX_RECOVERY_STEPS:
		var escaped := false
		for dir in directions:
			var test_pos := global_position + dir * RECOVERY_STEP
			shape_params.transform = Transform2D(global_rotation, test_pos)
			var test_overlaps := space_state.intersect_shape(shape_params, 1)
			if test_overlaps.is_empty():
				global_position = test_pos
				_last_safe_position = global_position
				return
			escaped = false
		if not escaped:
			break

	global_position = _last_safe_position
```

- [ ] **Step 2: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat(player): add _resolve_terrain_overlap method for collision recovery"
```

---

### Task 3: Integrate `_resolve_terrain_overlap()` into `_physics_process()`

**Files:**
- Modify: `src/player/player_controller.gd`

- [ ] **Step 1: Call `_resolve_terrain_overlap()` after `move_and_slide()` in the main movement path (line 95)**

Change line 95 from:

```gdscript
	move_and_slide()
```

To:

```gdscript
	move_and_slide()
	_resolve_terrain_overlap()
```

- [ ] **Step 2: Also call `_resolve_terrain_overlap()` in the dead-player path (line 72)**

Change lines 71-73 from:

```gdscript
		velocity = Vector2.ZERO
		move_and_slide()
		return
```

To:

```gdscript
		velocity = Vector2.ZERO
		move_and_slide()
		_resolve_terrain_overlap()
		return
```

- [ ] **Step 3: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat(player): integrate terrain overlap recovery into physics process"
```

---

### Task 4: Manual playtest verification

**Files:** None (manual testing)

- [ ] **Step 1: Run the game in the Godot editor**

Launch the game and playtest in a room with stone walls.

- [ ] **Step 2: Test normal wall collision**

Walk into a wall without attacking. Verify the player slides along the wall normally and does NOT get pushed away when simply walking alongside terrain.

- [ ] **Step 3: Test digging into stone**

Attack a stone wall to carve a pocket. Walk into the pocket. Verify the player is pushed out if they overlap with terrain after the collision shape updates.

- [ ] **Step 4: Test rapid digging while moving**

Hold move direction into a wall while repeatedly attacking. Verify the player never gets permanently stuck — they should always be pushed free.

- [ ] **Step 5: Verify no regression in creative mode**

Switch to creative mode (where collision is disabled) and verify terrain overlap recovery does not interfere (it should early-return since the `intersect_shape` check uses mask 1 which the creative-mode player isn't checking, and the player has no collision in creative mode anyway).

- [ ] **Step 6: Verify knockback still works**

Take damage from an enemy. Verify knockback movement works and the recovery doesn't clash with it.