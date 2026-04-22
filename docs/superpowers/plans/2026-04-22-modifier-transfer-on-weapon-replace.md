# Modifier Transfer on Weapon Replace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When picking up a weapon drop with full slots, allow the player to choose one modifier from the replaced weapon to transfer to the new weapon, with an animated transition and a skip option.

**Architecture:** Extend `weapon_popup.gd` with a "modifier transfer" sub-mode that activates after weapon slot selection. When the replaced weapon has modifiers, the popup animates the modifier icons from the weapon card up into larger selection cards. Selecting a modifier (or skipping) completes the swap via an updated callback on `weapon_drop.gd`. A convenience method `find_empty_modifier_slot()` is added to `Weapon`.

**Tech Stack:** GDScript, Godot 4.x, existing UI animation utilities (`UiAnimations`)

---

### Task 1: Add `find_empty_modifier_slot()` to Weapon

**Files:**
- Modify: `src/weapons/weapon.gd`

- [ ] **Step 1: Add the convenience method to `weapon.gd`**

Add the following method after `get_modifier_at()` (after line 75):

```gdscript
func find_empty_modifier_slot() -> int:
	for i in range(modifier_slot_count):
		if modifiers[i] == null:
			return i
	return -1
```

- [ ] **Step 2: Commit**

```bash
git add src/weapons/weapon.gd
git commit -m "feat: add find_empty_modifier_slot convenience method to Weapon"
```

---

### Task 2: Add modifier transfer state and logic to WeaponPopup

**Files:**
- Modify: `src/ui/weapon_popup.gd`

This is the core task. The weapon popup needs a new sub-mode for modifier transfer that activates after the player clicks a weapon card in pickup mode (when the replaced weapon has modifiers).

- [ ] **Step 1: Add transfer state variables**

In the variable declarations section (after line 24, after `_feedback_label`), add:

```gdscript
var _transfer_mode: bool = false
var _transfer_slot: int = -1
var _transfer_weapon: Weapon = null
var _transfer_modifiers: Array[Modifier] = []
var _skip_button: Button = null
```

- [ ] **Step 2: Reset transfer state in `close()`**

In the `close()` method, add these lines after `_selected_slot = -1` (after line 84):

```gdscript
	_transfer_mode = false
	_transfer_slot = -1
	_transfer_weapon = null
	_transfer_modifiers = []
```

- [ ] **Step 3: Modify pickup-mode card click to enter transfer mode**

Replace the entire `_on_card_input` method with:

```gdscript
func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			if _transfer_mode:
				pass
			else:
				var replaced_weapon: Weapon = _weapon_manager.weapons[slot_index]
				var transferable_modifiers := _get_transferable_modifiers(replaced_weapon)
				if transferable_modifiers.size() > 0:
					_enter_transfer_mode(slot_index, replaced_weapon, transferable_modifiers)
				else:
					_pickup_callback.call(slot_index, null)
					close()
		elif _modifier_mode:
			_handle_modifier_slot_click(slot_index)
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

- [ ] **Step 4: Add `_get_transferable_modifiers` helper**

Add this method after `_on_card_input`:

```gdscript
func _get_transferable_modifiers(weapon: Weapon) -> Array[Modifier]:
	var result: Array[Modifier] = []
	if weapon == null:
		return result
	for i in range(weapon.modifier_slot_count):
		var mod: Modifier = weapon.get_modifier_at(i)
		if mod != null:
			result.append(mod)
	return result
```

- [ ] **Step 5: Add `_enter_transfer_mode` method**

This method records the global positions of modifier icons on the selected card, clears the cards, and builds the modifier transfer cards with animation. Add after `_get_transferable_modifiers`:

```gdscript
func _enter_transfer_mode(slot_index: int, replaced_weapon: Weapon, transferable_modifiers: Array[Modifier]) -> void:
	var modifier_positions: Array[Vector2] = []
	var modifier_sizes: Array[Vector2] = []
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var card: Control = cards[slot_index]
		var slot_container: HBoxContainer = _find_modifier_slot_container(card)
		if slot_container != null:
			for child in slot_container.get_children():
				if child is TextureRect:
					modifier_positions.append(child.global_position)
					modifier_sizes.append(child.size)
	var alt_positions := _estimate_modifier_positions(transferable_modifiers.size(), modifier_positions, modifier_sizes)
	_transfer_mode = true
	_transfer_slot = slot_index
	_transfer_weapon = replaced_weapon
	_transfer_modifiers = transferable_modifiers
	_title_label.text = "Transfer a modifier?"
	_clear_cards()
	_build_transfer_cards(alt_positions)
	_add_skip_button()
