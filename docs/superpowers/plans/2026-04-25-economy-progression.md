# Economy & Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 3 economy & progression: currency, drops, modifier inventory, shop UI, and a dummy enemy to test the loot loop.

**Architecture:** Player gets WalletComponent + ModifierInventory nodes. Enemies drop GoldDrop / WeaponDrop via DropTable resource. Shop UI (CanvasLayer) has buy + remove-modifier tabs, uses both wallet and inventory. CurrencyHUD shows gold in HUD.

**Tech Stack:** Godot 4.6 / GDScript, gdUnit4 for tests (no tests yet).

---

### Task 1: Drop Table Resource

**Files:**
- Create: `src/enemies/drop_table.gd`

- [ ] **Step 1: Create the DropEntry inner class and DropTable resource**

```gdscript
# src/enemies/drop_table.gd
class_name DropTable
extends Resource

class DropEntry:
	var scene: PackedScene
	var weight: float
	var min_count: int = 1
	var max_count: int = 1
	var gold_per_drop: int = 0

	func _init(p_scene: PackedScene, p_weight: float, p_min: int = 1, p_max: int = 1, p_gold: int = 0):
		scene = p_scene
		weight = p_weight
		min_count = p_min
		max_count = p_max
		gold_per_drop = p_gold

var entries: Array[DropEntry] = []


func add_entry(entry: DropEntry) -> void:
	entries.append(entry)


func resolve(position: Vector2, parent: Node) -> void:
	for entry in entries:
		var roll := randf()
		if roll > entry.weight:
			continue
		var count := randi_range(entry.min_count, entry.max_count)
		for i in count:
			var drop: Node = entry.scene.instantiate()
			if drop.has_method("set_amount") and entry.gold_per_drop > 0:
				drop.set_amount(entry.gold_per_drop)
			var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
			parent.add_child(drop)
			drop.global_position = position + offset
```

---

### Task 2: Shop Offer Resource

**Files:**
- Create: `src/economy/shop_offer.gd`

- [ ] **Step 1: Create the ShopOffer resource**

```gdscript
# src/economy/shop_offer.gd
class_name ShopOffer
extends Resource

var modifier: Modifier
var price: int

func _init(p_modifier: Modifier, p_price: int):
	modifier = p_modifier
	price = p_price
```

---

### Task 3: Wallet Component

**Files:**
- Create: `src/player/wallet_component.gd`

- [ ] **Step 1: Create the WalletComponent**

```gdscript
# src/player/wallet_component.gd
class_name WalletComponent
extends Node

signal gold_changed(new_amount: int)

var gold: int = 0


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true
```

---

### Task 4: Modifier Inventory

**Files:**
- Create: `src/player/modifier_inventory.gd`

- [ ] **Step 1: Create the ModifierInventory**

```gdscript
# src/player/modifier_inventory.gd
class_name ModifierInventory
extends Node

signal modifier_added(modifier: Modifier)
signal modifier_removed(modifier: Modifier)

var _modifiers: Array[Modifier] = []


func add_modifier(modifier: Modifier) -> void:
	_modifiers.append(modifier)
	modifier_added.emit(modifier)


func remove_modifier(modifier: Modifier) -> bool:
	var idx := _modifiers.find(modifier)
	if idx < 0:
		return false
	_modifiers.remove_at(idx)
	modifier_removed.emit(modifier)
	return true


func get_modifiers() -> Array[Modifier]:
	return _modifiers.duplicate()


func has_modifiers() -> bool:
	return _modifiers.size() > 0
```

---

### Task 5: Gold Drop

**Files:**
- Create: `src/drops/gold_drop.gd`
- Create: `scenes/gold_drop.tscn`

- [ ] **Step 1: Create gold_drop.gd**

```gdscript
# src/drops/gold_drop.gd
class_name GoldDrop
extends Drop

var amount: int = 1


func set_amount(value: int) -> void:
	amount = value


func _ready() -> void:
	super._ready()
	# Color the sprite gold
	_sprite.modulate = Color(1.0, 0.84, 0.0)


func _pickup(player: Node) -> void:
	var wallet := player.get_node_or_null("WalletComponent")
	if wallet:
		wallet.add_gold(amount)
	queue_free()
```

- [ ] **Step 2: Create gold_drop.tscn**

Inherits from `drop.tscn`, overrides script to `gold_drop.gd`, provides a coin texture.

Use coin texture: `textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/coin_01a.png`

