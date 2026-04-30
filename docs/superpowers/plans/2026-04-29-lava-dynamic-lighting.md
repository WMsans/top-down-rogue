# Lava Dynamic Lighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make lava (and any future emissive material with `glow > 0`) cast a soft, world-space orange glow on nearby terrain and entities, without per-pixel `PointLight2D` nodes and without GPU→CPU readbacks.

**Architecture:** A new autoload `LightingManager` runs three compute passes every 4 frames over the loaded chunks: (1) per-chunk emission reduce — downsample each chunk's RGBA8 cell texture into a 64×64 RGBA16F emission tile by summing `MATERIAL_TINT[m] * MATERIAL_GLOW[m]` over each 4×4 block; (2) compose tiles into a single light grid texture sized to the loaded-chunk AABB; (3) separable Gaussian blur. The blurred grid is exposed as a global canvas shader parameter and sampled by a fullscreen additive `ColorRect` overlay placed above the Light2D-lit world layer.

**Tech Stack:** Godot 4.6, GDScript, low-level `RenderingDevice` compute (RDShaderFile / RDUniform / compute_list), GLSL 450, gdUnit4 tests.

**Spec:** `docs/superpowers/specs/2026-04-29-lava-dynamic-lighting-design.md`

---

## File map

**Create:**
- `src/autoload/lighting_manager.gd` — autoload orchestrator. Owns compute pipelines, per-chunk emission tile RIDs, main grid + scratch RIDs, and the tick loop.
- `shaders/compute/emission_reduce.glsl` — per-chunk 4×4 emission reduce.
- `shaders/compute/light_compose.glsl` — chunk emission tile → main grid blit.
- `shaders/compute/light_blur.glsl` — separable Gaussian (horizontal/vertical via push constant).
- `src/core/lighting_overlay.gd` + `scenes/lighting_overlay.tscn` — `ColorRect` on a `CanvasLayer` running the additive overlay shader.
- `shaders/canvas/light_overlay.gdshader` — additive overlay shader sampling the global `light_grid_tex`.
- `src/console/commands/lighting_command.gd` — `lighting <on|off>` console command.
- `tests/unit/test_lighting_manager.gd` — unit tests for non-GPU helpers (AABB math, emitter helper).

**Modify:**
- `project.godot` — register `LightingManager` autoload (after `GameModeManager`).
- `src/core/chunk_manager.gd` — call `LightingManager.register_chunk` from `create_chunk` and `LightingManager.unregister_chunk` from `unload_chunk`.
- `src/autoload/material_registry.gd` — add `is_emitter(material_id) -> bool`.
- `src/autoload/console_manager.gd` — register `LightingCommands` in `_register_commands`.
- `scenes/game.tscn` — instance `lighting_overlay.tscn` as a child above the main viewport content.

**No changes:**
- `tools/generate_material_glsl.gd` already emits `MATERIAL_TINT[]` and `MATERIAL_GLOW[]`. The new compute shader includes `shaders/generated/materials.glslinc` and reads them directly.

---

## Conventions used by existing compute pipelines

The plan's GLSL and GDScript follow patterns established in `src/core/compute_device.gd` and `shaders/compute/simulation.glsl`:

- Chunk cell format is `RGBA8`; material id is `int(round(p.r * 255.0))`. Use `get_material(pixel)` from `shaders/include/sim/common.glslinc` if convenient (but emission_reduce can inline it to avoid pulling unrelated sim helpers).
- Compute shaders are loaded with `load("res://shaders/compute/X.glsl") as RDShaderFile`, then `rd.shader_create_from_spirv(file.get_spirv())`.
- Uniform sets are created against a specific shader and a specific `set` index. The set layout in the compute shader must match.
- Push constants are 16-byte aligned `PackedByteArray`s.

---

### Task 1: Bootstrap LightingManager autoload (skeleton)

**Files:**
- Create: `src/autoload/lighting_manager.gd`
- Modify: `project.godot` (autoload list)

- [ ] **Step 1: Write the file**

```gdscript
# src/autoload/lighting_manager.gd
@tool
extends Node

@export var enabled: bool = true
@export var tick_interval: int = 4
@export var intensity_k: float = 1.0
@export var blur_radius_cells: int = 5
@export var ambient: Color = Color(0.05, 0.05, 0.05)

const CELL_SIZE: int = 4
const CHUNK_SIZE: int = 256  # mirrors src/core/chunk_manager.gd
const TILE_SIZE: int = CHUNK_SIZE / CELL_SIZE  # 64

var rd: RenderingDevice
var _frame_counter: int = 0

func _ready() -> void:
	rd = RenderingServer.get_rendering_device()

func _process(_delta: float) -> void:
	if not enabled:
		return
	_frame_counter += 1
	if _frame_counter < tick_interval:
		return
	_frame_counter = 0
	_tick()

func _tick() -> void:
	pass  # filled in by later tasks

func register_chunk(_chunk) -> void:
	pass

func unregister_chunk(_chunk) -> void:
	pass
```

