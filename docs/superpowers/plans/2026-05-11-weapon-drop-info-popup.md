# Weapon Drop Info Popup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a floating info card above the highlighted weapon drop showing name, damage, cooldown, and modifier icons.

**Architecture:** `WeaponInfoPopup` (CanvasLayer, layer=15) owned by `PickupContext`. Popup creates its UI in code, positions via camera canvas transform each frame, animates in/out with JuicyPanel-style elastic transitions.

**Tech Stack:** Godot 4.6, GDScript, existing `UiTheme` styles

---

### Task 1: Create WeaponInfoPopup script

**Files:**
- Create: `src/ui/weapon_info_popup.gd`

- [ ] **Step 1: Write the WeaponInfoPopup class**

```gdscript
class_name WeaponInfoPopup
extends CanvasLayer

const POPUP_OFFSET_Y: float = -24.0
const SHOW_DURATION: float = 0.35
const HIDE_DURATION: float = 0.20
const CROSSFADE_DURATION: float = 0.10

var _card_root: Control
var _panel: PanelContainer
var _name_label: Label
var _damage_label: Label
var _cooldown_label: Label
var _modifier_container: HBoxContainer
var _show_tween: Tween
var _hide_tween: Tween
var _is_visible: bool = false
var _current_drop: WeaponDrop = null


func _ready() -> void:
	layer = 15

	_card_root = Control.new()
	_card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_root)

	_panel = PanelContainer.new()
	_panel.theme = UiTheme.get_theme()
	_card_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_name_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_damage_label = Label.new()
	_damage_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	_damage_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_damage_label)

	_cooldown_label = Label.new()
	_cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	_cooldown_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_cooldown_label)

	_modifier_container = HBoxContainer.new()
	vbox.add_child(_modifier_container)

	_card_root.hide()
	_card_root.modulate.a = 0.0


func show_for(drop: WeaponDrop) -> void:
	if not is_instance_valid(drop):
		hide()
		return
	var weapon: Weapon = drop.weapon
	if weapon == null:
		hide()
		return

	if _current_drop == drop and _is_visible:
		return

	if _is_visible and _current_drop != drop:
		_crossfade_to(drop)
		return

	_current_drop = drop
	_populate(weapon)
	_animate_show()


func hide() -> void:
	if not _is_visible:
		return
	_animate_hide()


func update_position(drop: WeaponDrop) -> void:
	if not _is_visible:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var screen_pos := cam.get_canvas_transform() * drop.global_position
	screen_pos.y += POPUP_OFFSET_Y
	_card_root.position = screen_pos


func _populate(weapon: Weapon) -> void:
	_name_label.text = weapon.name
	_damage_label.text = "Damage: %d" % weapon.damage
	_cooldown_label.text = "Cooldown: %.1fs" % weapon.cooldown

	for child in _modifier_container.get_children():
		child.queue_free()

	var has_modifier := false
	for i in range(weapon.modifier_slot_count):
		var mod := weapon.get_modifier_at(i)
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(24, 24)
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if mod and mod.icon_texture:
			slot.texture = mod.icon_texture
			has_modifier = true
		_modifier_container.add_child(slot)

	_modifier_container.visible = has_modifier


func _animate_show() -> void:
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()

	_card_root.show()
	_card_root.modulate.a = 0.0
	_card_root.scale = Vector2(0.9, 0.9)

	if _current_drop:
		update_position(_current_drop)

	var target_y := _card_root.position.y
	_card_root.position.y += 12.0

	_show_tween = create_tween()
	_show_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_show_tween.parallel().tween_property(_card_root, "position:y", target_y, SHOW_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_tween.parallel().tween_property(_card_root, "modulate:a", 1.0, 0.22)\
		.set_trans(Tween.TRANS_LINEAR)
	_show_tween.parallel().tween_property(_card_root, "scale", Vector2.ONE, SHOW_DURATION)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_show_tween.tween_callback(func() -> void: _is_visible = true)


func _animate_hide() -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()

	_is_visible = false
	_current_drop = null

	_hide_tween = create_tween()
	_hide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hide_tween.parallel().tween_property(_card_root, "modulate:a", 0.0, 0.15)\
		.set_trans(Tween.TRANS_LINEAR)
	_hide_tween.parallel().tween_property(_card_root, "position:y", _card_root.position.y + 8.0, HIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_hide_tween.tween_callback(func() -> void: _card_root.hide())


func _crossfade_to(drop: WeaponDrop) -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()

	_is_visible = false

	var crossfade := create_tween()
	crossfade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	crossfade.tween_property(_card_root, "modulate:a", 0.0, CROSSFADE_DURATION)
	crossfade.tween_callback(func() -> void:
		_current_drop = drop
		_populate(drop.weapon)
		_animate_show()
	)
```