Create `scenes/gold_drop.tscn`:
```gdscene
[gd_scene format=3 uid="uid://new_gold_drop"]

[ext_resource type="PackedScene" path="res://scenes/drop.tscn" id="1"]
[ext_resource type="Script" path="res://src/drops/gold_drop.gd" id="2"]
[ext_resource type="Shader" uid="uid://bgkst7g0qd22q" path="res://shaders/visual/outline.gdshader" id="3"]
[ext_resource type="Texture2D" path="res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/coin_01a.png" id="4"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_1"]
shader = ExtResource("3")
shader_parameter/outline_width = 0.0
shader_parameter/outline_color = Color(1, 1, 1, 1)

[node name="GoldDrop" instance=ExtResource("1")]
script = ExtResource("2")

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("4")
material = SubResource("ShaderMaterial_1")

[node name="Interactable" parent="." index="2" node_paths=PackedStringArray("canvas_item")]
canvas_item = NodePath("../Sprite2D")
```

---

### Task 6: Enemy Base

**Files:**
- Create: `src/enemies/enemy.gd`
- Create: `scenes/enemy.tscn`

- [ ] **Step 1: Create enemy.gd**

```gdscript
# src/enemies/enemy.gd
class_name Enemy
extends Node2D

signal died
signal health_changed(current: int, maximum: int)

@export var max_health: int = 20
@export var speed: float = 20.0

var health: int
var drop_table: DropTable = null
var _hit_flash_tween: Tween = null


func _ready() -> void:
	health = max_health


func hit(damage: int) -> void:
	if damage <= 0:
		return
	health -= damage
	health_changed.emit(health, max_health)
	_on_hit()
	if health <= 0:
		die()


func die() -> void:
	died.emit()
	if drop_table:
		drop_table.resolve(global_position, get_parent())
	_on_death()
	queue_free()


func _on_hit() -> void:
	pass


func _on_death() -> void:
	pass
```

- [ ] **Step 2: Create enemy.tscn**

```
Node2D (Enemy)
├── Sprite2D
└── CollisionShape2D (CircleShape2D, radius=8)
```

Create `scenes/enemy.tscn`:
```gdscene
[gd_scene format=3 uid="uid://new_enemy"]

[ext_resource type="Script" path="res://src/enemies/enemy.gd" id="1"]

[sub_resource type="CircleShape2D" id="CircleShape2D_1"]
radius = 8.0

[node name="Enemy" type="Node2D"]
script = ExtResource("1")

[node name="Sprite2D" type="Sprite2D" parent="."]

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_1")
```

---

### Task 7: Dummy Enemy

**Files:**
- Create: `src/enemies/dummy_enemy.gd`
- Create: `scenes/dummy_enemy.tscn`

- [ ] **Step 1: Create dummy_enemy.gd**

```gdscript
# src/enemies/dummy_enemy.gd
class_name DummyEnemy
extends Enemy

const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")
const MeleeWeaponScript := preload("res://src/weapons/melee_weapon.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/lava_emitter_modifier.gd")

var _player: Node = null


func _ready() -> void:
	super._ready()
	_sprite_modulate_green()
	_setup_drop_table()
	_player = get_tree().get_first_node_in_group("player")


func _sprite_modulate_green() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = Color(0.2, 0.8, 0.2)


func _setup_drop_table() -> void:
	drop_table = DropTable.new()
	var weapon_drop_entry := DropTable.DropEntry.new(WEAPON_DROP_SCENE, 1.0, 1, 1)
	drop_table.add_entry(weapon_drop_entry)
	var gold_entry := DropTable.DropEntry.new(GOLD_DROP_SCENE, 1.0, 2, 5, 5)
	drop_table.add_entry(gold_entry)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dir := _player.global_position - global_position
	if dir.length() < 4.0:
		return
	global_position += dir.normalized() * speed * delta


func _on_hit() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(0.2, 0.8, 0.2), 0.15)
```

- [ ] **Step 2: Create dummy_enemy.tscn**

Inherits from `enemy.tscn`, overrides script to `dummy_enemy.gd`.

```gdscene
[gd_scene format=3 uid="uid://new_dummy_enemy"]

[ext_resource type="PackedScene" path="res://scenes/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/dummy_enemy.gd" id="2"]

[node name="DummyEnemy" instance=ExtResource("1")]
script = ExtResource("2")
```

---

### Task 8: Currency HUD

**Files:**
- Create: `src/ui/currency_hud.gd`

- [ ] **Step 1: Create currency_hud.gd**

