# Balatro-Style Card Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply Balatro-style card effects (3D perspective tilt, holographic border, springy hover) to all selection cards via a SubViewport rendering pipeline and custom shader.

**Architecture:** A custom `canvas_item` shader provides 3D tilt and holographic border. Each card is wrapped in a SubViewport→TextureRect pipeline so the vertex shader tilts the entire card visual. A `CardEffects` utility class manages the wrapping, per-frame mouse tracking, and hover tweens. Card creators call `CardEffects.setup_card(card)` instead of manually wiring materials/signals.

**Tech Stack:** Godot 4.6, GDScript, GLSL canvas_item shader, SubViewport, Tween

---

### Task 1: Create the holographic card shader

**Files:**
- Create: `shaders/ui/card_holo.gdshader`

- [ ] **Step 1: Write the shader file**

Create `shaders/ui/card_holo.gdshader`:

```glsl
shader_type canvas_item;

uniform float tilt_x = 0.0;
uniform float tilt_y = 0.0;
uniform float holo_time = 0.0;
uniform float holo_intensity = 0.0;
uniform float border_width : hint_range(0.0, 0.2) = 0.06;
uniform vec2 card_size = vec2(160.0, 220.0);

void vertex() {
	vec2 center = card_size * 0.5;
	vec2 centered = VERTEX - center;

	// 3D rotation around X axis (tilts top/bottom)
	float cos_x = cos(tilt_x);
	float sin_x = sin(tilt_x);
	// R_x: y' = y*cos_x - z*sin_x, z' = y*sin_x + z*cos_x
	float y1 = centered.y * cos_x;
	float z1 = centered.y * sin_x;
	float x1 = centered.x;

	// 3D rotation around Y axis (tilts left/right)
	float cos_y = cos(tilt_y);
	float sin_y = sin(tilt_y);
	// R_y: x'' = x1*cos_y + z1*sin_y, z'' = -x1*sin_y + z1*cos_y
	float x2 = x1 * cos_y + z1 * sin_y;
	float z2 = -x1 * sin_y + z1 * cos_y;
	float y2 = y1;

	// Perspective projection
	float perspective_distance = 2.0 * card_size.x;
	float scale = perspective_distance / (perspective_distance + z2);

	VERTEX = center + vec2(x2 * scale, y2 * scale);
}

vec3 rainbow(float t) {
	// 1D HSL-like rainbow lookup
	t = fract(t);
	vec3 a = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(1.0, 1.0, 0.0);
	vec3 c = vec3(0.0, 1.0, 0.0);
	vec3 d = vec3(0.0, 1.0, 1.0);
	vec3 e = vec3(0.0, 0.0, 1.0);
	vec3 f = vec3(1.0, 0.0, 1.0);

	if (t < 0.1667)       return mix(a, b, t / 0.1667);
	else if (t < 0.3333)  return mix(b, c, (t - 0.1667) / 0.1667);
	else if (t < 0.5)     return mix(c, d, (t - 0.3333) / 0.1667);
	else if (t < 0.6667)  return mix(d, e, (t - 0.5) / 0.1667);
	else if (t < 0.8333)  return mix(e, f, (t - 0.6667) / 0.1667);
	else                  return mix(f, a, (t - 0.8333) / 0.1667);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// Border mask: distance to nearest edge
	float edge_dist = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border_mask = 1.0 - smoothstep(0.0, border_width, edge_dist);

	// Holographic rainbow sweep — direction follows tilt angle
	float tilt_angle = atan(tilt_y, tilt_x);
	float sweep_pos = UV.x * cos(tilt_angle) + UV.y * sin(tilt_angle) + holo_time;
	vec3 holo_color = rainbow(sweep_pos);

	// Metallic specular highlight on border — tracks tilt direction
	float hl_angle = tilt_angle + 3.14159 * 0.5;
	float border_angle = atan(UV.y - 0.5, UV.x - 0.5);
	float angle_diff = abs(border_angle - hl_angle);
	if (angle_diff > 3.14159) { angle_diff = 6.28318 - angle_diff; }
	float highlight = pow(1.0 - smoothstep(0.0, 0.4, angle_diff), 4.0);

	// Inner dim — darken card center so border pops
	float inner_dim = mix(1.0, 0.88, (1.0 - border_mask) * holo_intensity);

	// Composite
	vec3 holo_overlay = mix(holo_color, vec3(1.0), highlight * 0.6) * border_mask * holo_intensity * 0.7;
	vec3 result = base.rgb * inner_dim + holo_overlay;
	COLOR = vec4(result, base.a);
}
```

