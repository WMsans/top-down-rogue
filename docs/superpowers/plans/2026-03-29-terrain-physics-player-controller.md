# Terrain Physics & Player Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add marching-squares terrain collision and a top-down player controller with acceleration/friction movement.

**Architecture:** GPU terrain data is read back in a 64x64 region around the player, downsampled to a 16x16 binary grid, and fed through marching squares to produce collision polygons. A CharacterBody2D player with `move_and_slide()` collides against these polygons. WorldManager tracks the player for chunk loading and exposes a terrain query API.

**Tech Stack:** Godot 4.6, GDScript, RenderingDevice API, CharacterBody2D physics

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/marching_squares.gd` | Create | Pure algorithm: takes a 2D binary grid, returns arrays of polygon vertex lists |
| `scripts/terrain_collider.gd` | Create | Reads terrain from WorldManager, downsamples, runs marching squares, manages CollisionPolygon2D nodes |
| `scripts/player_controller.gd` | Create | CharacterBody2D movement with acceleration/friction |
| `scenes/player.tscn` | Create | Player scene: CharacterBody2D + CollisionShape2D + Sprite2D + Camera2D + TerrainCollider subtree |
| `scripts/world_manager.gd` | Modify | Add `read_terrain_region()`, `find_spawn_position()`, player reference, camera tracking |
| `scenes/main.tscn` | Modify | Remove Camera2D node, instance Player scene |
| `scripts/camera_controller.gd` | Delete | Replaced by Camera2D on the Player node |

---

### Task 1: Marching Squares Algorithm

**Files:**
- Create: `scripts/marching_squares.gd`

This is a pure-logic class with no scene dependencies. It takes a 2D array of booleans (solid/air) and returns an array of `PackedVector2Array` polygons.

- [ ] **Step 1: Create `scripts/marching_squares.gd` with the full algorithm**

```gdscript
class_name MarchingSquares
extends RefCounted

## Takes a 2D grid of booleans and returns polygon contours.
## grid_width/grid_height are the dimensions of the boolean grid.
## cell_size is the world-space size of each grid cell (used to scale output vertices).
## offset is the world-space position of the grid's top-left corner.

static func generate_polygons(grid: Array[bool], grid_width: int, grid_height: int, cell_size: float, offset: Vector2) -> Array[PackedVector2Array]:
	# Build edge segments from marching squares cases
	var segments: Array[Vector2] = [] # pairs of points: [start0, end0, start1, end1, ...]

	for y in range(grid_height - 1):
		for x in range(grid_width - 1):
			var tl := grid[y * grid_width + x]
			var tr := grid[y * grid_width + (x + 1)]
			var bl := grid[(y + 1) * grid_width + x]
			var br := grid[(y + 1) * grid_width + (x + 1)]

			var case_index := 0
			if tl: case_index |= 8
			if tr: case_index |= 4
			if br: case_index |= 2
			if bl: case_index |= 1

			var cx := float(x) * cell_size + offset.x
			var cy := float(y) * cell_size + offset.y

			var top := Vector2(cx + cell_size * 0.5, cy)
			var bottom := Vector2(cx + cell_size * 0.5, cy + cell_size)
			var left := Vector2(cx, cy + cell_size * 0.5)
			var right := Vector2(cx + cell_size, cy + cell_size * 0.5)

			match case_index:
				0, 15:
					pass # all air or all solid — no boundary
				1:
					segments.append_array([left, bottom])
				2:
					segments.append_array([bottom, right])
				3:
					segments.append_array([left, right])
				4:
					segments.append_array([right, top])
				5:
					# Saddle case: tl=0 tr=1 br=0 bl=1
					segments.append_array([left, top])
					segments.append_array([right, bottom])
				6:
					segments.append_array([bottom, top])
				7:
					segments.append_array([left, top])
				8:
					segments.append_array([top, left])
				9:
					segments.append_array([top, bottom])
				10:
					# Saddle case: tl=1 tr=0 br=1 bl=0
					segments.append_array([top, right])
					segments.append_array([bottom, left])
				11:
					segments.append_array([top, right])
				12:
					segments.append_array([right, left])
				13:
					segments.append_array([right, bottom])
				14:
					segments.append_array([bottom, left])

	return _chain_segments_into_polygons(segments)