```gdscript
# src/ui/currency_hud.gd
class_name CurrencyHUD
extends CanvasLayer

const COIN_TEXTURE := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/coin_01a.png")

@onready var _coin_icon: TextureRect = %CoinIcon
@onready var _gold_label: Label = %GoldLabel
@onready var _container: Control = %Container


func _ready() -> void:
	_container.theme = UiTheme.get_theme()
	_coin_icon.texture = COIN_TEXTURE
	_gold_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_gold_label.add_theme_font_size_override("font_size", 16)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			wallet.gold_changed.connect(_on_gold_changed)
			_on_gold_changed(wallet.gold)


func _on_gold_changed(amount: int) -> void:
	_gold_label.text = str(amount)
```

---

### Task 9: Shop UI

**Files:**
- Create: `src/economy/shop_ui.gd`
- Create: `scenes/economy/shop_ui.tscn`

- [ ] **Step 1: Create shop_ui.gd**

```gdscript
# src/economy/shop_ui.gd
class_name ShopUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 200)
const MODIFIER_ICON_SIZE := Vector2(48, 48)
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")

var _remove_cost: int = 50
var _remove_count: int = 0
var _offerings: Array[ShopOffer] = []

@onready var _overlay: ColorRect = %Overlay
@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _buy_container: HBoxContainer = %BuyContainer
@onready var _remove_button: Button = %RemoveButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme := UiTheme.get_theme()
	_title_label.theme = theme
	_gold_label.theme = theme
	_overlay.gui_input.connect(_on_overlay_input)
	_close_button.pressed.connect(close)
	_remove_button.pressed.connect(_on_remove_pressed)
	visible = false


func open(offerings: Array[ShopOffer]) -> void:
	_offerings = offerings
	_remove_count = 0
	_refresh_gold()
	_build_buy_grid()
	_build_remove_section()
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_clear_buy_grid()
	visible = false
	SceneManager.set_paused(false)


func _refresh_gold() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			_gold_label.text = "Gold: %d" % wallet.gold


func _build_buy_grid() -> void:
	_clear_buy_grid()
	for offer in _offerings:
		var card := _create_offer_card(offer)
		_buy_container.add_child(card)


func _clear_buy_grid() -> void:
	for child in _buy_container.get_children():
		child.queue_free()


func _create_offer_card(offer: ShopOffer) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if offer.modifier.icon_texture:
		var icon := TextureRect.new()
		icon.texture = offer.modifier.icon_texture
		icon.custom_minimum_size = MODIFIER_ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = offer.modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var desc := offer.modifier.get_description()
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 13)
		vbox.add_child(desc_label)

	var price_label := Label.new()
	price_label.text = "%d gold" % offer.price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	vbox.add_child(price_label)

	var buy_button := Button.new()
	buy_button.text = "Buy"
	buy_button.theme = UiTheme.get_theme()
	buy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy_button.pressed.connect(_on_buy_pressed.bind(offer, card))
	vbox.add_child(buy_button)

	return card


func _on_buy_pressed(offer: ShopOffer, card: Control) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var wallet := player.get_node_or_null("WalletComponent")
	var inventory := player.get_node_or_null("ModifierInventory")
	if not wallet or not inventory:
		return
	if not wallet.spend_gold(offer.price):
		return
	# Move modifier from shop offer to player inventory
	var mod: Modifier = offer.modifier
	_offerings.erase(offer)
	card.queue_free()
	inventory.add_modifier(mod)
	_refresh_gold()


func _build_remove_section() -> void:
	_remove_cost = 50 + _remove_count * 25
	_remove_button.text = "Remove Modifier (%d gold)" % _remove_cost

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var inventory := player.get_node_or_null("ModifierInventory")
		var wallet := player.get_node_or_null("WalletComponent")
		var can_afford := wallet and wallet.gold >= _remove_cost
		var has_mods := inventory and inventory.has_modifiers()
		_remove_button.disabled = not (can_afford and has_mods)


func _on_remove_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var inventory := player.get_node_or_null("ModifierInventory")
	var wallet := player.get_node_or_null("WalletComponent")
	if not inventory or not wallet:
		return
	var mods := inventory.get_modifiers()
	if mods.size() == 0:
		return
	if not wallet.spend_gold(_remove_cost):
		return
	inventory.remove_modifier(mods[-1])
	_remove_count += 1
	_refresh_gold()
	_build_remove_section()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _on_card_mouse_entered(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", true)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2(1.03, 1.03), 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = UiTheme.ACCENT
		card.add_theme_stylebox_override("panel", new_style)


func _on_card_mouse_exited(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", false)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = UiTheme.PANEL_BORDER
		card.add_theme_stylebox_override("panel", new_style)
```

