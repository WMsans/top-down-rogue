# Interactable & Drop System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an interactable system with white-outline highlighting, pushable drops with topdown physics, and weapon drops that grant weapons on pickup.

**Architecture:** Component composition — `Interactable` node component, `InteractionController` on player with Area2D detection, `Drop` as RigidBody2D with physics push, `WeaponDrop` extending `Drop` with weapon-granting logic. Outline effect via a canvas_item shader toggled by `outline_width` parameter.

**Tech Stack:** Godot 4.6, GDScript, shader (canvas_item)

---

### Task 1: Create Outline Shader

**Files:**
- Create: `shaders/visual/outline.gdshader`

- [ ] **Step 1: Write the outline shader**

Create `shaders/visual/outline.gdshader`:

```glsl
shader_type canvas_item;

uniform float outline_width : hint_range(0.0, 10.0) = 0.0;
uniform Color outline_color : source_color = Color(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 base_color = texture(TEXTURE, UV);

	if (outline_width > 0.0) {
		vec2 pixel_size = TEXTURE_PIXEL_SIZE * outline_width;
		float max_alpha = 0.0;

		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(pixel_size.x, 0.0)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(0.0, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, pixel_size.y) * 0.7071).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(pixel_size.x, pixel_size.y) * 0.7071).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, -pixel_size.y) * 0.7071).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV - vec2(pixel_size.x, -pixel_size.y) * 0.7071).a);

		vec4 outline = vec4(outline_color.rgb, max_alpha * outline_color.a) * (1.0 - base_color.a);
		COLOR = base_color + outline;
	} else {
		COLOR = base_color;
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/visual/outline.gdshader
git commit -m "feat: add outline shader for interactable highlighting"
```

---

### Task 2: Add Interact Input Action

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Add interact input action to project.godot**

Open `project.godot` and add the `interact` action after the existing `move_right` action in the `[input]` section. The keycode for E is 69.

Add this entry right after the `move_right` block and before the `[physics]` section:

```
interact={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":69,"physical_keycode":0,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Commit**

```bash
git add project.godot
git commit -m "feat: add interact input action (E key)"
```

---

### Task 3: Create Interactable Component

**Files:**
- Create: `src/interactables/interactable.gd`

- [ ] **Step 1: Write the Interactable script**

Create `src/interactables/interactable.gd`:

```gdscript
class_name Interactable
extends Node

signal highlighted
signal unhighlighted

@export var interaction_name: String = ""
@export var outline_material: ShaderMaterial

var _is_highlighted: bool = false


func set_highlighted(enabled: bool) -> void:
	if _is_highlighted == enabled:
		return
	_is_highlighted = enabled
	if outline_material:
		outline_material.set_shader_parameter("outline_width", 2.0 if enabled else 0.0)
	if enabled:
		highlighted.emit()
	else:
		unhighlighted.emit()


func interact(player: Node) -> void:
	var parent := get_parent()
	if parent and parent.has_method("interact"):
		parent.interact(player)
```

- [ ] **Step 2: Commit**

```bash
git add src/interactables/interactable.gd
git commit -m "feat: add Interactable component with outline toggle"
```

---

### Task 4: Create Drop Base Scene

**Files:**
- Create: `src/drops/drop.gd`
- Create: `scenes/drop.tscn`
- Create: `shaders/visual/outline.tres` (material resource)

- [ ] **Step 1: Create the outline ShaderMaterial resource**

Create `shaders/visual/outline.tres`:

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://shaders/visual/outline.gdshader" id="1"]

[resource]
shader = ExtResource("1")
shader_parameter/outline_width = 0.0
shader_parameter/outline_color = Color(1, 1, 1, 1)
```

Note: If this .tres file doesn't load correctly, create it via the Godot editor: create a new ShaderMaterial resource, assign the outline shader, set `outline_width` to 0.0, and save.

- [ ] **Step 2: Write the Drop script**

Create `src/drops/drop.gd`:

```gdscript
class_name Drop
extends RigidBody2D

@export var linear_damp_value: float = 5.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	linear_damp = linear_damp_value
	mass = 1.0


func interact(player: Node) -> void:
	_pickup(player)


func _pickup(_player: Node) -> void:
	queue_free()


func set_highlighted(enabled: bool) -> void:
	if _interactable:
		_interactable.set_highlighted(enabled)
```

- [ ] **Step 3: Create the Drop scene file**

Create `scenes/drop.tscn`:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://src/drops/drop.gd" id="1"]
[ext_resource type="ShaderMaterial" path="res://shaders/visual/outline.tres" id="2"]
[ext_resource type="Script" path="res://src/interactables/interactable.gd" id="3"]