- [ ] **Step 2: Commit**

```bash
git add shaders/ui/card_holo.gdshader
git commit -m "feat: add balatro-style holographic card shader"
```

---

### Task 2: Create CardEffects utility class

**Files:**
- Create: `src/ui/card_effects.gd`

- [ ] **Step 1: Write the CardEffects static class and CardEffectController**

Create `src/ui/card_effects.gd`:

```gdscript
# src/ui/card_effects.gd
class_name CardEffects

const HOLO_SHADER := preload("res://shaders/ui/card_holo.gdshader")
const DEFAULT_TILT_STRENGTH := 0.08
const DEFAULT_HOVER_SCALE := 1.05

static var _controllers: Dictionary = {}

static func setup_card(card: Control, tilt_strength := DEFAULT_TILT_STRENGTH, hover_scale := DEFAULT_HOVER_SCALE) -> CardEffectController:
	if card.custom_minimum_size.x == 0.0 or card.custom_minimum_size.y == 0.0:
		push_error("CardEffects.setup_card: card has zero minimum size")
		return null

	var controller := CardEffectController.new()
	controller.card = card
	controller.tilt_strength = tilt_strength
	controller.hover_scale = hover_scale

	# 1. Create SubViewport
	var subviewport := SubViewport.new()
	subviewport.name = "CardEffectViewport"
	subviewport.transparent_bg = true
	subviewport.size = card.custom_minimum_size
	subviewport.gui_disable_input = false
	subviewport.handle_input_locally = false
	card.add_child(subviewport)
	controller.subviewport = subviewport

	# Reparent original children into a VBoxContainer inside the SubViewport
	var inner_container := VBoxContainer.new()
	inner_container.name = "InnerContainer"
	inner_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	subviewport.add_child(inner_container)

	for child in card.get_children():
		if child != subviewport and child != controller:
			card.remove_child(child)
			inner_container.add_child(child)

	# 2. Create TextureRect to display the rendered SubViewport
	var texture_rect := TextureRect.new()
	texture_rect.name = "CardEffectTextureRect"
	texture_rect.anchors_preset = Control.PRESET_FULL_RECT
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = subviewport.get_texture()
	card.add_child(texture_rect)
	controller.texture_rect = texture_rect

	# 3. Create ShaderMaterial and assign
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = HOLO_SHADER
	shader_mat.set_shader_parameter("card_size", card.custom_minimum_size)
	shader_mat.set_shader_parameter("border_width", 0.06)
	shader_mat.set_shader_parameter("tilt_x", 0.0)
	shader_mat.set_shader_parameter("tilt_y", 0.0)
	shader_mat.set_shader_parameter("holo_time", 0.0)
	shader_mat.set_shader_parameter("holo_intensity", 0.0)
	texture_rect.material = shader_mat

	# Add controller as child (handles signals and _process)
	card.add_child(controller)
	if card.is_inside_tree():
		controller._init_signals()

	_controllers[card] = controller
	return controller

static func get_controller(card: Control) -> CardEffectController:
	return _controllers.get(card, null)


class CardEffectController:
	extends Node

	var card: Control = null
	var subviewport: SubViewport = null
	var texture_rect: TextureRect = null
	var tilt_strength: float = DEFAULT_TILT_STRENGTH
	var hover_scale: float = DEFAULT_HOVER_SCALE
	var _hover_tween: Tween = null
	var _icon_zones: Array[Dictionary] = []
	var _active_zone: String = ""

	signal zone_entered(zone_id: String)
	signal zone_exited()

	func _ready() -> void:
		_init_signals()

	func _init_signals() -> void:
		if card.mouse_entered.is_connected(_on_hover_enter):
			return
		card.mouse_entered.connect(_on_hover_enter)
		card.mouse_exited.connect(_on_hover_leave)
		card.tree_exiting.connect(_cleanup)
		set_process(true)

	func _process(_delta: float) -> void:
		var mat := texture_rect.material as ShaderMaterial
		if mat == null:
			return

		var mouse_pos := card.get_local_mouse_position()
		var delta := (mouse_pos - card.size * 0.5) / (card.size * 0.5)

		mat.set_shader_parameter("tilt_x", delta.y * tilt_strength)
		mat.set_shader_parameter("tilt_y", -delta.x * tilt_strength)
		mat.set_shader_parameter("holo_time", fmod(Time.get_ticks_msec() / 1000.0, 1.0))

		# Update SubViewport size if card resized
		if subviewport.size != card.custom_minimum_size:
			subviewport.size = card.custom_minimum_size
			mat.set_shader_parameter("card_size", card.custom_minimum_size)

		# Icon zone hit testing
		_check_icon_zones(mouse_pos)

	func register_zone(zone_id: String, rect: Rect2) -> void:
		_icon_zones.append({"id": zone_id, "rect": rect})

	func clear_zones() -> void:
		_icon_zones.clear()
		_active_zone = ""

	func _check_icon_zones(mouse_pos: Vector2) -> void:
		var found: String = ""
		for zone_dict in _icon_zones:
			var rect: Rect2 = zone_dict["rect"]
			if rect.has_point(mouse_pos):
				found = zone_dict["id"]
				break
		if found != _active_zone:
			if not _active_zone.is_empty():
				zone_exited.emit()
			_active_zone = found
			if not found.is_empty():
				zone_entered.emit(found)

	func _on_hover_enter() -> void:
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()

		var t := card.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

		t.tween_property(card, "scale", Vector2(hover_scale, hover_scale), 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(card, "rotation", deg_to_rad(2.0), 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_method(_set_holo_intensity, _get_holo_intensity(), 1.0, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		t.tween_property(card, "scale", Vector2(1.03, 1.03), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(card, "rotation", 0.0, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

		_hover_tween = t

	func _on_hover_leave() -> void:
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()

		var t := card.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

		t.tween_property(card, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(card, "rotation", 0.0, 0.2) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		t.parallel().tween_method(_set_holo_intensity, _get_holo_intensity(), 0.0, 0.2) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)

		_hover_tween = t

	func _set_holo_intensity(v: float) -> void:
		var mat := texture_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("holo_intensity", v)

	func _get_holo_intensity() -> float:
		var mat := texture_rect.material as ShaderMaterial
		if mat:
			return mat.get_shader_parameter("holo_intensity")
		return 0.0

	func _cleanup() -> void:
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = null
		if card.mouse_entered.is_connected(_on_hover_enter):
			card.mouse_entered.disconnect(_on_hover_enter)
		if card.mouse_exited.is_connected(_on_hover_leave):
			card.mouse_exited.disconnect(_on_hover_leave)
		if card.tree_exiting.is_connected(_cleanup):
			card.tree_exiting.disconnect(_cleanup)
		CardEffects._controllers.erase(card)
```