- [ ] **Step 2: Create shop_ui.tscn**

```gdscene
[gd_scene format=3 uid="uid://new_shop_ui"]

[ext_resource type="Script" path="res://src/economy/shop_ui.gd" id="1"]

[node name="ShopUI" type="CanvasLayer"]
layer = 16
script = ExtResource("1")

[node name="Overlay" type="ColorRect" parent="." unique_id=1]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.102, 0.059, 0.071, 0.87)

[node name="CenterContainer" type="CenterContainer" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
grow_horizontal = 2
grow_vertical = 2

[node name="VBoxContainer" type="VBoxContainer" parent="CenterContainer"]
layout_mode = 2
theme_override_constants/separation = 16
alignment = 1

[node name="TitleLabel" type="Label" parent="CenterContainer/VBoxContainer" unique_id=2]
unique_name_in_owner = true
layout_mode = 2
text = "SHOP"
horizontal_alignment = 1

[node name="GoldLabel" type="Label" parent="CenterContainer/VBoxContainer" unique_id=3]
unique_name_in_owner = true
layout_mode = 2
text = "Gold: 0"
horizontal_alignment = 1

[node name="BuyContainer" type="HBoxContainer" parent="CenterContainer/VBoxContainer" unique_id=4]
unique_name_in_owner = true
layout_mode = 2
theme_override_constants/separation = 16
alignment = 1

[node name="RemoveButton" type="Button" parent="CenterContainer/VBoxContainer" unique_id=5]
unique_name_in_owner = true
layout_mode = 2
text = "Remove Modifier (50 gold)"
size_flags_horizontal = 4

[node name="CloseButton" type="Button" parent="CenterContainer/VBoxContainer" unique_id=6]
unique_name_in_owner = true
layout_mode = 2
text = "Close"
size_flags_horizontal = 4
```

---

### Task 10: Integration

**Files:**
- Modify: `src/input/input_handler.gd`
- Modify: `scenes/game.tscn`
- Modify: `scenes/player.tscn`

- [ ] **Step 1: Add dev keys to input_handler.gd**

Add at line 10 (after `LavaEmitterModifierScript`):
```gdscript
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const DUMMY_ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")
const SHOP_UI_SCENE := preload("res://scenes/economy/shop_ui.tscn")
const ShopOfferScript := preload("res://src/economy/shop_offer.gd")
const LavaEmitterModifierScript := preload("res://src/weapons/lava_emitter_modifier.gd")
```

Add after the right-click block (after `event.button_index == MOUSE_BUTTON_RIGHT` block, around line 34):
```gdscript
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_spawn_dummy_enemy(world_pos)
```

Add new functions at end of file:
```gdscript
func _spawn_dummy_enemy(pos: Vector2) -> void:
	var enemy: Node2D = DUMMY_ENEMY_SCENE.instantiate()
	get_parent().add_child(enemy)
	enemy.global_position = pos


func _spawn_gold_drop(pos: Vector2) -> void:
	var drop: GoldDrop = GOLD_DROP_SCENE.instantiate()
	drop.set_amount(10)
	get_parent().add_child(drop)
	drop.global_position = pos


func _open_test_shop() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var shop: ShopUI = SHOP_UI_SCENE.instantiate()
	get_parent().add_child(shop)
	var offerings: Array[ShopOffer] = [
		ShopOfferScript.new(LavaEmitterModifierScript.new(), 50),
	]
	shop.open(offerings)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_G:
			var viewport := get_viewport()
			var camera := viewport.get_camera_2d()
			if camera == null:
				return
			var screen_pos := viewport.get_mouse_position()
			var view_size := viewport.get_visible_rect().size
			var world_pos := (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
			_spawn_gold_drop(world_pos)
		KEY_H:
			var viewport := get_viewport()
			var camera := viewport.get_camera_2d()
			if camera == null:
				return
			var screen_pos := viewport.get_mouse_position()
			var view_size := viewport.get_visible_rect().size
			var world_pos := (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
			_spawn_dummy_enemy(world_pos)
		KEY_U:
			_open_test_shop()
```

- [ ] **Step 2: Add WalletComponent and ModifierInventory to player.tscn**

