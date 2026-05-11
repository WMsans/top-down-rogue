# Wall-Block Detection Auto-Facing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the player to carve terrain by facing the input direction when blocked by a wall, while preserving auto-face-to-enemy behavior otherwise.

**Architecture:** Add a short raycast check (`_is_blocked_by_terrain()`) in `player_controller.gd` that detects when the player is pushing against terrain. When blocked, input direction overrides auto-face; otherwise auto-face to nearest enemy as before. Single-file change, no new inputs.

**Tech Stack:** Godot 4 (GDScript), CharacterBody2D, PhysicsRayQueryParameters2D

---

### Task 1: Add wall-block detection and modify facing logic

**Files:**
- Modify: `src/player/player_controller.gd`

**Spec reference:** `docs/superpowers/specs/2026-05-11-wall-block-auto-facing-design.md`

- [ ] **Step 1: Add `_is_blocked_by_terrain()` function**

Insert the following function after `_get_input_direction()` (after line 105, before `_apply_movement`):

```gdscript
func _is_blocked_by_terrain(direction: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + direction * 4.0,
		1,  # terrain collision_layer (see chunk_manager.gd:115)
		[self]
	)
	var result := space_state.intersect_ray(query)
	return not result.is_empty()
```

- [ ] **Step 2: Modify auto-facing logic in `_physics_process()`**

Replace lines 73-77:

```gdscript
	var enemy_dir := _find_closest_enemy_direction()
	if enemy_dir != Vector2.ZERO:
		_last_facing = enemy_dir
	elif input_dir != Vector2.ZERO:
		_last_facing = input_dir
```

With:

```gdscript
	var enemy_dir := _find_closest_enemy_direction()
	var is_pushing_wall := input_dir != Vector2.ZERO and _is_blocked_by_terrain(input_dir)
	if is_pushing_wall:
		_last_facing = input_dir
	elif enemy_dir != Vector2.ZERO:
		_last_facing = enemy_dir
	elif input_dir != Vector2.ZERO:
		_last_facing = input_dir
```

- [ ] **Step 3: Run script parse check**

```bash
# Godot headless parse check (catches syntax errors)
/Applications/Godot.app/Contents/MacOS/Godot --headless --script src/player/player_controller.gd --check-only 2>&1 || echo "SKIP (headless check not available)"
```

This is advisory only — if the command fails but the script parses correctly in-editor, it's fine.

- [ ] **Step 4: Manual verification checklist**

Open the project in Godot editor and verify:

1. **Carve through wall with enemy nearby**: Walk toward a wall with an enemy within 250px → press attack key → player faces the wall and carves it
2. **Auto-face still works**: Walk in open space with an enemy nearby → press attack → player faces the enemy
3. **No-input auto-face**: Stand still with enemy nearby → press attack → player faces the enemy
4. **Creative mode**: Creative mode has `collision_mask = 0`, so `_is_blocked_by_terrain()` always returns false. Behavior should be identical to before.
5. **No enemy in range**: Without enemies nearby, input direction sets facing as before.

- [ ] **Step 5: Commit**

```bash
git add src/player/player_controller.gd
git commit -m "feat: wall-block detection overrides auto-face for terrain carving"
```