- [ ] **Step 2: Commit**

```bash
git add src/ui/card_effects.gd
git commit -m "feat: add CardEffects utility with SubViewport pipeline and hover tweens"
```

---

### Task 3: Integrate into weapon_popup.gd

**Files:**
- Modify: `src/ui/weapon_popup.gd`

- [ ] **Step 1: Update imports and remove CARD_GLOW_SHADER preload**

Replace line 8:
```gdscript
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")
```
with:
```gdscript
# (nothing — removed, CardEffects now handles the shader)
```

Remove line 8 entirely.

- [ ] **Step 2: Rewrite `_create_card()` to use CardEffects (lines 291–339)**

Replace the `_create_card()` function body (lines 291–339):

```gdscript
func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_card_input.bind(slot_index))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon == null:
		var empty_label := Label.new()
		empty_label.text = "EMPTY"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		vbox.add_child(empty_label)
	else:
		_add_icon(vbox, weapon)
		var name_label := Label.new()
		name_label.text = weapon.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
		vbox.add_child(name_label)

		var stats := weapon.get_base_stats()
		var cooldown_label := Label.new()
		cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		cooldown_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(cooldown_label)

		var damage_label := Label.new()
		damage_label.text = "Damage: %.0f" % stats["damage"]
		damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		damage_label.add_theme_color_override("font_color", UiTheme.ACCENT)
		damage_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(damage_label)

		_add_modifier_slots(vbox, weapon, card)

	var controller := CardEffects.setup_card(card)
	if controller and weapon != null:
		for i in range(weapon.modifier_slot_count):
			var modifier: Modifier = weapon.get_modifier_at(i)
			if modifier != null:
				_register_modifier_zone(controller, card, i, modifier)

	return card
```