static func _chain_segments_into_polygons(segments: Array[Vector2]) -> Array[PackedVector2Array]:
	if segments.is_empty():
		return []

	# Build adjacency: map each point to the segments that start/end there
	# segments are stored as pairs: [start0, end0, start1, end1, ...]
	var segment_count := segments.size() / 2
	var used := PackedByteArray()
	used.resize(segment_count)
	used.fill(0)

	var result: Array[PackedVector2Array] = []
	var epsilon := 0.01

	for i in range(segment_count):
		if used[i]:
			continue

		# Start a new chain from this segment
		var chain: PackedVector2Array = []
		chain.append(segments[i * 2])
		chain.append(segments[i * 2 + 1])
		used[i] = 1

		# Try to extend the chain by finding segments whose start matches our chain's end
		var changed := true
		while changed:
			changed = false
			var chain_end := chain[chain.size() - 1]
			for j in range(segment_count):
				if used[j]:
					continue
				var s_start := segments[j * 2]
				var s_end := segments[j * 2 + 1]
				if chain_end.distance_to(s_start) < epsilon:
					chain.append(s_end)
					used[j] = 1
					changed = true
					break
				elif chain_end.distance_to(s_end) < epsilon:
					chain.append(s_start)
					used[j] = 1
					changed = true
					break

		if chain.size() >= 3:
			result.append(chain)

	return result
```

- [ ] **Step 2: Verify the script loads without errors**

Run: Open the project in Godot editor. Check the Output panel for parse errors on `marching_squares.gd`.
Expected: No errors. `MarchingSquares` class is available globally.

- [ ] **Step 3: Commit**

```bash
git add scripts/marching_squares.gd
git commit -m "feat: add marching squares polygon generation algorithm"
```

---

### Task 2: Player Controller Script

**Files:**
- Create: `scripts/player_controller.gd`

Movement logic for a CharacterBody2D with acceleration, friction, and max speed.

- [ ] **Step 1: Create `scripts/player_controller.gd`**

```gdscript
extends CharacterBody2D

@export var max_speed: float = 120.0
@export var acceleration: float = 800.0
@export var friction: float = 600.0


func _physics_process(delta: float) -> void:
	var input_dir := _get_input_direction()

	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()


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
	return dir.normalized()
