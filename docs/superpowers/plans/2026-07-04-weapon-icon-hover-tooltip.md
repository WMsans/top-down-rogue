# Weapon Icon Hover Tooltip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a weapon name + description tooltip when hovering over the weapon icon on a Card, managed entirely by the Card class.

**Architecture:** Add tooltip lifecycle to `Card.gd` — stores title/description, detects icon-area hover in `_process`, creates/destroys a top-level `PanelContainer` tooltip. Consumers opt in with one `set_tooltip_text()` call.

**Tech Stack:** Godot 4 GDScript, existing UiTheme constants

## Global Constraints

- Modifier tooltip in `weapon_popup.gd` must not be touched
- Tooltip styling matches modifier tooltip: name in `UiTheme.ACCENT_GOLD`, description in `UiTheme.TEXT_SECONDARY`, 14pt, 180px max width, word-wrap smart
- Card used for non-weapon purposes (modifier transfer, remove-modifier) must not show a tooltip

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `src/ui/card.gd` | Modify | Self-contained tooltip: store text, detect icon hover, show/hide panel |
| `src/ui/weapon_popup.gd` | Modify | One-line opt-in per weapon card |
| `src/ui/chest_ui.gd` | Modify | One-line opt-in per weapon card |

---

### Task 1: Card.gd — self-contained tooltip

**Files:**
- Modify: `src/ui/card.gd`

**Interfaces:**
- Produces: `signal icon_mouse_entered`, `signal icon_mouse_exited`, `func set_tooltip_text(title: String, description: String) -> void`

- [ ] **Step 1: Add signals and member variables**

Append after `signal card_clicked` at line 4:

```gdscript
signal icon_mouse_entered
signal icon_mouse_exited
```

Append after `var _tilt_was_active: bool = false` at line 44:

```gdscript
var _tooltip_title: String = ""
var _tooltip_description: String = ""
var _weapon_tooltip: PanelContainer = null
var _icon_hovered: bool = false
```

- [ ] **Step 2: Add `set_tooltip_text()` public method**

Append after `_make_sparkle_texture()` (before `_process`):

```gdscript
func set_tooltip_text(title: String, description: String) -> void:
	_tooltip_title = title
	_tooltip_description = description
```

- [ ] **Step 3: Add icon hover detection and tooltip lifecycle to `_process`**

The Card's `_process` already computes `mouse_pos` and checks `mouse_in_card`. Append the icon hover logic after the card-level `_tilt_was_active = true` line (currently line 227):

```gdscript
	var icon_rect := Rect2(_icon.global_position, _icon.size)
	var mouse_in_icon := _icon.visible and icon_rect.has_point(mouse_pos)
	if mouse_in_icon != _icon_hovered:
		_icon_hovered = mouse_in_icon
		if _icon_hovered:
			icon_mouse_entered.emit()
		else:
			icon_mouse_exited.emit()

	if _icon_hovered and _tooltip_title != "":
		_ensure_weapon_tooltip()
	else:
		_cancel_weapon_tooltip()
```

- [ ] **Step 4: Add tooltip creation and cleanup private methods**

Append after `_update_subviewport()` (end of file):

```gdscript
func _ensure_weapon_tooltip() -> void:
	if _weapon_tooltip != null:
		return
	_weapon_tooltip = PanelContainer.new()
	_weapon_tooltip.theme = UiTheme.get_theme()
	_weapon_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_tooltip.top_level = true
	_weapon_tooltip.z_index = 100

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_weapon_tooltip.add_child(vbox)

	var name_label := Label.new()
	name_label.text = _tooltip_title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	if _tooltip_description != "":
		var separator := HSeparator.new()
		vbox.add_child(separator)

		var desc_label := Label.new()
		desc_label.text = _tooltip_description
		desc_label.custom_minimum_size.x = 180.0
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(desc_label)

	add_child(_weapon_tooltip)
	_position_weapon_tooltip()


func _position_weapon_tooltip() -> void:
	if _weapon_tooltip == null:
		return
	await get_tree().process_frame
	if _weapon_tooltip == null or not is_instance_valid(self):
		return
	var card_rect := get_global_rect()
	var tooltip_size := _weapon_tooltip.get_combined_minimum_size()
	var pos_x := card_rect.position.x + card_rect.size.x / 2.0 - tooltip_size.x / 2.0
	var viewport_width := get_viewport().get_visible_rect().size.x
	pos_x = clampf(pos_x, 4.0, viewport_width - tooltip_size.x - 4.0)
	_weapon_tooltip.global_position = Vector2(pos_x, card_rect.position.y - tooltip_size.y - 4.0)
	_weapon_tooltip.size = tooltip_size


func _cancel_weapon_tooltip() -> void:
	if _weapon_tooltip != null:
		_weapon_tooltip.queue_free()
		_weapon_tooltip = null


func _exit_tree() -> void:
	_cancel_weapon_tooltip()
```

