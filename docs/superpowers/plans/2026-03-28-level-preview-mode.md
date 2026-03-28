# Level Preview Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add editor preview mode for world generation with n×n chunk generation from world origin.

**Architecture:** WorldPreview node (with@tool) calls WorldManager's public API to generate chunks without simulation. EditorPlugin provides inspector UI with buttons.

**Tech Stack:** GDScript, Godot 4.6, RenderingDevice API

---

## File Structure

| File | Purpose |
|------|---------|
| `scripts/world_manager.gd` | Add public API methods, skip sim in editor |
| `scripts/world_preview.gd` | New @tool script for preview functionality |
| `addons/level_preview/plugin.cfg` | Plugin configuration |
| `addons/level_preview/level_preview_plugin.gd` | EditorPlugin + InspectorPlugin combined |
| `project.godot` | Register editor plugin |

---

### Task1: Add Public API to WorldManager

**Files:**
- Modify: `scripts/world_manager.gd`

- [ ] **Step 1: Add editor check in _process**

Modify `_process` to skip simulation when running in editor:

```gdscript
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_chunks()
	_run_simulation()
```

- [ ] **Step 2: Add generate_chunks_at method**

Add after`get_active_chunk_coords()`:

```gdscript
func generate_chunks_at(coords: Array[Vector2i], seed_val: int) -> void:
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()

	var new_chunks: Array[Vector2i] = []
	for coord in coords:
		if not chunks.has(coord):
			_create_chunk(coord)
			new_chunks.append(coord)

	if new_chunks.is_empty():
		return

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, gen_pipeline)
	for coord in new_chunks:
		var chunk: Chunk = chunks[coord]
		var gen_uniform := RDUniform.new()
		gen_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		gen_uniform.binding = 0
		gen_uniform.add_id(chunk.rd_texture)
		var uniform_set := rd.uniform_set_create([gen_uniform], gen_shader, 0)
		_gen_uniform_sets_to_free.append(uniform_set)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

		var push_data := PackedByteArray()
		push_data.resize(16)
		push_data.encode_s32(0, coord.x)
		push_data.encode_s32(4, coord.y)
		push_data.encode_u32(8, seed_val)
		push_data.encode_u32(12, 0)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())

		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
	rd.compute_list_end()

	_rebuild_sim_uniform_sets(new_chunks, [])
```

- [ ] **Step 3: Add clear_all_chunks method**

Add after `generate_chunks_at`:

```gdscript
func clear_all_chunks() -> void:
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		_free_chunk_resources(chunk)
	chunks.clear()
	for us in _gen_uniform_sets_to_free:
		rd.free_rid(us)
	_gen_uniform_sets_to_free.clear()
```

- [ ] **Step 4: Add get_chunk_container method**

Add after `clear_all_chunks`:

```gdscript
func get_chunk_container() -> Node2D:
	return chunk_container
```

- [ ] **Step 5: Commit changes**

```bash
git add scripts/world_manager.gd
git commit -m "feat: add public API for chunk generation to WorldManager"
```

---

### Task 2: Create WorldPreview @tool Script

**Files:**
- Create: `scripts/world_preview.gd`

- [ ] **Step 1: Create WorldPreview script**

Create `scripts/world_preview.gd`:

```gdscript
@tool
class_name WorldPreview
extends Node2D

@export var preview_size: int = 3
@export var world_seed: int = 0

var _world_manager: Node2D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_find_world_manager()


func _find_world_manager() -> void:
	var parent = get_parent()
	if parent and parent.has_method("generate_chunks_at"):
		_world_manager = parent


func generate_preview() -> void:
	if not _is_ready():
		return

	_world_manager.clear_all_chunks()

	var coords: Array[Vector2i] = []
	for x in range(-preview_size, preview_size + 1):
		for y in range(-preview_size, preview_size + 1):
			coords.append(Vector2i(x, y))

	_world_manager.generate_chunks_at(coords, world_seed)


func clear_preview() -> void:
	if not _is_ready():
		return

	_world_manager.clear_all_chunks()


func _is_ready() -> bool:
	if _world_manager == null:
		_find_world_manager()
	return _world_manager != null
```

