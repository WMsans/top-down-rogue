# Terrain Physics & Player Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add terrain collision via a CPU shadow grid (async GPU readback) and a top-down player controller with acceleration/friction movement.

**Architecture:** GPU chunk textures are read back into a 128x128 CPU-side byte array centered on the player. The player controller queries this shadow grid for solid pixels and resolves collisions axis-by-axis. The player is a plain Node2D — no Godot physics engine.

**Tech Stack:** GDScript, Godot 4.6, RenderingDevice API for GPU readback

---

## File Map

**New files:**
- `scripts/shadow_grid.gd` — CPU-side terrain mirror: stores material bytes, handles coordinate mapping, sync triggers, readback scheduling
- `scripts/player_controller.gd` — WASD input, acceleration/friction movement, axis-separated collision resolution against shadow grid
- `scenes/player.tscn` — Player scene: Node2D root + ColorRect (8x12) + Camera2D (zoom 8x)

**Modified files:**
- `scripts/world_manager.gd` — Add `read_region()`, `find_spawn_position()`, change chunk tracking from camera to player position
- `scenes/main.tscn` — Add Player node, remove standalone Camera2D node

**Removed files:**
- `scripts/camera_controller.gd` — Replaced by Camera2D as child of Player

---

### Task 1: Create ShadowGrid data structure

**Files:**
- Create: `scripts/shadow_grid.gd`

This task builds the shadow grid's storage, coordinate mapping, and query API — no sync logic yet (that comes in Task 3).

- [ ] **Step 1: Create `scripts/shadow_grid.gd` with storage and coordinate mapping**

```gdscript
class_name ShadowGrid
extends Node

## Size of the shadow grid in pixels (square). Configurable, default 128.
@export var grid_size: int = 128

## Distance from grid center before re-centering triggers a sync.
const RECENTER_THRESHOLD := 32

## Material constants (must match world_manager.gd / shaders)
const MAT_AIR := 0

var _data: PackedByteArray
## World position of the grid's top-left corner.
var _anchor: Vector2i = Vector2i.ZERO
## World position of the grid center at last sync.
var _last_sync_center: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_data = PackedByteArray()
	_data.resize(grid_size * grid_size)
	# Fill with solid (conservative default — treat unknown as impassable)
	_data.fill(255)


## Convert world coordinates to grid index. Returns -1 if out of bounds.
func _world_to_index(world_x: int, world_y: int) -> int:
	var lx: int = world_x - _anchor.x
	var ly: int = world_y - _anchor.y
	if lx < 0 or lx >= grid_size or ly < 0 or ly >= grid_size:
		return -1
	return ly * grid_size + lx


## Returns true if the pixel at (world_x, world_y) is solid (not air).
## Out-of-bounds queries return true (conservative).
func is_solid(world_x: int, world_y: int) -> bool:
	var idx := _world_to_index(world_x, world_y)
	if idx == -1:
		return true
	return _data[idx] != MAT_AIR


## Returns the material type byte at (world_x, world_y).
## Out-of-bounds queries return 255 (solid).
func get_material(world_x: int, world_y: int) -> int:
	var idx := _world_to_index(world_x, world_y)
	if idx == -1:
		return 255
	return _data[idx]


## Check if the grid should be re-centered around a new player position.
func needs_recenter(player_world_pos: Vector2i) -> bool:
	var dx: int = absi(player_world_pos.x - _last_sync_center.x)
	var dy: int = absi(player_world_pos.y - _last_sync_center.y)
	return dx > RECENTER_THRESHOLD or dy > RECENTER_THRESHOLD


## Update the anchor so the grid is centered on the given world position.
func set_center(center: Vector2i) -> void:
	_anchor = Vector2i(center.x - grid_size / 2, center.y - grid_size / 2)
	_last_sync_center = center


## Replace the grid data with new readback data. Called after GPU readback completes.
func apply_data(data: PackedByteArray) -> void:
	_data = data


## Returns the world-space Rect2i that this grid currently covers.
func get_world_rect() -> Rect2i:
	return Rect2i(_anchor, Vector2i(grid_size, grid_size))
```

- [ ] **Step 2: Verify the script parses**