- [ ] **Step 2: Register the autoload in project.godot**

In `project.godot`, under `[autoload]`, append after the `GameModeManager` line:

```
LightingManager="*res://src/autoload/lighting_manager.gd"
```

- [ ] **Step 3: Run the editor / smoke check**

Run: `godot --headless --quit-after 30` from the project root.
Expected: no parse errors. The line `LightingManager` does not need to print anything yet.

- [ ] **Step 4: Commit**

```bash
git add src/autoload/lighting_manager.gd project.godot
git commit -m "feat(lighting): bootstrap LightingManager autoload skeleton"
```

---

### Task 2: `is_emitter` helper + unit test

**Files:**
- Modify: `src/autoload/material_registry.gd`
- Create: `tests/unit/test_lighting_manager.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_lighting_manager.gd`:

```gdscript
extends GdUnitTestSuite

func test_is_emitter_true_for_lava() -> void:
	assert_that(MaterialRegistry.is_emitter(MaterialRegistry.MAT_LAVA)).is_true()

func test_is_emitter_false_for_air() -> void:
	assert_that(MaterialRegistry.is_emitter(MaterialRegistry.MAT_AIR)).is_false()

func test_is_emitter_false_for_water() -> void:
	assert_that(MaterialRegistry.is_emitter(MaterialRegistry.MAT_WATER)).is_false()

func test_is_emitter_false_for_invalid_id() -> void:
	assert_that(MaterialRegistry.is_emitter(-1)).is_false()
	assert_that(MaterialRegistry.is_emitter(99999)).is_false()
```

- [ ] **Step 2: Run test, expect failure**

Run: `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_lighting_manager.gd`
Expected: failures — `is_emitter` does not exist on MaterialRegistry.

- [ ] **Step 3: Implement helper**

In `src/autoload/material_registry.gd`, append after the existing `get_glow` function:

```gdscript
func is_emitter(material_id: int) -> bool:
	return get_glow(material_id) > 0.0
```

Note: `get_glow` already returns 1.0 (default) for invalid ids — that's a non-zero default. Adjust by guarding bounds first:

```gdscript
func is_emitter(material_id: int) -> bool:
	if material_id < 0 or material_id >= materials.size():
		return false
	return materials[material_id].glow > 0.0
```

- [ ] **Step 4: Re-run test, expect pass**

Same command. All four assertions pass.

- [ ] **Step 5: Commit**

```bash
git add src/autoload/material_registry.gd tests/unit/test_lighting_manager.gd
git commit -m "feat(lighting): add MaterialRegistry.is_emitter helper"
```

---

### Task 3: emission_reduce compute shader + pipeline init

**Files:**
- Create: `shaders/compute/emission_reduce.glsl`
- Modify: `src/autoload/lighting_manager.gd`

- [ ] **Step 1: Write the GLSL**

```glsl
// shaders/compute/emission_reduce.glsl
#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

const int CELL_SIZE = 4;
const int TILE_SIZE = 64;        // CHUNK_SIZE / CELL_SIZE, mirror in CPU
const int CHUNK_SIZE = 256;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) readonly uniform image2D chunk_tex;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D emission_tile;

void main() {
	ivec2 tile_pos = ivec2(gl_GlobalInvocationID.xy);
	if (tile_pos.x >= TILE_SIZE || tile_pos.y >= TILE_SIZE) return;

	vec3 sum = vec3(0.0);
	ivec2 base = tile_pos * CELL_SIZE;
	for (int dy = 0; dy < CELL_SIZE; ++dy) {
		for (int dx = 0; dx < CELL_SIZE; ++dx) {
			vec4 p = imageLoad(chunk_tex, base + ivec2(dx, dy));
			int m = int(round(p.r * 255.0));
			if (m < 0 || m >= MAT_COUNT) continue;
			float g = MATERIAL_GLOW[m];
			if (g <= 0.0) continue;
			sum += MATERIAL_TINT[m].rgb * g;
		}
	}
	// Divide by 16 so a fully-emissive 4x4 block reads as plain `tint * glow`,
	// not 16x. The `intensity_k` global multiplier lives in the overlay shader.
	imageStore(emission_tile, tile_pos, vec4(sum / 16.0, 1.0));
}
```

- [ ] **Step 2: Add pipeline initialization in LightingManager**

In `src/autoload/lighting_manager.gd`, add at the top of the file:

```gdscript
var emission_shader: RID
var emission_pipeline: RID
```

Replace `_ready` with:

```gdscript
func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_error("LightingManager: no RenderingDevice; disabling")
		enabled = false
		return
	_init_pipelines()

func _init_pipelines() -> void:
	var emission_file := load("res://shaders/compute/emission_reduce.glsl") as RDShaderFile
	emission_shader = rd.shader_create_from_spirv(emission_file.get_spirv())
	emission_pipeline = rd.compute_pipeline_create(emission_shader)
```

Add a free path:

```gdscript
func _exit_tree() -> void:
	if rd == null:
		return
	if emission_pipeline.is_valid():
		rd.free_rid(emission_pipeline)
	if emission_shader.is_valid():
		rd.free_rid(emission_shader)
```

- [ ] **Step 3: Smoke run**

Run: `godot --headless --quit-after 30`
Expected: no GLSL compile errors printed; `MATERIAL_TINT[]` and `MATERIAL_GLOW[]` resolve correctly because `materials.glslinc` is included.

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/emission_reduce.glsl src/autoload/lighting_manager.gd
git commit -m "feat(lighting): emission reduce compute shader + pipeline init"
```

---

### Task 4: Per-chunk emission tile lifecycle

**Files:**
- Modify: `src/autoload/lighting_manager.gd`
- Modify: `src/core/chunk_manager.gd`

- [ ] **Step 1: Implement tile RID alloc / free in LightingManager**

Add to `src/autoload/lighting_manager.gd`:

```gdscript
# Vector2i chunk_coord -> RID emission_tile_tex
var emission_tiles: Dictionary = {}

func register_chunk(chunk) -> void:
	if rd == null or not enabled:
		return
	if emission_tiles.has(chunk.coord):
		return
	var tf := RDTextureFormat.new()
	tf.width = TILE_SIZE
	tf.height = TILE_SIZE
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var tex := rd.texture_create(tf, RDTextureView.new())
	emission_tiles[chunk.coord] = tex

func unregister_chunk(chunk) -> void:
	if rd == null:
		return
	var tex_var = emission_tiles.get(chunk.coord, null)
	if tex_var == null:
		return
	var tex: RID = tex_var
	if tex.is_valid():
		rd.free_rid(tex)
	emission_tiles.erase(chunk.coord)
```

Update `_exit_tree` to also free tiles:

```gdscript
func _exit_tree() -> void:
	if rd == null:
		return
	for tex in emission_tiles.values():
		if tex.is_valid():
			rd.free_rid(tex)
	emission_tiles.clear()
	if emission_pipeline.is_valid():
		rd.free_rid(emission_pipeline)
	if emission_shader.is_valid():
		rd.free_rid(emission_shader)
```

- [ ] **Step 2: Hook into chunk_manager**

In `src/core/chunk_manager.gd`, locate `create_chunk` (line ~46) and at the very end of the function, after the chunk is fully constructed and inserted into `world_manager.chunks`, append:

```gdscript
	LightingManager.register_chunk(chunk)
```

In `unload_chunk` (line ~117), at the start of the function (before any RID frees), insert:

```gdscript
	LightingManager.unregister_chunk(world_manager.chunks[coord])
```

In `clear_all_chunks` (line ~222), inside the loop before `chunks.clear()`, insert:

```gdscript
	for coord in chunks:
		LightingManager.unregister_chunk(chunks[coord])
```

(Place it before the existing free loop so tiles are freed before chunk RIDs go away.)

- [ ] **Step 3: Smoke run**

Run: `godot --headless` and load into the game scene briefly, then quit. Expected: no errors about leaked RIDs at shutdown for emission tiles.

- [ ] **Step 4: Commit**

```bash
git add src/autoload/lighting_manager.gd src/core/chunk_manager.gd
git commit -m "feat(lighting): per-chunk emission tile lifecycle"
```

---

### Task 5: Dispatch emission_reduce per loaded chunk

**Files:**
- Modify: `src/autoload/lighting_manager.gd`

- [ ] **Step 1: Implement dispatch loop**

Add to `src/autoload/lighting_manager.gd`:

```gdscript
func _dispatch_emission_reduce() -> void:
	# Walk world_manager.chunks; dispatch one reduce per chunk.
	var world_manager = get_node_or_null("/root/Main")
	if world_manager == null:
		return
	var chunks: Dictionary = world_manager.chunks
	if chunks.is_empty():
		return

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, emission_pipeline)

	var groups := TILE_SIZE / 8  # 64/8 = 8

	# Track uniform sets to free after dispatch (Godot pattern from compute_device).
	var created_sets: Array[RID] = []

	for coord in chunks:
		var chunk = chunks[coord]
		var tile_var = emission_tiles.get(coord, null)
		if tile_var == null:
			continue
		var tile_rid: RID = tile_var

		var u_chunk := RDUniform.new()
		u_chunk.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_chunk.binding = 0
		u_chunk.add_id(chunk.rd_texture)

		var u_tile := RDUniform.new()
		u_tile.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_tile.binding = 1
		u_tile.add_id(tile_rid)

		var set_rid := rd.uniform_set_create([u_chunk, u_tile], emission_shader, 0)
		created_sets.append(set_rid)
		rd.compute_list_bind_uniform_set(compute_list, set_rid, 0)
		rd.compute_list_dispatch(compute_list, groups, groups, 1)

	rd.compute_list_end()

	# Free transient uniform sets next frame (the chunk_manager pattern).
	# Simplest: free immediately after end — RD defers if still in flight.
	for s in created_sets:
		rd.free_rid(s)