- [ ] **Step 2: Commit changes**

```bash
git add scripts/world_preview.gd
git commit -m "feat: add WorldPreview @tool script for editor preview"
```

---

### Task 3: Create Editor Plugin

**Files:**
- Create: `addons/level_preview/plugin.cfg`
- Create: `addons/level_preview/level_preview_plugin.gd`

- [ ] **Step 1: Create plugin.cfg**

Create `addons/level_preview/plugin.cfg`:

```ini
[plugin]

name="LevelPreview"
description="Editor preview for world generation"
author="TopDownRogue"
version="1.0"
script="level_preview_plugin.gd"
```

- [ ] **Step 2: Create level_preview_plugin.gd**

Create `addons/level_preview/level_preview_plugin.gd`:

```gdscript
@tool
extends EditorPlugin


var _inspector_plugin: EditorInspectorPlugin
var _last_selected_preview: WorldPreview = null


func _enter_tree() -> void:
	_inspector_plugin = WorldPreviewInspectorPlugin.new()
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)


func _handles(object: Object) -> bool:
	return object is WorldPreview


func _edit(object: Object) -> void:
	var preview := object as WorldPreview
	if preview == null:
		if _last_selected_preview and is_instance_valid(_last_selected_preview):
			_last_selected_preview.clear_preview()
		_last_selected_preview = null
	else:
		_last_selected_preview = preview


class WorldPreviewInspectorPlugin extends EditorInspectorPlugin:
	func _can_handle(object: Object) -> bool:
		return object is WorldPreview


	func _parse_begin(object: Object) -> void:
		var preview := object as WorldPreview
		if not preview:
			return

		var vbox := VBoxContainer.new()

		var generate_btn := Button.new()
		generate_btn.text = "Generate Preview"
		generate_btn.pressed.connect(_on_generate_pressed.bind(preview))
		vbox.add_child(generate_btn)

		var clear_btn := Button.new()
		clear_btn.text = "Clear Preview"
		clear_btn.pressed.connect(_on_clear_pressed.bind(preview))
		vbox.add_child(clear_btn)

		add_custom_control(vbox)


	func _on_generate_pressed(preview: WorldPreview) -> void:
		preview.generate_preview()


	func _on_clear_pressed(preview: WorldPreview) -> void:
		preview.clear_preview()
```

- [ ] **Step 3: Commit changes**

```bash
git add addons/level_preview/
git commit -m "feat: add LevelPreview editor plugin with inspector buttons"
```

---

### Task 4: Register Plugin in Project

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Add plugin configuration section**

Add to `project.godot` after the `[rendering]` section:

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/level_preview/plugin.cfg")
```

- [ ] **Step 2: Commit changes**

```bash
git add project.godot
git commit -m "chore: register LevelPreview editor plugin"
```

---

### Task 5: Add WorldPreview Node to Scene

**Files:**
- Modify: `scenes/main.tscn`

This task must be done after Task 2, when Godot has imported the script and generated its UID file.

- [ ] **Step 1: Read the generated UID**

After Task 2, Godot will have created `scripts/world_preview.gd.uid`. Read its contents to get the actual UID.

- [ ] **Step 2: Modify main.tscn**

Add the ext_resource and node entry to `scenes/main.tscn`. Add after the last `ext_resource` line (line 5):

```
[ext_resource type="Script" uid="<UID_FROM_STEP1>" path="res://scripts/world_preview.gd" id="6"]
```

Then add after the ChunkContainer node section (after line 14), as a child of WorldManager:

```
[node name="WorldPreview" type="Node2D" parent="WorldManager"]
script = ExtResource("6")
```

- [ ] **Step 3: Commit changes**

```bash
git add scenes/main.tscn
git commit -m "feat: add WorldPreview node to WorldManager"
```