- [ ] **Step 3: Update `_add_modifier_slots()` to remove mouse signals (lines 364–389)**

Replace the function (lines 364–389):

```gdscript
func _add_modifier_slots(parent: VBoxContainer, weapon: Weapon, card: PanelContainer) -> void:
	var slot_container := HBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 4)
	slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(slot_container)

	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			else:
				icon.texture = null
			# Mouse signals now handled by CardEffectController zone system
			icon.gui_input.connect(_on_modifier_icon_input.bind(modifier, icon))
			slot_container.add_child(icon)
		else:
			var empty_slot := ColorRect.new()
			empty_slot.custom_minimum_size = MODIFIER_ICON_SIZE
			empty_slot.color = Color(0.165, 0.082, 0.098, 1)
			slot_container.add_child(empty_slot)
```

- [ ] **Step 4: Add `_register_modifier_zone()` helper and update tooltip handling**

Add these new functions after `_add_modifier_slots` (after line 389):

```gdscript
func _register_modifier_zone(controller: CardEffectController, card: PanelContainer, slot_idx: int, modifier: Modifier) -> void:
	await get_tree().process_frame
	if not is_instance_valid(controller) or not is_instance_valid(card):
		return

	var slot_container: HBoxContainer = _find_modifier_slot_container(card)
	if slot_container == null:
		return

	var icon_index := 0
	for child in slot_container.get_children():
		if child is TextureRect:
			if icon_index == slot_idx:
				var zone_id := "mod_%d" % slot_idx
				var local_pos := _get_rect_in_card(child, card)
				controller.register_zone(zone_id, local_pos)
				_stash_modifier_for_zone(zone_id, modifier, controller)
				# Connect zone signals once
				if not controller.zone_entered.is_connected(_on_modifier_zone_entered):
					controller.zone_entered.connect(_on_modifier_zone_entered.bind(controller))
					controller.zone_exited.connect(_on_modifier_zone_exited.bind(controller))
				return
			icon_index += 1

func _get_rect_in_card(child: Control, card: Control) -> Rect2:
	var global_pos := child.global_position
	var card_global_pos := card.global_position
	return Rect2(global_pos - card_global_pos, child.size)

func _stash_modifier_for_zone(zone_id: String, modifier: Modifier, controller: CardEffectController) -> void:
	var zone_map: Dictionary = controller.get_meta("zone_modifiers", {})
	zone_map[zone_id] = modifier
	controller.set_meta("zone_modifiers", zone_map)
```

- [ ] **Step 5: Replace `_on_modifier_icon_mouse_entered/exited` with zone signal handlers**

Remove `_on_modifier_icon_mouse_entered()` (lines 419–452) and `_on_modifier_icon_mouse_exited()` (lines 454–457), and replace with:

```gdscript
func _on_modifier_zone_entered(zone_id: String, controller: CardEffectController) -> void:
	var zone_map: Dictionary = controller.get_meta("zone_modifiers", {})
	var modifier: Modifier = zone_map.get(zone_id) as Modifier
	if modifier == null:
		return
	_cancel_modifier_tooltip()
	_modifier_tooltip = PanelContainer.new()
	_modifier_tooltip.theme = UiTheme.get_theme()
	_modifier_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_modifier_tooltip.add_child(vbox)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var description := modifier.get_description()
	if description != "":
		var separator := HSeparator.new()
		vbox.add_child(separator)

		var desc_label := Label.new()
		desc_label.text = description
		desc_label.custom_minimum_size.x = TOOLTIP_MAX_WIDTH
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(desc_label)

	add_child(_modifier_tooltip)

	# Position tooltip: find the zone rect from controller
	var zone_rect: Rect2
	var zones: Array[Dictionary] = controller.get("_icon_zones")
	for z in zones:
		if z["id"] == zone_id:
			zone_rect = z["rect"]
			break

	if zone_rect.size != Vector2.ZERO:
		_position_tooltip_at_rect(zone_rect, controller.card)

func _on_modifier_zone_exited(_controller: CardEffectController) -> void:
	_cancel_modifier_tooltip()

func _position_tooltip_at_rect(zone_rect: Rect2, card: Control) -> void:
	if _modifier_tooltip == null:
		return
	await get_tree().process_frame
	var tooltip_size := _modifier_tooltip.get_combined_minimum_size()
	var icon_global := card.global_position + zone_rect.position
	var pos_x := icon_global.x + zone_rect.size.x / 2.0 - tooltip_size.x / 2.0
	var viewport_width := get_viewport().get_visible_rect().size.x
	pos_x = clampf(pos_x, 4.0, viewport_width - tooltip_size.x - 4.0)
	_modifier_tooltip.global_position = Vector2(
		pos_x,
		icon_global.y - tooltip_size.y - 4.0
	)
	_modifier_tooltip.size = tooltip_size
```

- [ ] **Step 6: Rewrite `_create_transfer_card()` to use CardEffects (lines 809–864)**

Replace the function:

```gdscript
func _create_transfer_card(modifier: Modifier, index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()
	card.gui_input.connect(_on_transfer_card_input.bind(index))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if modifier.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = modifier.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = ICON_SIZE
		fallback.color = Color(0.212, 0.110, 0.133, 1)
		vbox.add_child(fallback)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	name_label.modulate.a = 0.0
	vbox.add_child(name_label)

	var text_labels: Array[Label] = [name_label]

	var desc_text := modifier.get_description()
	if desc_text != "":
		var desc_label := Label.new()
		desc_label.text = desc_text
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 24.0
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.modulate.a = 0.0
		vbox.add_child(desc_label)
		text_labels.append(desc_label)

	card.set_meta("transfer_labels", text_labels)

	CardEffects.setup_card(card)

	return card
```

- [ ] **Step 7: Rewrite `_create_remove_modifier_card()` to use CardEffects (lines 551–600)**

Replace the function:

```gdscript
func _create_remove_modifier_card(modifier: Modifier, slot_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme = UiTheme.get_theme()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_remove_modifier_card_input.bind(slot_index))

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	if modifier.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = modifier.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var desc := modifier.get_description()
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(desc_label)

	var slot_label := Label.new()
	slot_label.text = "slot %d" % (slot_index + 1)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	slot_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(slot_label)

	CardEffects.setup_card(card)

	return card
```

- [ ] **Step 8: Remove `_on_card_mouse_entered()` and `_on_card_mouse_exited()`**

Remove these functions entirely (lines 392–416). They are replaced by the CardEffectController's hover handling.

- [ ] **Step 9: Commit**

```bash
git add src/ui/weapon_popup.gd
git commit -m "feat: integrate CardEffects into WeaponPopup cards"
```

---

### Task 4: Integrate into chest_ui.gd

**Files:**
- Modify: `src/ui/chest_ui.gd`

- [ ] **Step 1: Remove CARD_GLOW_SHADER preload**

Remove line 7:
```gdscript
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")
```

- [ ] **Step 2: Rewrite `_create_weapon_card()` (lines 136–200)**

Replace:

```gdscript
func _create_weapon_card(weapon: Weapon, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	card.gui_input.connect(_on_card_gui_input.bind(index, card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon.icon_texture:
		var icon_container := CenterContainer.new()
		icon_container.custom_minimum_size = ICON_SIZE * 1.5
		vbox.add_child(icon_container)

		var icon := TextureRect.new()
		icon.texture = weapon.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(icon)
	else:
		var fallback := CenterContainer.new()
		fallback.custom_minimum_size = ICON_SIZE * 1.5
		vbox.add_child(fallback)
		var q_label := Label.new()
		q_label.text = "?"
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		fallback.add_child(q_label)

	var name_label := Label.new()
	name_label.text = weapon.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	vbox.add_child(name_label)

	var stats := weapon.get_base_stats()
	var cooldown_label := Label.new()
	cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	cooldown_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(cooldown_label)

	var damage_label := Label.new()
	damage_label.text = "Damage: %.0f" % stats["damage"]
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	damage_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(damage_label)

	CardEffects.setup_card(card)

	return card
```