Run: Open Godot editor or run from CLI:
```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No GDScript parse errors for `shadow_grid.gd`.

- [ ] **Step 3: Commit**

```bash
git add scripts/shadow_grid.gd
git commit -m "feat: add ShadowGrid data structure with coordinate mapping and queries"
```

---

### Task 2: Add WorldManager readback API

**Files:**
- Modify: `scripts/world_manager.gd`

Add a method that reads a rectangular region of material bytes from GPU chunk textures, spanning multiple chunks if needed. This is the bridge between GPU terrain and the CPU shadow grid.

- [ ] **Step 1: Add `read_region()` method to `scripts/world_manager.gd`**

Add this method at the bottom of the file, before the final closing (after the existing `get_chunk_container()` method):

```gdscript
## Read material bytes for a rectangular world region from GPU chunk textures.
## Returns a PackedByteArray of width*height bytes (one byte per pixel, material type).
## Pixels in unloaded chunks are returned as 255 (solid).
func read_region(region: Rect2i) -> PackedByteArray:
	var width: int = region.size.x
	var height: int = region.size.y
	var result := PackedByteArray()
	result.resize(width * height)
	result.fill(255)  # Default: solid for unloaded areas

	# Determine which chunks overlap this region
	var min_chunk := Vector2i(
		floori(float(region.position.x) / CHUNK_SIZE),
		floori(float(region.position.y) / CHUNK_SIZE)
	)
	var max_chunk := Vector2i(
		floori(float(region.end.x - 1) / CHUNK_SIZE),
		floori(float(region.end.y - 1) / CHUNK_SIZE)
	)

	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var chunk_coord := Vector2i(cx, cy)
			if not chunks.has(chunk_coord):
				continue

			var chunk: Chunk = chunks[chunk_coord]
			var chunk_data := rd.texture_get_data(chunk.rd_texture, 0)

			# World-space origin of this chunk
			var chunk_origin := chunk_coord * CHUNK_SIZE

			# Overlap between the requested region and this chunk
			var chunk_rect := Rect2i(chunk_origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			var overlap := region.intersection(chunk_rect)

			for y in range(overlap.position.y, overlap.end.y):
				for x in range(overlap.position.x, overlap.end.x):
					var local_x: int = x - chunk_origin.x
					var local_y: int = y - chunk_origin.y
					var chunk_idx: int = (local_y * CHUNK_SIZE + local_x) * 4  # RGBA8
					var material: int = chunk_data[chunk_idx]  # R channel = material type

					var result_x: int = x - region.position.x
					var result_y: int = y - region.position.y
					result[result_y * width + result_x] = material

	return result
```

- [ ] **Step 2: Verify the script parses**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add read_region() for GPU terrain readback"
```

---

### Task 3: Add spawn finder to WorldManager

**Files:**
- Modify: `scripts/world_manager.gd`

Add a method that scans terrain for a contiguous air pocket large enough to fit the player (8x12). Spiral-searches outward from a starting point.

- [ ] **Step 1: Add `find_spawn_position()` to `scripts/world_manager.gd`**

Add after the `read_region()` method:

```gdscript
## Find a spawn position by spiraling outward from search_origin.
## Looks for a contiguous air pocket that fits body_size.
## Returns the top-left corner of the pocket in world coordinates.
## Falls back to search_origin if no pocket found within max_radius.
func find_spawn_position(search_origin: Vector2i, body_size: Vector2i) -> Vector2i:
	var max_radius := CHUNK_SIZE * 4  # Search up to 4 chunks away
	var search_rect := Rect2i(
		search_origin - Vector2i(max_radius, max_radius),
		Vector2i(max_radius * 2, max_radius * 2)
	)
	var region_data := read_region(search_rect)
	var region_w: int = search_rect.size.x
	var region_h: int = search_rect.size.y

	# Spiral outward from center of the search region
	var center := Vector2i(max_radius, max_radius)
	var dir := Vector2i(1, 0)
	var pos := center
	var steps_in_leg := 1
	var steps_taken := 0
	var legs_completed := 0

	for _i in range(region_w * region_h):
		# Check if body_size fits at this position (all air)
		if _pocket_fits(region_data, region_w, region_h, pos, body_size):
			return search_rect.position + pos

		# Spiral step
		pos += dir
		steps_taken += 1
		if steps_taken >= steps_in_leg:
			steps_taken = 0
			legs_completed += 1
			# Rotate direction: right -> down -> left -> up
			dir = Vector2i(-dir.y, dir.x)
			if legs_completed % 2 == 0:
				steps_in_leg += 1

	push_warning("ShadowGrid: No valid spawn pocket found, falling back to search_origin")
	return search_origin


func _pocket_fits(data: PackedByteArray, region_w: int, region_h: int, top_left: Vector2i, size: Vector2i) -> bool:
	if top_left.x < 0 or top_left.y < 0:
		return false
	if top_left.x + size.x > region_w or top_left.y + size.y > region_h:
		return false
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			if data[y * region_w + x] != MAT_AIR:
				return false
	return true
```

- [ ] **Step 2: Verify the script parses**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add find_spawn_position() with spiral search"
```

---

### Task 4: Create player controller with movement (no collision yet)

**Files:**
- Create: `scripts/player_controller.gd`
- Create: `scenes/player.tscn`

Build the player scene and movement script. Collision is added in Task 5 — this task gets WASD movement with acceleration/friction working first.

- [ ] **Step 1: Create `scripts/player_controller.gd`**

```gdscript
class_name PlayerController
extends Node2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var velocity: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	var input_dir := _get_input_direction()
	_apply_movement(input_dir, delta)
	position += velocity * delta


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	return dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO


func _apply_movement(input_dir: Vector2, delta: float) -> void:
	if input_dir != Vector2.ZERO:
		velocity += input_dir * acceleration * delta
	else:
		var friction_amount: float = friction * delta
		if velocity.length() <= friction_amount:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity.normalized() * friction_amount
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
```

- [ ] **Step 2: Create `scenes/player.tscn`**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/player_controller.gd" id="1"]

[node name="Player" type="Node2D"]
script = ExtResource("1")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -4
offset_top = -6
offset_right = 4
offset_bottom = 6
color = Color(0.2, 0.8, 0.3, 1)

[node name="Camera2D" type="Camera2D" parent="."]
zoom = Vector2(8, 8)
position_smoothing_enabled = true
position_smoothing_speed = 12.0
```

- [ ] **Step 3: Verify the script and scene parse**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/player_controller.gd scenes/player.tscn
git commit -m "feat: add player controller with acceleration/friction movement"
```

---

### Task 5: Add collision resolution to player controller

**Files:**
- Modify: `scripts/player_controller.gd`

Add axis-separated collision resolution using the ShadowGrid. The player checks its 8x12 footprint against solid pixels and clamps position when overlapping.

- [ ] **Step 1: Add shadow grid reference and collision to `scripts/player_controller.gd`**

Replace the `_physics_process` method and add the collision methods. The full updated file:

```gdscript
class_name PlayerController
extends Node2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var velocity: Vector2 = Vector2.ZERO
var shadow_grid: ShadowGrid

## Collision state — available for gameplay mechanics.
var is_on_floor: bool = false
var is_on_wall_left: bool = false
var is_on_wall_right: bool = false
var is_on_ceiling: bool = false


func _physics_process(delta: float) -> void:
	if shadow_grid == null:
		return
	var input_dir := _get_input_direction()
	_apply_movement(input_dir, delta)
	_move_and_collide(delta)
	_update_contact_state()


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	return dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO


func _apply_movement(input_dir: Vector2, delta: float) -> void:
	if input_dir != Vector2.ZERO:
		velocity += input_dir * acceleration * delta
	else:
		var friction_amount: float = friction * delta
		if velocity.length() <= friction_amount:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity.normalized() * friction_amount
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed


func _move_and_collide(delta: float) -> void:
	# Player origin is center of the body. Compute top-left from position.
	var half_w: int = BODY_WIDTH / 2   # 4
	var half_h: int = BODY_HEIGHT / 2  # 6

	# --- Resolve X axis ---
	var new_x: float = position.x + velocity.x * delta
	var test_left: int = int(floor(new_x)) - half_w
	var test_top: int = int(floor(position.y)) - half_h
	if velocity.x > 0:
		# Check right edge
		var edge_x: int = test_left + BODY_WIDTH  # one pixel past right side
		if _column_has_solid(edge_x, test_top, BODY_HEIGHT):
			new_x = float(edge_x - BODY_WIDTH + half_w) - 0.001
			velocity.x = 0
	elif velocity.x < 0:
		# Check left edge
		if _column_has_solid(test_left, test_top, BODY_HEIGHT):
			new_x = float(test_left + 1 + half_w)
			velocity.x = 0

	# --- Resolve Y axis ---
	var new_y: float = position.y + velocity.y * delta
	test_left = int(floor(new_x)) - half_w
	var test_top_y: int = int(floor(new_y)) - half_h
	if velocity.y > 0:
		# Check bottom edge
		var edge_y: int = test_top_y + BODY_HEIGHT
		if _row_has_solid(test_left, edge_y, BODY_WIDTH):
			new_y = float(edge_y - BODY_HEIGHT + half_h) - 0.001
			velocity.y = 0
	elif velocity.y < 0:
		# Check top edge
		if _row_has_solid(test_left, test_top_y, BODY_WIDTH):
			new_y = float(test_top_y + 1 + half_h)
			velocity.y = 0

	position = Vector2(new_x, new_y)


## Check if any pixel in a vertical column is solid.
func _column_has_solid(world_x: int, world_y_start: int, height: int) -> bool:
	for y in range(world_y_start, world_y_start + height):
		if shadow_grid.is_solid(world_x, y):
			return true
	return false


## Check if any pixel in a horizontal row is solid.
func _row_has_solid(world_x_start: int, world_y: int, width: int) -> bool:
	for x in range(world_x_start, world_x_start + width):
		if shadow_grid.is_solid(x, world_y):
			return true
	return false


## Sample adjacent pixels for contact state (available for future gameplay).
func _update_contact_state() -> void:
	var half_w: int = BODY_WIDTH / 2
	var half_h: int = BODY_HEIGHT / 2
	var left: int = int(floor(position.x)) - half_w
	var top: int = int(floor(position.y)) - half_h

	is_on_floor = _row_has_solid(left, top + BODY_HEIGHT, BODY_WIDTH)
	is_on_ceiling = _row_has_solid(left, top - 1, BODY_WIDTH)
	is_on_wall_left = _column_has_solid(left - 1, top, BODY_HEIGHT)
	is_on_wall_right = _column_has_solid(left + BODY_WIDTH, top, BODY_HEIGHT)
```

- [ ] **Step 2: Verify the script parses**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/player_controller.gd
git commit -m "feat: add axis-separated collision resolution to player controller"
```

---

### Task 6: Wire ShadowGrid sync to WorldManager

**Files:**
- Modify: `scripts/shadow_grid.gd`

Add the async sync logic: event-driven triggers (player movement, terrain dirty) with a frequency cap of 3 frames. The ShadowGrid calls WorldManager's `read_region()` and applies the result on the next frame.

- [ ] **Step 1: Add sync logic to `scripts/shadow_grid.gd`**

Add these properties after the existing variable declarations:

```gdscript
## Reference to WorldManager — set by the player controller during setup.
var world_manager: Node2D

## Sync scheduling state
var _sync_pending: bool = false
var _readback_pending: bool = false
var _pending_data: PackedByteArray
var _frames_since_last_sync: int = 0
var _dirty: bool = false
const MIN_SYNC_INTERVAL := 3  # Minimum frames between syncs
```

Add this method to handle per-frame sync scheduling (add after `get_world_rect()`):

```gdscript
## Called each physics frame by the player controller.
## Handles async two-phase readback: request on frame N, apply on frame N+1.
func update_sync(player_world_pos: Vector2i) -> void:
	_frames_since_last_sync += 1

	# Phase 2: apply pending readback data from previous frame
	if _readback_pending:
		apply_data(_pending_data)
		_pending_data = PackedByteArray()
		_readback_pending = false
		_frames_since_last_sync = 0

	# Phase 1: check if we need to request a new readback
	var should_sync: bool = _dirty or needs_recenter(player_world_pos)
	if should_sync and _frames_since_last_sync >= MIN_SYNC_INTERVAL and not _sync_pending:
		set_center(player_world_pos)
		_request_readback()


func _request_readback() -> void:
	if world_manager == null:
		return
	_sync_pending = true
	# Perform the GPU readback (synchronous call, but only happens every few frames)
	_pending_data = world_manager.read_region(get_world_rect())
	_sync_pending = false
	_readback_pending = true
	_dirty = false


## Called by WorldManager when terrain changes in a chunk that overlaps this grid.
func mark_dirty() -> void:
	_dirty = true


## Force an immediate sync (used for initial spawn).
func force_sync(center: Vector2i) -> void:
	if world_manager == null:
		return
	set_center(center)
	var data := world_manager.read_region(get_world_rect())
	apply_data(data)
	_frames_since_last_sync = 0
	_dirty = false
```

- [ ] **Step 2: Verify the script parses**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/shadow_grid.gd
git commit -m "feat: add async sync logic to ShadowGrid with frequency cap"
```

---

### Task 7: Add terrain dirty notification to WorldManager

**Files:**
- Modify: `scripts/world_manager.gd`

After simulation runs each frame, check if any simulated chunks overlap the shadow grid's bounds. If so, mark the shadow grid dirty. Also add a signal for this and switch chunk tracking from camera to a settable position.

- [ ] **Step 1: Add player tracking and dirty notification to `scripts/world_manager.gd`**

Replace the `camera` onready variable and add shadow grid tracking. At the top of the file, replace:

```gdscript
@onready var chunk_container: Node2D = $ChunkContainer
@onready var camera: Camera2D = get_parent().get_node("Camera2D")
```

with:

```gdscript
@onready var chunk_container: Node2D = $ChunkContainer

## The position used for chunk loading/unloading. Set by the player controller.
var tracking_position: Vector2 = Vector2.ZERO
## Reference to the shadow grid for dirty notifications. Set by the player controller.
var shadow_grid: ShadowGrid
```

In `_get_desired_chunks()`, replace the camera references. Change:

```gdscript
func _get_desired_chunks() -> Array[Vector2i]:
	var vp_size := get_viewport().get_visible_rect().size
	var cam_pos := camera.global_position
	var cam_zoom := camera.zoom
	var half_view := vp_size / (2.0 * cam_zoom)

	var min_chunk := Vector2i(
		floori((cam_pos.x - half_view.x) / CHUNK_SIZE) - 1,
		floori((cam_pos.y - half_view.y) / CHUNK_SIZE) - 1
	)
	var max_chunk := Vector2i(
		floori((cam_pos.x + half_view.x) / CHUNK_SIZE) + 1,
		floori((cam_pos.y + half_view.y) / CHUNK_SIZE) + 1
	)
```

to:

```gdscript
func _get_desired_chunks() -> Array[Vector2i]:
	var vp_size := get_viewport().get_visible_rect().size
	# Use zoom from any Camera2D in the tree, default to 8x
	var cam := get_viewport().get_camera_2d()
	var cam_zoom := cam.zoom if cam else Vector2(8, 8)
	var half_view := vp_size / (2.0 * cam_zoom)

	var min_chunk := Vector2i(
		floori((tracking_position.x - half_view.x) / CHUNK_SIZE) - 1,
		floori((tracking_position.y - half_view.y) / CHUNK_SIZE) - 1
	)
	var max_chunk := Vector2i(
		floori((tracking_position.x + half_view.x) / CHUNK_SIZE) + 1,
		floori((tracking_position.y + half_view.y) / CHUNK_SIZE) + 1
	)
```

At the end of `_run_simulation()`, add dirty notification. After the existing `rd.compute_list_end()` line, add:

```gdscript
	# Notify shadow grid if any simulated chunk overlaps its bounds
	if shadow_grid:
		var grid_rect := shadow_grid.get_world_rect()
		for coord in chunks:
			var chunk_rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
			if grid_rect.intersects(chunk_rect):
				shadow_grid.mark_dirty()
				break
```

- [ ] **Step 2: Verify the script parses**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add player tracking and shadow grid dirty notification"
```

---

### Task 8: Integrate everything into main scene

**Files:**
- Modify: `scripts/player_controller.gd` — add `_ready()` for spawn and wiring
- Modify: `scenes/main.tscn` — add Player, remove Camera2D
- Remove: `scripts/camera_controller.gd`

- [ ] **Step 1: Add `_ready()` to `scripts/player_controller.gd` for spawn and wiring**

Add this at the top of the class, after the variable declarations and before `_physics_process`:

```gdscript
@onready var _world_manager: Node2D = get_parent().get_node("WorldManager")


func _ready() -> void:
	# Create and configure the shadow grid
	shadow_grid = ShadowGrid.new()
	shadow_grid.world_manager = _world_manager
	add_child(shadow_grid)

	# Wire world manager to track this player
	_world_manager.tracking_position = global_position
	_world_manager.shadow_grid = shadow_grid

	# Wait one frame for chunks to generate, then find spawn and sync
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos := _world_manager.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	shadow_grid.force_sync(Vector2i(position))
```

Also add tracking position update at the end of `_physics_process`, after `_update_contact_state()`:

```gdscript
	# Update world manager tracking position for chunk loading
	_world_manager.tracking_position = global_position
	# Update shadow grid sync
	shadow_grid.update_sync(Vector2i(int(floor(position.x)), int(floor(position.y))))
```

- [ ] **Step 2: Update `scenes/main.tscn`**

Replace the entire file with the updated scene that includes Player and removes the standalone Camera2D:

```
[gd_scene format=3 uid="uid://dsytrqtiu7drc"]

[ext_resource type="Script" uid="uid://dbbimgkhcuwvu" path="res://scripts/world_manager.gd" id="1"]
[ext_resource type="Script" uid="uid://bn2f13as3veks" path="res://scripts/input_handler.gd" id="3"]
[ext_resource type="Script" uid="uid://fawu47fhsxos" path="res://scripts/debug_manager.gd" id="4"]
[ext_resource type="Script" uid="uid://dpx6ctk67xl0e" path="res://scripts/chunk_grid_overlay.gd" id="5"]
[ext_resource type="Script" uid="uid://cwpvprev001" path="res://scripts/world_preview.gd" id="6"]
[ext_resource type="PackedScene" path="res://scenes/player.tscn" id="7"]

[node name="Main" type="Node2D" unique_id=194821170]

[node name="WorldManager" type="Node2D" parent="." unique_id=1684191940]
script = ExtResource("1")

[node name="ChunkContainer" type="Node2D" parent="WorldManager" unique_id=241049915]

[node name="WorldPreview" type="Node2D" parent="WorldManager" unique_id=613443267]
script = ExtResource("6")
preview_size = 1
world_seed = 56

[node name="Player" parent="." instance=ExtResource("7")]

[node name="InputHandler" type="Node" parent="." unique_id=924507179]
script = ExtResource("3")

[node name="DebugManager" type="Node2D" parent="." unique_id=993138986]
visible = false
script = ExtResource("4")

[node name="ChunkGridOverlay" type="Node2D" parent="DebugManager" unique_id=2077171302]
script = ExtResource("5")
```

- [ ] **Step 3: Delete `scripts/camera_controller.gd`**

```bash
git rm scripts/camera_controller.gd
```

- [ ] **Step 4: Update `scripts/input_handler.gd` to use viewport camera**

The input handler currently gets `world_manager.get_global_mouse_position()` which already uses the viewport's camera transform. Since the Camera2D is now on the Player, this should work without changes. Verify by reading the file — if it references the old Camera2D node directly, update it. The current code uses `world_manager.get_global_mouse_position()` which is fine.

- [ ] **Step 5: Verify everything parses and run the project**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -10
```
Expected: No parse errors.

Then run the project to verify:
- Player spawns in an air pocket
- WASD moves the player with acceleration/friction feel
- Player collides with terrain (stone, wood) and cannot pass through
- Camera follows the player
- Chunks load/unload based on player position
- Fire placement still works on click

- [ ] **Step 6: Commit**

```bash
git add scripts/player_controller.gd scenes/player.tscn scenes/main.tscn scripts/input_handler.gd
git commit -m "feat: integrate player, shadow grid, and collision into main scene"
```

---

### Task 9: Fix debug manager camera reference

**Files:**
- Modify: `scripts/debug_manager.gd`
- Modify: `scripts/chunk_grid_overlay.gd`

These scripts may reference the old Camera2D node path. Update them to use the viewport's camera.

- [ ] **Step 1: Check and update debug scripts**

Read `scripts/debug_manager.gd` and `scripts/chunk_grid_overlay.gd`. If either references `get_parent().get_node("Camera2D")` or a hardcoded path to the old Camera2D, update it to use `get_viewport().get_camera_2d()`.

For `chunk_grid_overlay.gd`, if it uses camera position for drawing chunk boundaries, change the camera reference from a node path to `get_viewport().get_camera_2d()`.

- [ ] **Step 2: Verify and run**

```bash
cd /home/jeremy/Development/Godot/top-down-rogue && timeout 30 godot --headless --quit 2>&1 | tail -5
```
Expected: No parse errors. Debug overlay (F3) still works.

- [ ] **Step 3: Commit**

```bash
git add scripts/debug_manager.gd scripts/chunk_grid_overlay.gd
git commit -m "fix: update debug scripts to use viewport camera"
```