After the InteractionController node (line 55-56):
```
[node name="WalletComponent" type="Node" parent="."]
script = ExtResource("wallet_comp")  ; Add ext_resource for src/player/wallet_component.gd

[node name="ModifierInventory" type="Node" parent="."]
script = ExtResource("modifier_inv")  ; Add ext_resource for src/player/modifier_inventory.gd
```

Add ext_resources:
```
[ext_resource type="Script" uid="uid://new_wallet_uid" path="res://src/player/wallet_component.gd" id="wallet_comp"]
[ext_resource type="Script" uid="uid://new_mod_inv_uid" path="res://src/player/modifier_inventory.gd" id="modifier_inv"]
```

- [ ] **Step 3: Add CurrencyHUD to game.tscn**

After the DeathScreen node (line 58-59):
```
[node name="CurrencyHUD" type="CanvasLayer" parent="."]
script = ExtResource("currency_hud")  ; Add ext_resource
```

Add ext_resource:
```
[ext_resource type="Script" path="res://src/ui/currency_hud.gd" id="currency_hud"]
```

Create its child nodes in the tscn or in currency_hud.gd's `_ready()`. Since we can create them in code, update CurrencyHUD to build its own UI:

```gdscript
# Updated currency_hud.gd
class_name CurrencyHUD
extends CanvasLayer

const COIN_TEXTURE := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/coin_01a.png")

var _gold_label: Label
var _coin_icon: TextureRect


func _ready() -> void:
	# Build the HUD layout in code (avoids tscn dependency)
	var container := HBoxContainer.new()
	container.position = Vector2(get_viewport().get_visible_rect().size.x - 120, 8)
	container.theme = UiTheme.get_theme()
	add_child(container)

	_coin_icon = TextureRect.new()
	_coin_icon.texture = COIN_TEXTURE
	_coin_icon.custom_minimum_size = Vector2(16, 16)
	_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(_coin_icon)

	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_gold_label.add_theme_font_size_override("font_size", 16)
	container.add_child(_gold_label)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			wallet.gold_changed.connect(_on_gold_changed)
			_on_gold_changed(wallet.gold)


func _on_gold_changed(amount: int) -> void:
	_gold_label.text = str(amount)
```

Since the HUD now builds itself in code, we still need the ext_resource in game.tscn, but no child nodes. Just add:
```
[node name="CurrencyHUD" type="CanvasLayer" parent="."]
script = ExtResource("currency_hud")
```

- [ ] **Step 4: WeaponPopup integration with ModifierInventory**

Update `src/ui/weapon_popup.gd` to work with ModifierInventory.

When `_handle_modifier_slot_click` is called (line 390), the modifier comes from `_modifier_ref`. If we want modifiers from inventory to be equipable, the caller needs to remove from inventory before passing.

The modifier picker (weapon_popup) already handles this pattern. The call sites (modifier_drop.gd) already pass a Modifier directly. Add an inventory-aware path:

In `weapon_popup.gd`, add a new open method:
```gdscript
func open_for_inventory_modifier(weapon_manager: WeaponManager, inventory: ModifierInventory, callback: Callable) -> void:
	# Opens popup for equipping a modifier from inventory onto a weapon
	_modifier_mode = true
	_pickup_mode = false
	_weapon_manager = weapon_manager
	_selected_slot = -1
	# Store inventory reference to remove on equip
	set_meta("inventory_ref", inventory)
	_title_label.text = "Equip modifier to:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true
```

And update `_handle_modifier_slot_click` to remove from inventory on equip:
```gdscript
func _handle_modifier_slot_click(slot_index: int) -> void:
	var weapon: Weapon = _weapon_manager.weapons[slot_index]
	if weapon == null:
		_show_feedback("No weapon in that slot!")
		return
	var empty_slot := _find_empty_modifier_slot(weapon)
	if empty_slot == -1:
		_show_feedback("No empty modifier slots!")
		return
	# Remove from inventory if applicable
	var inventory := get_meta("inventory_ref") as ModifierInventory
	if inventory:
		inventory.remove_modifier(_modifier_ref)
	_weapon_manager.add_modifier_to_weapon(slot_index, empty_slot, _modifier_ref)
	_modifier_callback.call()
	close()
```

---

### Task 11: Verify Game Loads

- [ ] **Step 1: Run the game**

Run: `godot --headless --check-only` (or open in editor and press F5)

Expected: Game loads without errors. Left-click spawns weapon drops, right-click places lava, middle-click spawns dummy enemies. G spawns gold drops, U opens test shop.