- [ ] **Step 5: Run tests to verify nothing is broken**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```

Expected: existing tests pass (card still populates, clicks still emit, no regressions).

- [ ] **Step 6: Commit**

```bash
git add src/ui/card.gd && git commit -m "feat: add self-contained weapon icon hover tooltip to Card"
```

---

### Task 2: Wire tooltip in weapon_popup.gd

**Files:**
- Modify: `src/ui/weapon_popup.gd`

**Interfaces:**
- Consumes: `Card.set_tooltip_text(title, description)` from Task 1

- [ ] **Step 1: Add opt-in call in `_create_card`**

In `_create_card`, inside the `ready` callback, append after `card.set_rarity(weapon.rarity)` (line 284):

```gdscript
			card.set_tooltip_text(weapon.name, weapon.description)
```

This must be inside the `else` branch (non-null weapon), not the `if weapon == null` branch.

Context around the insertion point (lines 274-286):

```gdscript
		else:
			var stats: Array[String] = []
			var base_stats := weapon.get_base_stats()
			stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
			stats.append("Damage: %.0f" % base_stats["damage"])
			var mod_icons: Array[Texture2D] = []
			for i in range(weapon.modifier_slot_count):
				var mod: Modifier = weapon.get_modifier_at(i)
				mod_icons.append(mod.icon_texture if mod else null)
			card.populate(weapon.icon_texture, weapon.name, stats, mod_icons)
			card.set_rarity(weapon.rarity)
			card.set_tooltip_text(weapon.name, weapon.description)
			_add_modifier_slots_to_card(card, weapon)
```

- [ ] **Step 2: Run tests**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add src/ui/weapon_popup.gd && git commit -m "feat: wire weapon tooltip in weapon popup"
```

---

### Task 3: Wire tooltip in chest_ui.gd

**Files:**
- Modify: `src/ui/chest_ui.gd`

**Interfaces:**
- Consumes: `Card.set_tooltip_text(title, description)` from Task 1

- [ ] **Step 1: Add opt-in call in `_build_cards`**

In `_build_cards`, inside the `ready` callback, append after `card.set_rarity(weapon.rarity)` (line 99):

```gdscript
			card.set_tooltip_text(weapon.name, weapon.description)
```

Context around the insertion point (lines 93-100):

```gdscript
		card.ready.connect(func():
			var stats: Array[String] = []
			var base_stats := weapon.get_base_stats()
			stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
			stats.append("Damage: %.0f" % base_stats["damage"])
			card.populate(weapon.icon_texture, weapon.name, stats)
			card.set_rarity(weapon.rarity)
			card.set_tooltip_text(weapon.name, weapon.description)
		, CONNECT_ONE_SHOT)
```

- [ ] **Step 2: Run tests**

```bash
godot --headless --path . --import && \
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/test_card_view.gd
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add src/ui/chest_ui.gd && git commit -m "feat: wire weapon tooltip in chest UI"
```

---

### Task 4: Manual smoke test

No automated test exists for hover tooltip behavior. Verify manually:

- [ ] **Step 1: Weapon popup tooltip**

Open the weapon popup (Tab key in-game). Hover the mouse over the weapon icon on any card. Tooltip should appear above the card showing weapon name in gold + description in secondary text. Move mouse off icon → tooltip disappears. Move to next card's icon → tooltip appears for that weapon.

- [ ] **Step 2: Chest UI tooltip**

Open a chest. Hover the weapon icons on the choice cards. Tooltip should appear for each.

- [ ] **Step 3: Edge cases**

- Empty slot card → no tooltip
- Weapon with no description → tooltip shows name only (no separator/desc)
- Card with no `set_tooltip_text` call (transfer cards in weapon popup) → no tooltip