```

Note: the `world_manager` lookup uses the path `/root/Main` matching `scenes/game.tscn`'s root node. If the scene tree node name differs in the running game, adjust to the actual path.

Wire it into `_tick`:

```gdscript
func _tick() -> void:
	if rd == null:
		return
	_dispatch_emission_reduce()
```

- [ ] **Step 2: Visual sanity check (manual)**

Run the game. The visible behavior is unchanged (no overlay yet), but with `--rendering-driver vulkan` logs enabled the dispatch should run without validation errors. To confirm the reduce produced data, temporarily insert at the end of `_tick`:

```gdscript
	# DEBUG: print one tile's center pixel
	for coord in emission_tiles:
		var data := rd.texture_get_data(emission_tiles[coord], 0)
		# RGBA16F: 4 floats per pixel * 8 bytes; pick center pixel
		var center := (TILE_SIZE / 2) * TILE_SIZE + (TILE_SIZE / 2)
		var off := center * 8
		# Minimal: just print byte length; if zero on chunks with no lava, that's expected.
		print("tile ", coord, " bytes=", data.size())
		break
```

Use the `lava` console command (already exists per `world_manager.place_lava`) to drop lava into a chunk and verify a non-zero center byte pattern after the next tick. Remove the debug print after verifying.

- [ ] **Step 3: Commit**

```bash
git add src/autoload/lighting_manager.gd
git commit -m "feat(lighting): dispatch emission_reduce per loaded chunk"
```

---

### Task 6: Loaded-chunk AABB + main grid + scratch textures

**Files:**
- Modify: `src/autoload/lighting_manager.gd`

- [ ] **Step 1: Compute AABB and (re)allocate grid textures**

Add to `src/autoload/lighting_manager.gd`:

```gdscript
var main_grid_tex: RID
var scratch_grid_tex: RID
var loaded_aabb: Rect2i = Rect2i()  # in chunk coords; size in chunks
var grid_size: Vector2i = Vector2i.ZERO  # in light-grid cells

const MAX_GRID_CELLS: int = 1024 * 1024  # safety cap

func _compute_loaded_aabb() -> Rect2i:
	if emission_tiles.is_empty():
		return Rect2i()
	var any_set := false
	var min_c := Vector2i.ZERO
	var max_c := Vector2i.ZERO
	for coord_v in emission_tiles.keys():
		var coord: Vector2i = coord_v
		if not any_set:
			min_c = coord
			max_c = coord
			any_set = true
		else:
			min_c.x = min(min_c.x, coord.x)
			min_c.y = min(min_c.y, coord.y)
			max_c.x = max(max_c.x, coord.x)
			max_c.y = max(max_c.y, coord.y)
	# +1 because max is inclusive
	return Rect2i(min_c, max_c - min_c + Vector2i.ONE)

func _ensure_grid_textures() -> bool:
	var aabb := _compute_loaded_aabb()
	if aabb.size == Vector2i.ZERO:
		return false
	if aabb == loaded_aabb and main_grid_tex.is_valid():
		return true
	# Reallocate
	_free_grid_textures()
	loaded_aabb = aabb
	grid_size = Vector2i(aabb.size.x * TILE_SIZE, aabb.size.y * TILE_SIZE)
	if grid_size.x * grid_size.y > MAX_GRID_CELLS:
		push_warning("LightingManager: grid size %s exceeds cap; skipping" % grid_size)
		grid_size = Vector2i.ZERO
		return false
	var tf := RDTextureFormat.new()
	tf.width = grid_size.x
	tf.height = grid_size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	)
	main_grid_tex = rd.texture_create(tf, RDTextureView.new())
	scratch_grid_tex = rd.texture_create(tf, RDTextureView.new())
	return true

func _free_grid_textures() -> void:
	if main_grid_tex.is_valid():
		rd.free_rid(main_grid_tex)
		main_grid_tex = RID()
	if scratch_grid_tex.is_valid():
		rd.free_rid(scratch_grid_tex)
		scratch_grid_tex = RID()
```

Update `_exit_tree` to free grid textures:

```gdscript
	_free_grid_textures()
```

Update `_tick`:

```gdscript
func _tick() -> void:
	if rd == null:
		return
	if not _ensure_grid_textures():
		return
	_dispatch_emission_reduce()
```

- [ ] **Step 2: Smoke run**

Run the game, walk around so chunks load/unload. Watch for "grid size exceeds cap" — should not appear for a normal 5×5 window (320×320 cells = 102400, well under cap).

- [ ] **Step 3: Commit**

```bash
git add src/autoload/lighting_manager.gd
git commit -m "feat(lighting): loaded-chunk AABB tracking + grid texture allocation"
```

---

### Task 7: light_compose shader + dispatch

**Files:**
- Create: `shaders/compute/light_compose.glsl`
- Modify: `src/autoload/lighting_manager.gd`

- [ ] **Step 1: Write the GLSL**

```glsl
// shaders/compute/light_compose.glsl
// Copies one chunk's emission tile into the corresponding region of the main grid.
#[compute]
#version 450