- [ ] **Step 2: Verify the file is syntactically valid**

Run: `head -1 src/ui/weapon_info_popup.gd`
Expected: `class_name WeaponInfoPopup`

---

### Task 2: Integrate with PickupContext

**Files:**
- Modify: `src/player/pickup_context.gd`

- [ ] **Step 1: Add `_info_popup` variable and initialize in `_ready()`**

In `src/player/pickup_context.gd`, add after `var _highlighted: Node2D = null` (line 9):

```gdscript
var _info_popup: WeaponInfoPopup
```

In `_ready()`, add after `_player.add_child.call_deferred(_detection_area)` (line 27):

```gdscript
_info_popup = WeaponInfoPopup.new()
_info_popup.name = "WeaponInfoPopup"
add_child(_info_popup)
```

- [ ] **Step 2: Add popup show/hide logic in `_process()`**

In `_process()`, after the existing highlight switch block (line 37), add:

```gdscript
if get_tree().paused:
	_info_popup.hide()
	return
if _highlighted is WeaponDrop:
	_info_popup.show_for(_highlighted)
	_info_popup.update_position(_highlighted)
else:
	_info_popup.hide()
```

- [ ] **Step 3: Verify the modified file is correct**

Run: `grep -n "_info_popup" src/player/pickup_context.gd`
Expected: 4 matches (variable declaration, creation in _ready, two usages in _process)

---

### Task 3: Manual verification

- [ ] **Step 1: Launch the game and spawn a weapon drop**

Run the game in creative mode (`F1` → toggle creative, or use the creative spawn keys). Verify a weapon drop appears on the ground.

- [ ] **Step 2: Verify popup appears when near a weapon drop**

Walk close to the weapon drop. Expected: a styled popup slides up above the drop with elastic bounce, showing the weapon name, damage, cooldown, and modifier icons.

- [ ] **Step 3: Verify popup hides when walking away**

Walk away from all drops. Expected: popup fades out and drops down slightly.

- [ ] **Step 4: Verify crossfade between two adjacent drops**

Have two weapon drops near each other. Walk from one to the other. Expected: popup crossfades (quick fade, repopulate, animate in).

- [ ] **Step 5: Verify popup tracks a moving drop**

Push a drop around (player collision can nudge RigidBody2D). Expected: popup follows the drop smoothly.

- [ ] **Step 6: Verify popup hides when drop is picked up**

Press E to pick up the weapon drop. Expected: popup disappears.

- [ ] **Step 7: Verify popup hides when game is paused**

Press Escape to open pause menu while near a drop. Expected: popup hides while paused.

- [ ] **Step 8: Verify E-key pickup still works**

Press E near a weapon drop. Expected: WeaponPopup opens normally, pickup flow unchanged.

- [ ] **Step 9: Verify modifier drops do NOT show popup**

Spawn a modifier drop. Walk near it. Expected: highlight outline appears, but NO popup.

---

### Task 4: Commit

- [ ] **Step 1: Stage and commit**

```bash
git add src/ui/weapon_info_popup.gd src/player/pickup_context.gd
git commit -m "feat: add weapon drop info popup on proximity"
```