```

- [ ] **Step 2: Commit**

```bash
git add scripts/player_controller.gd
git commit -m "feat: add player controller with acceleration and friction"
```

---

### Task 3: Player Scene

**Files:**
- Create: `scenes/player.tscn`

Build the Player scene tree: CharacterBody2D root with CollisionShape2D, Sprite2D, Camera2D, and a TerrainCollider subtree (StaticBody2D placeholder — collision polygons added at runtime).

- [ ] **Step 1: Create `scenes/player.tscn`**

```
Player (CharacterBody2D)
  - script: res://scripts/player_controller.gd
  - collision_layer = 2 (player)
  - collision_mask = 1 (terrain)
  ├── CollisionShape2D
  │     - shape: RectangleShape2D(size = Vector2(10, 10))
  ├── Sprite2D
  │     - texture: null (use a simple colored rect via self_modulate or placeholder)
  │     - self_modulate: Color(0.2, 0.8, 0.3) (green)
  │     - region_enabled: false
  │     - Note: Create a 10x10 white placeholder texture or use a ColorRect approach
  ├── Camera2D
  │     - zoom: Vector2(8, 8)
  │     - position_smoothing_enabled: true
  │     - position_smoothing_speed: 10.0
  └── TerrainCollider (StaticBody2D)
        - script: res://scripts/terrain_collider.gd
        - collision_layer = 1 (terrain)
        - collision_mask = 0 (nothing — it's passive)
```

Since Godot `.tscn` files are complex to hand-write, create this scene programmatically or via the editor. If creating via script, use this approach:

Create a temporary script `tools/create_player_scene.gd` to build and save the scene, OR build the `.tscn` file directly:

```tscn
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/player_controller.gd" id="1"]
[ext_resource type="Script" path="res://scripts/terrain_collider.gd" id="2"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(10, 10)

[node name="Player" type="CharacterBody2D"]
collision_layer = 2
collision_mask = 1
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_1")

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.2, 0.8, 0.3, 1)
scale = Vector2(10, 10)

[node name="Camera2D" type="Camera2D" parent="."]
zoom = Vector2(8, 8)
position_smoothing_enabled = true
position_smoothing_speed = 10.0

[node name="TerrainCollider" type="StaticBody2D" parent="."]
collision_layer = 1
collision_mask = 0
script = ExtResource("2")
```

Note: The Sprite2D uses a scale of 10x10 on the default 1x1 white texture to create a visible 10x10 pixel square. If this doesn't render, create a small white PNG or use a `ColorRect` node instead.

- [ ] **Step 2: Verify the scene opens in the editor without errors**

Run: Open `scenes/player.tscn` in the Godot editor. Confirm the node tree matches the expected structure. Check for script parse errors.
Expected: Scene opens cleanly. All scripts attached. No errors in Output panel.

- [ ] **Step 3: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat: add player scene with collision, camera, and terrain collider"
```

---

### Task 4: Terrain Collider Script

**Files:**
- Create: `scripts/terrain_collider.gd`

This script lives on the TerrainCollider `StaticBody2D` under the Player. Each physics frame it checks if a rebuild is needed, reads terrain data from WorldManager, downsamples to a 16x16 grid, runs marching squares, and rebuilds `CollisionPolygon2D` children.

- [ ] **Step 1: Create `scripts/terrain_collider.gd`**

```gdscript
extends StaticBody2D

const READBACK_SIZE := 64
const GRID_SIZE := 16
const CELL_SIZE := 4.0  # READBACK_SIZE / GRID_SIZE = 4 pixels per cell
const REBUILD_THRESHOLD := 8.0  # pixels

var _last_rebuild_center := Vector2.INF
var _world_manager: Node2D


func _ready() -> void:
	# TerrainCollider is child of Player, which is child of Main
	# WorldManager is sibling of Player under Main
	_world_manager = get_node("/root/Main/WorldManager")
	top_level = true  # Don't inherit Player's transform — polygons are in world space


func _physics_process(_delta: float) -> void:
	var player_pos := get_parent().global_position  # Player's position

	if player_pos.distance_to(_last_rebuild_center) < REBUILD_THRESHOLD:
		return

	_rebuild_collision(player_pos)
	_last_rebuild_center = player_pos


func _rebuild_collision(center: Vector2) -> void:
	# Clear existing collision polygons
	for child in get_children():
		child.queue_free()

	# Read terrain region from WorldManager
	var region_data := _world_manager.read_terrain_region(center, READBACK_SIZE)
	if region_data.is_empty():
		return

	# Downsample to binary grid
	var grid := _downsample_to_grid(region_data)

	# Run marching squares
	var half_readback := READBACK_SIZE * 0.5
	var grid_offset := center - Vector2(half_readback, half_readback)
	var polygons := MarchingSquares.generate_polygons(grid, GRID_SIZE, GRID_SIZE, CELL_SIZE, grid_offset)

	# Create CollisionPolygon2D for each polygon
	for poly in polygons:
		if poly.size() < 3:
			continue
		var col := CollisionPolygon2D.new()
		col.polygon = poly
		add_child(col)


func _downsample_to_grid(region_data: PackedByteArray) -> Array[bool]:
	# region_data is READBACK_SIZE * READBACK_SIZE * 4 bytes (RGBA per pixel)
	# Downsample: each CELL_SIZE x CELL_SIZE block becomes one grid cell
	# A cell is solid if ANY pixel in the block has material != 0 (R channel != 0)
	var grid: Array[bool] = []
	grid.resize(GRID_SIZE * GRID_SIZE)
	grid.fill(false)

	var cell_px := int(CELL_SIZE)

	for gy in range(GRID_SIZE):
		for gx in range(GRID_SIZE):
			var solid := false
			for ly in range(cell_px):
				if solid:
					break
				for lx in range(cell_px):
					var px := gx * cell_px + lx
					var py := gy * cell_px + ly
					var idx := (py * READBACK_SIZE + px) * 4
					if region_data[idx] != 0:  # R channel = material, 0 = air
						solid = true
						break
			grid[gy * GRID_SIZE + gx] = solid

	return grid
```

- [ ] **Step 2: Verify the script loads without errors**

Run: Open the project in Godot editor. Check the Output panel for parse errors on `terrain_collider.gd`.
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/terrain_collider.gd
git commit -m "feat: add terrain collider with GPU readback and marching squares"
```

---

### Task 5: WorldManager — Terrain Region Readback API

**Files:**
- Modify: `scripts/world_manager.gd`

Add `read_terrain_region(center: Vector2, size: int) -> PackedByteArray` that reads pixel data from the GPU across chunk boundaries and returns a flat RGBA byte array.

- [ ] **Step 1: Add `read_terrain_region()` to `world_manager.gd`**

Add the following method at the bottom of the file, before the last line:

```gdscript
## Reads a square region of terrain pixel data centered on `center`.
## Returns a PackedByteArray of size*size*4 bytes (RGBA per pixel).
## Handles cross-chunk reads by sampling from adjacent chunks.
func read_terrain_region(center: Vector2, size: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(size * size * 4)
	result.fill(0)

	var half := size / 2
	var start_x := int(floor(center.x)) - half
	var start_y := int(floor(center.y)) - half

	# Cache chunk data reads to avoid reading the same chunk multiple times
	var chunk_data_cache: Dictionary = {}  # Vector2i -> PackedByteArray

	for py in range(size):
		for px in range(size):
			var wx := start_x + px
			var wy := start_y + py

			var chunk_coord := Vector2i(
				floori(float(wx) / CHUNK_SIZE),
				floori(float(wy) / CHUNK_SIZE)
			)

			if not chunks.has(chunk_coord):
				continue  # result already filled with 0 (air)

			if not chunk_data_cache.has(chunk_coord):
				var chunk: Chunk = chunks[chunk_coord]
				chunk_data_cache[chunk_coord] = rd.texture_get_data(chunk.rd_texture, 0)

			var data: PackedByteArray = chunk_data_cache[chunk_coord]
			var local_x := posmod(wx, CHUNK_SIZE)
			var local_y := posmod(wy, CHUNK_SIZE)
			var src_idx := (local_y * CHUNK_SIZE + local_x) * 4
			var dst_idx := (py * size + px) * 4

			result[dst_idx] = data[src_idx]        # R (material)
			result[dst_idx + 1] = data[src_idx + 1] # G (health)
			result[dst_idx + 2] = data[src_idx + 2] # B (temperature)
			result[dst_idx + 3] = data[src_idx + 3] # A (reserved)

	return result
```

- [ ] **Step 2: Verify no parse errors**

Run: Open the project in Godot editor. Check the Output panel.
Expected: No errors on `world_manager.gd`.

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add terrain region readback API to WorldManager"
```

---

### Task 6: WorldManager — Spawn Position Finder

**Files:**
- Modify: `scripts/world_manager.gd`

Add `find_spawn_position() -> Vector2` that scans the center chunk (0,0) for a cluster of air pixels large enough to fit the player.

- [ ] **Step 1: Add `find_spawn_position()` to `world_manager.gd`**

Add below `read_terrain_region()`:

```gdscript
## Finds a valid spawn position in the center chunk (0,0).
## Searches outward from the chunk center for a 12x12 air pocket (fits 10x10 player with margin).
func find_spawn_position() -> Vector2:
	var chunk_coord := Vector2i(0, 0)
	if not chunks.has(chunk_coord):
		push_warning("Center chunk not loaded, spawning at origin")
		return Vector2.ZERO

	var chunk: Chunk = chunks[chunk_coord]
	var data := rd.texture_get_data(chunk.rd_texture, 0)
	var pocket_size := 12  # pixels — must be fully air

	# Spiral search outward from chunk center
	var cx := CHUNK_SIZE / 2
	var cy := CHUNK_SIZE / 2

	for radius in range(0, CHUNK_SIZE / 2):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue  # only check perimeter of this radius ring
				var sx := cx + dx
				var sy := cy + dy
				if sx < 0 or sy < 0 or sx + pocket_size >= CHUNK_SIZE or sy + pocket_size >= CHUNK_SIZE:
					continue
				if _is_air_pocket(data, sx, sy, pocket_size):
					# Return world position at center of pocket
					return Vector2(
						chunk_coord.x * CHUNK_SIZE + sx + pocket_size / 2.0,
						chunk_coord.y * CHUNK_SIZE + sy + pocket_size / 2.0
					)

	push_warning("No valid spawn found, spawning at chunk center")
	return Vector2(cx, cy)


func _is_air_pocket(data: PackedByteArray, sx: int, sy: int, pocket_size: int) -> bool:
	for py in range(pocket_size):
		for px in range(pocket_size):
			var idx := ((sy + py) * CHUNK_SIZE + (sx + px)) * 4
			if data[idx] != MAT_AIR:
				return false
	return true
```

- [ ] **Step 2: Verify no parse errors**

Run: Open the project in Godot editor.
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add spawn position finder to WorldManager"
```

---

### Task 7: WorldManager — Player Integration & Camera Switch

**Files:**
- Modify: `scripts/world_manager.gd`
- Modify: `scenes/main.tscn`
- Delete: `scripts/camera_controller.gd`

Wire the player into the main scene. WorldManager tracks the player's position for chunk loading instead of the standalone Camera2D. Remove the old camera controller.

- [ ] **Step 1: Add player reference and update camera tracking in `world_manager.gd`**

Replace the `@onready var camera` line at the top of the file:

```gdscript
# Replace this line:
@onready var camera: Camera2D = get_parent().get_node("Camera2D")

# With:
var camera: Camera2D
```

Add a `setup_player()` method and modify `_ready()` to call it after initial chunk generation:

Add this method after `_init_material_textures()`:

```gdscript
var player: CharacterBody2D

func spawn_player() -> void:
	var player_scene := preload("res://scenes/player.tscn")
	player = player_scene.instantiate()
	get_parent().add_child(player)

	# Wait one frame for chunks to be generated, then find spawn position
	# (chunks are generated in _process, so we need at least one frame)
	await get_tree().process_frame
	await get_tree().process_frame  # second frame ensures GPU generation is dispatched

	var spawn_pos := find_spawn_position()
	player.global_position = spawn_pos

	camera = player.get_node("Camera2D")
```

Update `_ready()` to call `spawn_player()` after initialization (at the end of the non-editor branch):

```gdscript
func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_init_shaders()
	_init_dummy_texture()
	render_shader = preload("res://shaders/render_chunk.gdshader")
	_init_material_textures()
	if not Engine.is_editor_hint():
		spawn_player.call_deferred()
```

Add a guard in `_get_desired_chunks()` for when camera is null (before player spawns):

At the top of `_get_desired_chunks()`:

```gdscript
func _get_desired_chunks() -> Array[Vector2i]:
	if camera == null:
		# Before player spawns, load chunks around origin
		var result: Array[Vector2i] = []
		for x in range(-2, 3):
			for y in range(-2, 3):
				result.append(Vector2i(x, y))
		return result
	# ... rest of existing code unchanged
```

- [ ] **Step 2: Update `scenes/main.tscn` — remove the Camera2D node**

Remove the Camera2D node and its script reference from `main.tscn`. The Player scene (added at runtime by WorldManager) provides its own Camera2D.

In `main.tscn`, remove these lines:

```
[ext_resource type="Script" uid="uid://cvgqpuso1m1hn" path="res://scripts/camera_controller.gd" id="2"]
```

```
[node name="Camera2D" type="Camera2D" parent="." unique_id=1982148970]
zoom = Vector2(8, 8)
script = ExtResource("2")
```

Note: After removing the Camera2D ext_resource, the remaining ext_resource IDs in the `.tscn` file stay the same — Godot references them by their `id` string, not by order.

- [ ] **Step 3: Delete `scripts/camera_controller.gd`**

```bash
rm scripts/camera_controller.gd
```

- [ ] **Step 4: Update `scripts/input_handler.gd` to use the player's camera for mouse position**

The existing `input_handler.gd` calls `world_manager.get_global_mouse_position()`. This uses the viewport's canvas transform, which automatically follows the active Camera2D. Since the Player's Camera2D becomes the active camera, no code change is needed in `input_handler.gd` — `get_global_mouse_position()` will work correctly.

Verify: Read `scripts/input_handler.gd` and confirm it uses `get_global_mouse_position()` — it does (line 11). No change required.

- [ ] **Step 5: Run the game and verify**

Run: Launch the game from the Godot editor (F5).
Expected:
- Chunks generate around the origin
- Player spawns in an air pocket in the center chunk
- Camera follows the player
- WASD moves the player with acceleration/friction (slides to a stop)
- Player collides with stone/wood terrain (cannot walk through walls)
- Left-click still places fire
- No errors in Output panel

- [ ] **Step 6: Commit**

```bash
git add scripts/world_manager.gd scenes/main.tscn scripts/input_handler.gd
git rm scripts/camera_controller.gd
git commit -m "feat: integrate player into world — spawn, camera, chunk tracking"
```

---

## Summary of Commit Sequence

1. `feat: add marching squares polygon generation algorithm`
2. `feat: add player controller with acceleration and friction`
3. `feat: add player scene with collision, camera, and terrain collider`
4. `feat: add terrain collider with GPU readback and marching squares`
5. `feat: add terrain region readback API to WorldManager`
6. `feat: add spawn position finder to WorldManager`
7. `feat: integrate player into world — spawn, camera, chunk tracking`