- [ ] **Step 3: Remove `_on_card_mouse_entered()` and `_on_card_mouse_exited()`**

Remove lines 203–226. These are now handled by CardEffectController.

- [ ] **Step 4: Commit**

```bash
git add src/ui/chest_ui.gd
git commit -m "feat: integrate CardEffects into ChestUI cards"
```

---

### Task 5: Integrate into shop_ui.gd

**Files:**
- Modify: `src/economy/shop_ui.gd`

- [ ] **Step 1: Remove CARD_GLOW_SHADER preload**

Remove line 7:
```gdscript
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")
```

- [ ] **Step 2: Rewrite `_create_offer_card()` (lines 263–313)**

Replace:

```gdscript
func _create_offer_card(offer: ShopOffer, slot: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	card.gui_input.connect(_on_card_gui_input.bind(offer, card, slot))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = MODIFIER_ICON_SIZE * 1.6
	vbox.add_child(icon_container)

	if offer.modifier.icon_texture:
		var icon := TextureRect.new()
		icon.texture = offer.modifier.icon_texture
		icon.custom_minimum_size = MODIFIER_ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(icon)

	var name_label := Label.new()
	name_label.text = offer.modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	vbox.add_child(name_label)

	var desc := offer.modifier.get_description()
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(desc_label)

	CardEffects.setup_card(card)

	return card
```

- [ ] **Step 3: Rewrite `_create_remove_card()` (lines 316–365)**

Replace:

```gdscript
func _create_remove_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	card.gui_input.connect(_on_remove_card_input.bind(card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = MODIFIER_ICON_SIZE * 1.6
	vbox.add_child(icon_container)

	var x_label := Label.new()
	x_label.text = "x"
	x_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	x_label.add_theme_color_override("font_color", UiTheme.DANGER)
	x_label.add_theme_font_size_override("font_size", 48)
	icon_container.add_child(x_label)

	var name_label := Label.new()
	name_label.text = "Remove Modifier"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.DANGER)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = "Removes the last modifier from your inventory"
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	desc_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc_label)

	CardEffects.setup_card(card)

	return card
```

- [ ] **Step 4: Remove `_on_card_mouse_entered()` and `_on_card_mouse_exited()`**

Remove lines 549–572. Now handled by CardEffectController.

- [ ] **Step 5: Update sold-card dim logic to not reference glow shader**

In `_on_buy_pressed()` (line ~415), remove:
```gdscript
if card_ref.material is ShaderMaterial:
    card_ref.material.set_shader_parameter("glow_enabled", false)
```
(This is no longer needed since CardEffects handles all visual state.)

- [ ] **Step 6: Commit**

```bash
git add src/economy/shop_ui.gd
git commit -m "feat: integrate CardEffects into ShopUI cards"
```

---

### Task 6: Verification

- [ ] **Step 1: Verify project loads without errors**

Open the project in Godot editor and check the Output panel for errors. Ensure no `push_error` from CardEffects or shader compile failures.

- [ ] **Step 2: Manual smoke test**

Launch the game and:
1. Open the WeaponPopup (press the weapon HUD button) — cards should tilt toward the mouse, show holographic border on hover, springy pop animation
2. Trigger a chest — ChestUI cards should tilt and show effects
3. Visit the shop — ShopUI cards should tilt and show effects

- [ ] **Step 3: Verify modifier tooltips still work**

In the WeaponPopup, hover over a modifier icon on a card — the tooltip should appear correctly.

- [ ] **Step 4: Verify click behavior unchanged**

Test: weapon swap, modifier equip, chest weapon selection, shop purchase. All should work as before.

- [ ] **Step 5: Verify pause behavior**

Pause the game while a card popup is open — hover tweens should still animate (TWEEN_PAUSE_PROCESS).

- [ ] **Step 6: Commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: card effects verification fixes"
```