const int TILE_SIZE = 64;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) readonly uniform image2D src_tile;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D dst_grid;

layout(push_constant, std430) uniform PushConstants {
	int dst_x;
	int dst_y;
	int _pad0;
	int _pad1;
} pc;

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	if (local.x >= TILE_SIZE || local.y >= TILE_SIZE) return;
	vec4 v = imageLoad(src_tile, local);
	imageStore(dst_grid, ivec2(pc.dst_x, pc.dst_y) + local, v);
}
```

- [ ] **Step 2: Add pipeline + dispatch**

In `src/autoload/lighting_manager.gd`, alongside `emission_*`, add:

```gdscript
var compose_shader: RID
var compose_pipeline: RID
```

Extend `_init_pipelines`:

```gdscript
	var compose_file := load("res://shaders/compute/light_compose.glsl") as RDShaderFile
	compose_shader = rd.shader_create_from_spirv(compose_file.get_spirv())
	compose_pipeline = rd.compute_pipeline_create(compose_shader)
```

Extend `_exit_tree` to free compose RIDs (mirror the emission pattern).

Add the dispatch helper:

```gdscript
func _dispatch_compose() -> void:
	if not main_grid_tex.is_valid():
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, compose_pipeline)
	var groups := TILE_SIZE / 8
	var created_sets: Array[RID] = []

	for coord_v in emission_tiles.keys():
		var coord: Vector2i = coord_v
		var tile_rid: RID = emission_tiles[coord]
		var dst := (coord - loaded_aabb.position) * TILE_SIZE

		var u_src := RDUniform.new()
		u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_src.binding = 0
		u_src.add_id(tile_rid)

		var u_dst := RDUniform.new()
		u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_dst.binding = 1
		u_dst.add_id(main_grid_tex)

		var set_rid := rd.uniform_set_create([u_src, u_dst], compose_shader, 0)
		created_sets.append(set_rid)

		var pc := PackedByteArray()
		pc.resize(16)
		pc.encode_s32(0, dst.x)
		pc.encode_s32(4, dst.y)

		rd.compute_list_bind_uniform_set(compute_list, set_rid, 0)
		rd.compute_list_set_push_constant(compute_list, pc, pc.size())
		rd.compute_list_dispatch(compute_list, groups, groups, 1)

	rd.compute_list_end()
	for s in created_sets:
		rd.free_rid(s)
```

Wire into `_tick`:

```gdscript
func _tick() -> void:
	if rd == null:
		return
	if not _ensure_grid_textures():
		return
	_dispatch_emission_reduce()
	_dispatch_compose()
```

- [ ] **Step 3: Smoke run**

Run the game, drop lava via console, watch the validation log for compute errors. No visible change yet (overlay still missing).

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/light_compose.glsl src/autoload/lighting_manager.gd
git commit -m "feat(lighting): light_compose shader + dispatch"
```

---

### Task 8: Separable Gaussian blur

**Files:**
- Create: `shaders/compute/light_blur.glsl`
- Modify: `src/autoload/lighting_manager.gd`

- [ ] **Step 1: Write the GLSL**

```glsl
// shaders/compute/light_blur.glsl
// Separable 11-tap Gaussian, direction selected by push constant.
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) readonly uniform image2D src;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D dst;

layout(push_constant, std430) uniform PushConstants {
	int width;
	int height;
	int dir_x;   // (1,0) for horizontal, (0,1) for vertical
	int dir_y;
} pc;

// 11-tap Gaussian, sigma ~= 2.5 cells (radius 5).
const float W[11] = float[11](
	0.009167, 0.020298, 0.039771, 0.069041, 0.105991,
	0.143464,
	0.105991, 0.069041, 0.039771, 0.020298, 0.009167
);

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.width || p.y >= pc.height) return;
	ivec2 dir = ivec2(pc.dir_x, pc.dir_y);
	vec3 sum = vec3(0.0);
	for (int i = -5; i <= 5; ++i) {
		ivec2 q = p + dir * i;
		q.x = clamp(q.x, 0, pc.width - 1);
		q.y = clamp(q.y, 0, pc.height - 1);
		sum += imageLoad(src, q).rgb * W[i + 5];
	}
	imageStore(dst, p, vec4(sum, 1.0));
}
```

- [ ] **Step 2: Add pipeline + dispatch**

In `src/autoload/lighting_manager.gd`, alongside other shader RIDs:

```gdscript
var blur_shader: RID
var blur_pipeline: RID
```

Extend `_init_pipelines` and `_exit_tree` mirroring earlier shaders.

Add the dispatch:

```gdscript
func _dispatch_blur() -> void:
	if not main_grid_tex.is_valid():
		return
	var groups_x := (grid_size.x + 7) / 8
	var groups_y := (grid_size.y + 7) / 8

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, blur_pipeline)
	var created_sets: Array[RID] = []

	# Horizontal pass: main -> scratch
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(main_grid_tex)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(scratch_grid_tex)
	var s0 := rd.uniform_set_create([u0, u1], blur_shader, 0)
	created_sets.append(s0)

	var pc_h := PackedByteArray()
	pc_h.resize(16)
	pc_h.encode_s32(0, grid_size.x)
	pc_h.encode_s32(4, grid_size.y)
	pc_h.encode_s32(8, 1)
	pc_h.encode_s32(12, 0)
	rd.compute_list_bind_uniform_set(compute_list, s0, 0)
	rd.compute_list_set_push_constant(compute_list, pc_h, pc_h.size())
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)

	# Barrier to ensure horizontal pass completes before vertical reads scratch
	rd.compute_list_add_barrier(compute_list)

	# Vertical pass: scratch -> main
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u2.binding = 0
	u2.add_id(scratch_grid_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u3.binding = 1
	u3.add_id(main_grid_tex)
	var s1 := rd.uniform_set_create([u2, u3], blur_shader, 0)
	created_sets.append(s1)

	var pc_v := PackedByteArray()
	pc_v.resize(16)
	pc_v.encode_s32(0, grid_size.x)
	pc_v.encode_s32(4, grid_size.y)
	pc_v.encode_s32(8, 0)
	pc_v.encode_s32(12, 1)
	rd.compute_list_bind_uniform_set(compute_list, s1, 0)
	rd.compute_list_set_push_constant(compute_list, pc_v, pc_v.size())
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)

	rd.compute_list_end()
	for s in created_sets:
		rd.free_rid(s)
```

Note: between compose (which writes main_grid_tex) and the horizontal blur (which reads it), there's an implicit barrier from `compute_list_end` + new `compute_list_begin`. Inside the blur compute list we add an explicit barrier between H and V. That's enough.

Wire into `_tick`:

```gdscript
func _tick() -> void:
	if rd == null:
		return
	if not _ensure_grid_textures():
		return
	_dispatch_emission_reduce()
	_dispatch_compose()
	_dispatch_blur()
```

- [ ] **Step 3: Smoke run**

Run the game, drop lava, no errors. Still no visible glow (overlay not yet wired).

- [ ] **Step 4: Commit**

```bash
git add shaders/compute/light_blur.glsl src/autoload/lighting_manager.gd
git commit -m "feat(lighting): separable Gaussian blur compute pass"
```

---

### Task 9: Expose grid as global canvas shader uniforms

**Files:**
- Modify: `src/autoload/lighting_manager.gd`

- [ ] **Step 1: Wrap main_grid_tex with Texture2DRD and publish global params**

Add to `src/autoload/lighting_manager.gd`:

```gdscript
var main_grid_2d: Texture2DRD

func _publish_grid_globals() -> void:
	# Wrap rd_texture for canvas shader use; recreate when texture identity changes.
	if main_grid_2d == null:
		main_grid_2d = Texture2DRD.new()
	main_grid_2d.texture_rd_rid = main_grid_tex
	RenderingServer.global_shader_parameter_set("light_grid_tex", main_grid_2d)

	# World-space rect covered by the grid:
	var origin_px := Vector2(loaded_aabb.position) * float(CHUNK_SIZE)
	var size_px := Vector2(loaded_aabb.size) * float(CHUNK_SIZE)
	RenderingServer.global_shader_parameter_set(
		"light_grid_world_rect",
		Vector4(origin_px.x, origin_px.y, size_px.x, size_px.y),
	)
	RenderingServer.global_shader_parameter_set("light_intensity_k", intensity_k)
	RenderingServer.global_shader_parameter_set("light_ambient", Vector3(ambient.r, ambient.g, ambient.b))
```

Register the global params at startup. In `_ready`, after `_init_pipelines`:

```gdscript
	_register_global_params()

func _register_global_params() -> void:
	# Idempotent: only add if missing.
	if not ProjectSettings.has_setting("shader_globals/light_grid_tex"):
		# Define via ProjectSettings so persistence survives editor sessions.
		# At runtime, simply set defaults via RenderingServer to avoid editing
		# project.godot at runtime.
		pass
	RenderingServer.global_shader_parameter_set("light_grid_tex", null)
	RenderingServer.global_shader_parameter_set("light_grid_world_rect", Vector4(0, 0, 0, 0))
	RenderingServer.global_shader_parameter_set("light_intensity_k", intensity_k)
	RenderingServer.global_shader_parameter_set("light_ambient", Vector3(ambient.r, ambient.g, ambient.b))
```

The global parameters must be declared in `project.godot` so canvas shaders can reference them. Add to `project.godot` under a new `[shader_globals]` section:

```
[shader_globals]

light_grid_tex={
"type": "sampler2D",
"value": ""
}
light_grid_world_rect={
"type": "vec4",
"value": Vector4(0, 0, 0, 0)
}
light_intensity_k={
"type": "float",
"value": 1.0
}
light_ambient={
"type": "vec3",
"value": Vector3(0.05, 0.05, 0.05)
}
```

Wire into `_tick`:

```gdscript
func _tick() -> void:
	if rd == null:
		return
	if not _ensure_grid_textures():
		return
	_dispatch_emission_reduce()
	_dispatch_compose()
	_dispatch_blur()
	_publish_grid_globals()
```

- [ ] **Step 2: Smoke run**

Run the game. No visual change yet, but `RenderingServer.global_shader_parameter_get("light_grid_world_rect")` after a few seconds should return a non-zero rect (verify via a one-line debug print if needed; remove after).

- [ ] **Step 3: Commit**

```bash
git add src/autoload/lighting_manager.gd project.godot
git commit -m "feat(lighting): publish grid texture + world rect as global shader params"
```

---

### Task 10: Overlay shader + scene + wire into game

**Files:**
- Create: `shaders/canvas/light_overlay.gdshader`
- Create: `src/core/lighting_overlay.gd`
- Create: `scenes/lighting_overlay.tscn`
- Modify: `scenes/game.tscn`

- [ ] **Step 1: Write the canvas shader**

```glsl
// shaders/canvas/light_overlay.gdshader
shader_type canvas_item;
render_mode blend_add, unshaded;

global uniform sampler2D light_grid_tex : filter_linear, repeat_disable;
global uniform vec4 light_grid_world_rect;  // (origin.xy, size.xy) in world pixels
global uniform float light_intensity_k;
global uniform vec3 light_ambient;

void fragment() {
	// Convert SCREEN_UV -> world-space pixel using the canvas transform.
	// CANVAS_MATRIX maps world -> canvas; we need its inverse.
	vec2 screen_px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 world_px = (inverse(CANVAS_MATRIX) * vec4(screen_px, 0.0, 1.0)).xy;

	vec2 rel = world_px - light_grid_world_rect.xy;
	vec2 grid_uv = rel / light_grid_world_rect.zw;

	vec3 lit = light_ambient;
	if (all(greaterThanEqual(grid_uv, vec2(0.0))) && all(lessThan(grid_uv, vec2(1.0)))) {
		lit += texture(light_grid_tex, grid_uv).rgb * light_intensity_k;
	}
	COLOR = vec4(lit, 1.0);
}
```

Note: if `inverse(CANVAS_MATRIX)` doesn't yield correct world coords in your viewport setup, fall back to using `SCREEN_TO_WORLD` derivation via a custom uniform set from the camera each frame. Verify in Step 4.

- [ ] **Step 2: Write the overlay node script**

```gdscript
# src/core/lighting_overlay.gd
extends ColorRect

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# Cover whole viewport
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Material is set in the .tscn
```

- [ ] **Step 3: Build the scene file**

Create `scenes/lighting_overlay.tscn` (use the editor or write the .tscn manually). Minimum structure:

- Root: `CanvasLayer` named `LightingOverlay`, `layer = 1` (above the world's default layer 0, below UI which is on higher layers in your existing setup).
  - Child: `ColorRect` named `Overlay` with the script `src/core/lighting_overlay.gd` attached, anchors full rect, `mouse_filter = 2` (ignore), and a `ShaderMaterial` whose shader is `shaders/canvas/light_overlay.gdshader`.

- [ ] **Step 4: Instance the overlay in game.tscn**

Open `scenes/game.tscn` and add an instance of `lighting_overlay.tscn` as a child of the root `Main` node. Place it in the tree such that it draws above the world `SubViewportContainer` content but below `CurrencyHUD` and `ConsoleManager`.

- [ ] **Step 5: Visual smoke test**

Run the game.
- In a dark cave with no lava: screen should be near-black with only the player carry-light visible (ambient ~0.05 bumps things slightly).
- Use the console to spawn lava (`spawn_mat lava` or whatever the existing command is — see `src/console/commands/spawn_mat_command.gd`). A soft orange glow should appear within ~2 cells of the lava, fading smoothly.
- If the glow appears glued to the screen instead of the world (i.e., it doesn't move when you pan the camera), the `inverse(CANVAS_MATRIX)` derivation is wrong; replace it by adding a `uniform vec2 camera_world_origin; uniform vec2 viewport_size_px;` in the shader, set both from `_process` in the overlay script using `get_viewport().get_camera_2d()` and `get_viewport().get_visible_rect()`, and compute `world_px = camera_world_origin + (SCREEN_UV - 0.5) * viewport_size_px`.

- [ ] **Step 6: Commit**

```bash
git add shaders/canvas/light_overlay.gdshader src/core/lighting_overlay.gd scenes/lighting_overlay.tscn scenes/game.tscn
git commit -m "feat(lighting): additive overlay shader + scene wired into game"
```

---

### Task 11: `lighting <on|off>` console command

**Files:**
- Create: `src/console/commands/lighting_command.gd`
- Modify: `src/autoload/console_manager.gd`

- [ ] **Step 1: Write the command**

```gdscript
# src/console/commands/lighting_command.gd
extends RefCounted

static func register(registry: CommandRegistry) -> void:
	registry.register("lighting", "Toggle dynamic lava lighting (on/off)", _lighting)

static func _lighting(args: Array[String], _ctx: Dictionary) -> String:
	if args.is_empty():
		return "Lighting is %s" % ("on" if LightingManager.enabled else "off")
	var arg := args[0].to_lower()
	if arg == "on":
		LightingManager.enabled = true
		return "Lighting on"
	if arg == "off":
		LightingManager.enabled = false
		return "Lighting off"
	return "error: expected 'on' or 'off'"
```

- [ ] **Step 2: Register in console_manager**

In `src/autoload/console_manager.gd::_register_commands`, append:

```gdscript
	var LightingCommands := preload("res://src/console/commands/lighting_command.gd")
	LightingCommands.register(_registry)
```

- [ ] **Step 3: Manual test**

Run the game, open the console (your existing keybind), run `lighting off` — overlay should hide / lighting should freeze. `lighting on` restores it.

Note: when toggling off, the overlay still draws (it just samples whatever was last in `light_grid_tex`). For a cleaner off behavior, also gate the overlay material visibility — extend the overlay `_process` to read `LightingManager.enabled` and toggle `visible`. Add to `src/core/lighting_overlay.gd`:

```gdscript
func _process(_delta: float) -> void:
	visible = LightingManager.enabled
```

- [ ] **Step 4: Commit**

```bash
git add src/console/commands/lighting_command.gd src/autoload/console_manager.gd src/core/lighting_overlay.gd
git commit -m "feat(lighting): lighting on/off console command"
```

---

### Task 12: Visual smoke test pass + perf check

**Files:**
- Create: `docs/superpowers/specs/2026-04-29-lava-dynamic-lighting-testing.md`

- [ ] **Step 1: Write the test checklist**

```markdown
# Lava Dynamic Lighting — Manual Test Checklist

Run the game in a fresh world. For each item, note PASS / FAIL.

1. **Empty cave, no lava** — screen at ambient floor (~0.05); player carry-light visible.
2. **Single lava pixel** — orange smudge ~5 cells across, soft falloff, no hard square edges.
3. **Lava pool** — surrounding stone visibly orange-tinted within ~half a tile, fading to black further out.
4. **Falling lava blob** — glow follows falling cells without gaps; source area dims as lava leaves.
5. **Player walks past lava** — carry-light + lava glow sum naturally; no banding or double-darkening.
6. **Camera pan** — glow stays glued to world position; no swimming/lag beyond the 4-frame tick step.
7. **Toggle off/on** — `lighting off` hides overlay instantly; `lighting on` restores.
8. **Chunk unload** — walk far away from a lava pool until its chunks unload; the glow disappears cleanly with no residue.
9. **Chunk reload** — walk back; glow reappears within ≤4 frames (~67 ms).
10. **Console spawn at chunk boundary** — spawn lava on a chunk boundary; glow renders continuously across the boundary (no seam).

## Perf

Open the Godot profiler. With a typical 5×5 chunk window and a few hundred lava pixels:
- `_tick()` cost should be <1 ms (sub-millisecond GPU dispatches).
- Per-frame cost outside ticks: just the overlay shader; should be negligible.

Record numbers in commit message.
```

- [ ] **Step 2: Run the checklist**

Walk through items 1–10 in-game. For any FAIL, file the symptom; if it's a small fix (e.g., world-coord derivation in the overlay shader), fix inline before committing the checklist.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-04-29-lava-dynamic-lighting-testing.md
git commit -m "docs(lighting): manual test checklist + perf pass"
```

---

## Self-review notes

**Spec coverage:** Every requirement in the design's "Requirements" table maps to a task: B (overlay design), light grid (Tasks 6–10), R1 cell size (Task 3 constant), U3 tick interval (Task 1 frame counter), K3 Gaussian (Task 8), E2 loaded chunks (Task 6 AABB), I2/X1 overlay (Tasks 9–10), C1 tint × glow (Task 3 GLSL), HDR (RGBA16F throughout), ambient (Task 9 globals), Light2D coexistence (Task 10 overlay layer above world).

**G1 amendment:** Tasks 3–8 implement the GPU pipeline; CPU walking is not used anywhere.

**Type/name consistency:** `TILE_SIZE = 64`, `CELL_SIZE = 4`, `CHUNK_SIZE = 256` mirrored between GDScript and GLSL. Globals named `light_grid_tex`, `light_grid_world_rect`, `light_intensity_k`, `light_ambient` are used identically in Task 9 (writer), `project.godot` (declaration), and Task 10 (shader).

**Known fragile points** (flagged inline for the implementer):
- Task 5: `world_manager` lookup path `/root/Main` matches `scenes/game.tscn`; verify before relying on it.
- Task 10 Step 5: `inverse(CANVAS_MATRIX)` may not give world coords in this viewport-shrink setup; fallback path provided.
- Transient uniform sets are freed immediately after `compute_list_end`. The existing pattern in `compute_device.gd` does the same; if Godot complains about freeing in-flight RIDs, defer freeing one frame.