[sub_resource type="CircleShape2D" id="CircleShape2D_1"]
radius = 8.0

[node name="Drop" type="RigidBody2D"]
collision_layer = 2
collision_mask = 3
linear_damp = 5.0
script = ExtResource("1")

[node name="Sprite2D" type="Sprite2D" parent="."]
material = ExtResource("2")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_1")

[node name="Interactable" type="Node" parent="."]
outline_material = ExtResource("2")
script = ExtResource("3")
```

- [ ] **Step 4: Commit**

```bash
git add src/drops/drop.gd scenes/drop.tscn shaders/visual/outline.tres
git commit -m "feat: add Drop base scene with physics, outline, and Interactable"
```

---

### Task 5: Create InteractionController on Player

**Files:**
- Create: `src/player/interaction_controller.gd`
- Modify: `scenes/player.tscn` — add InteractionController node

- [ ] **Step 1: Write the InteractionController script**

Create `src/player/interaction_controller.gd`:

```gdscript
class_name InteractionController
extends Node

var _player: CharacterBody2D = null
var _nearby_interactables: Array[Interactable] = []
var _highlighted_interactable: Interactable = null
var _detection_area: Area2D = null


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
	
	var shape := CircleShape2D.new()
	shape.radius = 32.0
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	_detection_area.add_child(collision_shape)
	_detection_area.collision_mask = 2
	_detection_area.monitoring = true
	
	add_child(_detection_area)
	
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	var closest := _find_closest_interactable()
	if _highlighted_interactable != closest:
		if _highlighted_interactable:
			_highlighted_interactable.set_highlighted(false)
		_highlighted_interactable = closest
		if _highlighted_interactable:
			_highlighted_interactable.set_highlighted(true)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("interact") and _highlighted_interactable:
		_highlighted_interactable.interact(_player)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	var interactable := _find_interactable(body)
	if interactable:
		_nearby_interactables.append(interactable)


func _on_body_exited(body: Node2D) -> void:
	var interactable := _find_interactable(body)
	if interactable:
		_nearby_interactables.erase(interactable)
		if _highlighted_interactable == interactable:
			_highlighted_interactable.set_highlighted(false)
			_highlighted_interactable = null


func _find_interactable(node: Node) -> Interactable:
	for child in node.get_children():
		if child is Interactable:
			return child
	return null