```

- [ ] **Step 6: Add `_find_modifier_slot_container` helper**

This finds the `HBoxContainer` that holds modifier slot icons inside a weapon card. Add after `_enter_transfer_mode`:

```gdscript
func _find_modifier_slot_container(card: Control) -> HBoxContainer:
	for child in card.get_children():
		if child is VBoxContainer:
			for vbox_child in child.get_children():
				if vbox_child is HBoxContainer:
					return vbox_child
	return null
```

- [ ] **Step 7: Add `_estimate_modifier_positions` helper**

When modifier icon positions aren't available (e.g. card was empty), estimate starting positions centered. Add after `_find_modifier_slot_container`:

```gdscript
func _estimate_modifier_positions(count: int, recorded: Array[Vector2], recorded_sizes: Array[Vector2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count == 0:
		return result
	var container_center := _cards_container.global_position + _cards_container.size * 0.5
	for i in range(count):
		if i < recorded.size():
			result.append({
				"position": recorded[i],
				"size": recorded_sizes[i],
			})
		else:
			var offset := Vector2((i - (count - 1) * 0.5) * 50.0, 0.0)
			result.append({
				"position": container_center + offset - Vector2(32, 32),
				"size": Vector2(32, 32),
			})
	return result
```

- [ ] **Step 8: Add `_build_transfer_cards` method**

This creates the modifier selection cards with animation from their starting positions. Add after `_estimate_modifier_positions`:

```gdscript
func _build_transfer_cards(start_positions: Array[Dictionary]) -> void:
	var cards: Array[Control] = []
	for i in range(_transfer_modifiers.size()):
		var modifier: Modifier = _transfer_modifiers[i]
		var card := _create_transfer_card(modifier, i)
		_cards_container.add_child(card)
		cards.append(card)
		if i < start_positions.size():
			var start_pos: Vector2 = start_positions[i]["position"]
			var start_sz: Vector2 = start_positions[i]["size"]
			var target_pos := card.global_position
			var scale_ratio := Vector2(start_sz.x / CARD_MIN_SIZE.x, start_sz.y / CARD_MIN_SIZE.y)
			card.global_position = start_pos
			card.scale = scale_ratio
			card.pivot_offset = card.size * 0.5
			var tween := card.create_tween()
			tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.set_parallel(true)
			tween.tween_property(card, "global_position", target_pos, 0.35).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
			tween.chain().tween_interval(0.1 * i)
	UiAnimations.stagger_slide_in(cards, 0.08, 10.0, 0.2)
```

- [ ] **Step 9: Add `_create_transfer_card` method**

Creates a single modifier selection card. Add after `_build_transfer_cards`:

```gdscript
func _create_transfer_card(modifier: Modifier, index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_transfer_card_input.bind(index))
	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

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
	vbox.add_child(name_label)

	var desc_text := modifier.get_description()
	if desc_text != "":
		var desc_label := Label.new()
		desc_label.text = desc_text
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 24.0
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(desc_label)

	return card
```

- [ ] **Step 10: Add `_on_transfer_card_input` handler**

Add after `_create_transfer_card`:

```gdscript
func _on_transfer_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var chosen_modifier: Modifier = _transfer_modifiers[index]
		_pickup_callback.call(_transfer_slot, chosen_modifier)
		close()
```

- [ ] **Step 11: Add `_add_skip_button` and `_on_skip_pressed`**

Add after `_on_transfer_card_input`:

```gdscript
func _add_skip_button() -> void:
	_cancel_skip_button()
	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip_button.theme = UiTheme.get_theme()
	_skip_button.pressed.connect(_on_skip_pressed)
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox:
		vbox.add_child(_skip_button)
		UiAnimations.fade_in(_skip_button, 0.3, 0.3)


func _on_skip_pressed() -> void:
	_pickup_callback.call(_transfer_slot, null)
	close()


func _cancel_skip_button() -> void:
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null
```

- [ ] **Step 12: Also reset skip button in `close()`**

Add `_cancel_skip_button()` call in `close()`, after `_cancel_feedback()` (line 75):

```gdscript
	_cancel_skip_button()
```

And add reset of the skip button reference:

```gdscript
	_skip_button = null
```

- [ ] **Step 13: Also clear `_cards_container` skip button on clear**

In `_clear_cards()`, add removal of the skip button before clearing cards. Actually, the `_cancel_skip_button()` in `close()` handles cleanup on close. But we also need to handle the case where `_build_cards` is called during transfer mode transitions. Add `_cancel_skip_button()` at the start of `_clear_cards()`:

Add at the start of `_clear_cards()` (after line 130):

```gdscript
	_cancel_skip_button()
```

- [ ] **Step 14: Commit**

```bash
git add src/ui/weapon_popup.gd
git commit -m "feat: add modifier transfer sub-mode to WeaponPopup with animated transition"
```

---

### Task 3: Update WeaponDrop callback to handle modifier transfer

**Files:**
- Modify: `src/drops/weapon_drop.gd`

- [ ] **Step 1: Update `_on_slot_selected` to accept and apply a transferred modifier**

Replace the entire `_on_slot_selected` method with:

```gdscript
func _on_slot_selected(slot_index: int, modifier: Modifier, player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if modifier != null:
		var empty_slot := weapon.find_empty_modifier_slot()
		if empty_slot >= 0:
			weapon.add_modifier(empty_slot, modifier)
	weapon_manager.swap_weapon(slot_index, weapon)
	queue_free()
```

- [ ] **Step 2: Commit**

```bash
git add src/drops/weapon_drop.gd
git commit -m "feat: apply transferred modifier to new weapon on pickup replace"
```

---

### Task 4: Handle edge case — new weapon has no empty modifier slots

If the new weapon has all modifier slots filled, the transferred modifier should replace the modifier in slot 0 (first slot). The `_on_slot_selected` code above already handles this: `find_empty_modifier_slot()` returns -1 if no slots are empty, and `add_modifier(slot_index, modifier)` overwrites whatever is at that index. We need to handle the `-1` case.

**Files:**
- Modify: `src/drops/weapon_drop.gd`

- [ ] **Step 1: Update the modifier slot assignment to handle the full-slots case**

In `weapon_drop.gd`, replace the modifier application block in `_on_slot_selected`:

```gdscript
func _on_slot_selected(slot_index: int, modifier: Modifier, player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if modifier != null:
		var empty_slot := weapon.find_empty_modifier_slot()
		if empty_slot >= 0:
			weapon.add_modifier(empty_slot, modifier)
		else:
			weapon.add_modifier(0, modifier)
	weapon_manager.swap_weapon(slot_index, weapon)
	queue_free()
```

- [ ] **Step 2: Amend the previous commit**

```bash
git add src/drops/weapon_drop.gd
git commit --amend -m "feat: apply transferred modifier to new weapon on pickup replace"
```

---

### Task 5: Handle overlay click during transfer mode

Currently clicking the overlay closes the popup. During transfer mode, clicking the overlay should also close the popup and cancel the pickup (no swap happens). This is the existing behavior and works correctly since `close()` resets all state. No change needed.

However, pressing the pause key during transfer mode should also close the popup. This is already handled by `_unhandled_input`. No change needed.

### Task 6: Update the `_build_cards` call during transfer mode to also skip modifier header

Currently, `_build_cards()` adds a modifier header in modifier mode. In transfer mode, we build different cards via `_build_transfer_cards()`, so the `_build_cards()` path is not taken. No change needed.

### Task 7: Manual testing checklist

- [ ] **Verify in-game:**
  1. Pick up a weapon drop when all 3 slots are filled and the selected weapon has modifiers → modifier transfer view appears with animated cards
  2. Click a modifier card → modifier transfers to new weapon, swap completes
  3. Click "Skip" → swap completes without modifier transfer
  4. Pick up a weapon drop when all 3 slots filled but selected weapon has no modifiers → swap happens immediately (no transfer step)
  5. The popup closes correctly in all cases
  6. The "Skip" button fades in after cards animate