func _find_closest_interactable() -> Interactable:
	var closest: Interactable = null
	var closest_dist: float = INF
	var player_pos: Vector2 = _player.global_position
	for interactable in _nearby_interactables:
		if not is_instance_valid(interactable):
			_nearby_interactables.erase(interactable)
			continue
		var dist: float = interactable.get_parent().global_position.distance_to(player_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = interactable
	return closest
```

- [ ] **Step 2: Add InteractionController to the player scene**

Modify `scenes/player.tscn` to add the InteractionController node. Add this after the `[ext_resource` section for lava_dmg and before the `[sub_resource` section:

Add a new ext_resource for the interaction_controller script:
```
[ext_resource type="Script" path="res://src/player/interaction_controller.gd" id="interaction_ctrl"]
```

And add the node after the LavaDamageChecker node:
```
[node name="InteractionController" type="Node" parent="."]
script = ExtResource("interaction_ctrl")
```

- [ ] **Step 3: Update player collision mask to include layer 2**

In `src/player/player_controller.gd`, add the collision mask setup in `_ready()`:

```gdscript
func _ready() -> void:
	add_to_group("player")
	collision_mask = 3  # Layers 1+2: terrain and drops
	shadow_grid = ShadowGridScript.new()
	# ... rest of _ready
```

Specifically, add `collision_mask = 3` right after `add_to_group("player")` in `_ready()`.

- [ ] **Step 4: Commit**

```bash
git add src/player/interaction_controller.gd scenes/player.tscn src/player/player_controller.gd
git commit -m "feat: add InteractionController with Area2D detection and E-key interact"
```

---

### Task 6: Update WeaponManager API

**Files:**
- Modify: `src/weapons/weapon_manager.gd`

- [ ] **Step 1: Add try_add_weapon, swap_weapon, has_empty_slot methods**

Add these three methods to `src/weapons/weapon_manager.gd` after the existing `swap_weapons` method:

```gdscript
func try_add_weapon(weapon: Weapon) -> bool:
	for i in range(weapons.size()):
		if weapons[i] == null:
			weapons[i] = weapon
			return true
	return false


func swap_weapon(slot_index: int, new_weapon: Weapon) -> Weapon:
	if slot_index < 0 or slot_index >= weapons.size():
		return null
	var old_weapon: Weapon = weapons[slot_index]
	weapons[slot_index] = new_weapon
	return old_weapon


func has_empty_slot() -> bool:
	for weapon in weapons:
		if weapon == null:
			return true
	return false
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/weapon_manager.gd
git commit -m "feat: add try_add_weapon, swap_weapon, has_empty_slot to WeaponManager"
```

---

### Task 7: Update WeaponPopup for Pickup Mode

**Files:**
- Modify: `src/ui/weapon_popup.gd`

- [ ] **Step 1: Add pickup mode support to WeaponPopup**

Add these variables after the existing `var _selected_slot: int = -1`:

```gdscript
var _pickup_mode: bool = false
var _pickup_weapon: Weapon = null
var _pickup_callback: Callable
```

Add the `open_for_pickup` method after the existing `open` method:

```gdscript
func open_for_pickup(weapon_manager: WeaponManager, new_weapon: Weapon, callback: Callable) -> void:
	_pickup_mode = true
	_pickup_weapon = new_weapon
	_pickup_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_build_cards()
	_title_label.text = "Replace a slot:"
	SceneManager.set_paused(true)
	visible = true
```

Modify the `close` method to reset pickup mode state:

```gdscript
func close() -> void:
	visible = false
	_weapon_manager = null
	_pickup_mode = false
	_pickup_weapon = null
	_pickup_callback = Callable()
	_selected_slot = -1
	_clear_cards()
	SceneManager.set_paused(false)
```

Modify `_on_card_input` to handle pickup mode (replace the existing method):

```gdscript
func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			_pickup_callback.call(slot_index)
			close()
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()
```

- [ ] **Step 2: Commit**

```bash
git add src/ui/weapon_popup.gd
git commit -m "feat: add pickup mode to WeaponPopup for weapon drop selection"
```

---

### Task 8: Create WeaponDrop

**Files:**
- Create: `src/drops/weapon_drop.gd`
- Create: `scenes/weapon_drop.tscn`

- [ ] **Step 1: Write the WeaponDrop script**

Create `src/drops/weapon_drop.gd`:

```gdscript
class_name WeaponDrop
extends Drop

var weapon: Weapon = null


func _ready() -> void:
	super._ready()
	if weapon and weapon.icon_texture:
		_sprite.texture = weapon.icon_texture


func _pickup(player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if weapon_manager.try_add_weapon(weapon):
		queue_free()
	else:
		var popup = player.get_parent().get_node("WeaponPopup")
		popup.open_for_pickup(weapon_manager, weapon, _on_slot_selected.bind(player))


func _on_slot_selected(slot_index: int, player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	var old_weapon: Weapon = weapon_manager.swap_weapon(slot_index, weapon)
	if old_weapon:
		var drop_scene: PackedScene = preload("res://scenes/weapon_drop.tscn")
		var new_drop: WeaponDrop = drop_scene.instantiate()
		new_drop.weapon = old_weapon
		player.get_parent().add_child(new_drop)
		new_drop.global_position = player.global_position
	queue_free()
```

- [ ] **Step 2: Create the WeaponDrop scene file**

Create `scenes/weapon_drop.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/drop.tscn" id="1"]
[ext_resource type="Script" path="res://src/drops/weapon_drop.gd" id="2"]

[node name="WeaponDrop" instance=ExtResource("1")]
script = ExtResource("2")
```

Note: This uses Godot scene inheritance — `WeaponDrop` inherits from `Drop` and overrides only the root node's script. If this .tscn doesn't load correctly in the editor, create it via: Scene > New Inherited Scene > select `drop.tscn` > set root node script to `weapon_drop.gd` > rename root to "WeaponDrop".

- [ ] **Step 3: Commit**

```bash
git add src/drops/weapon_drop.gd scenes/weapon_drop.tscn
git commit -m "feat: add WeaponDrop with pickup and weapon swap logic"
```

---

### Task 9: Integration Test

**Files:**
- No new files; manual testing

- [ ] **Step 1: Run the game and verify**

1. Launch the game in the Godot editor
2. Place a WeaponDrop in the game scene (or spawn one via script) with a weapon assigned
3. Verify:
   - Walking near the drop shows a white outline on the drop's sprite
   - Walking away removes the outline
   - Pressing E near the drop picks it up (if weapon slots available)
   - If all slots full, the WeaponPopup opens in pickup mode
   - Clicking a slot in pickup mode replaces that weapon and drops the old weapon at the player position
   - Pressing Escape or clicking overlay in pickup mode cancels and closes the popup
   - Walking into the drop pushes it away (RigidBody2D physics)
   - The drop decelerates and stops (linear_damp)

- [ ] **Step 2: Commit any fixes**

If bug fixes were needed during testing, commit them:
```bash
git add -A
git commit -m "fix: integration fixes for interactable and drop system"
```