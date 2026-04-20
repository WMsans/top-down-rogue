# Modifier Full-Slots Visual Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a player tries to pick up a modifier drop while all modifier slots are full, the weapon button icon flashes a red outline and plays a bouncy jitter animation.

**Architecture:** `ModifierDrop._pickup()` detects the full-slots condition and calls `flash_slots_full()` on the `WeaponButton` node (found via the same tree path used to find `WeaponPopup`). `WeaponButton` owns the outline panel (a `Panel` child of `_icon_button`) and delegates animation to a new `UiAnimations.jitter_bounce()` static function.

**Tech Stack:** Godot 4, GDScript, Tween API (`create_tween`, `TRANS_BACK`, `EASE_OUT`), `StyleBoxFlat` for border rendering.

---

## Files

- Modify: `src/ui/ui_animations.gd` — add `jitter_bounce()` static function
- Modify: `src/ui/weapon_button.gd` — add outline Panel creation and `flash_slots_full()` method
- Modify: `src/drops/modifier_drop.gd` — trigger `flash_slots_full()` on full-slots fail

---

### Task 1: Add `jitter_bounce()` to `UiAnimations`

**Files:**
- Modify: `src/ui/ui_animations.gd`

- [ ] **Step 1: Add the static function before `_update_pivot_center`**

In `src/ui/ui_animations.gd`, add after the `pulse_glow` function (before `stagger_slide_in`):

```gdscript
static func jitter_bounce(control: Control, duration: float = 0.35) -> Tween:
	_update_pivot_center(control)
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var step := duration / 4.0
	tween.tween_property(control, "scale", Vector2(1.12, 0.88), step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2(0.88, 1.12), step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2(1.06, 0.94), step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween
```

- [ ] **Step 2: Verify the file parses (open Godot editor or run `godot --headless --check-only`)**

The file should have no syntax errors. Confirm the function appears between `pulse_glow` and `stagger_slide_in`.

- [ ] **Step 3: Commit**

```bash
git add src/ui/ui_animations.gd
git commit -m "feat: add jitter_bounce animation to UiAnimations"
```

---

### Task 2: Add red outline Panel and `flash_slots_full()` to `WeaponButton`

**Files:**
- Modify: `src/ui/weapon_button.gd`

- [ ] **Step 1: Add member variables for outline and flash tween**

In `src/ui/weapon_button.gd`, add two new member variables after the existing `var _current_weapon: Weapon = null` line:

```gdscript
var _outline_panel: Panel = null
var _flash_tween: Tween = null
```

- [ ] **Step 2: Add `_create_outline_panel()` helper**

Add this private function at the bottom of `src/ui/weapon_button.gd`:

```gdscript
func _create_outline_panel() -> Panel:
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.2, 0.2, 1.0)
	style.draw_center = false
	p.add_theme_stylebox_override("panel", style)
	_icon_button.add_child(p)
	return p
```

- [ ] **Step 3: Call `_create_outline_panel()` at the end of `_ready()`**

In `_ready()`, after the block that calls `_update_display`, add:

```gdscript
	_outline_panel = _create_outline_panel()
```

The end of `_ready()` should now look like:

```gdscript
	if _weapon_manager != null:
		_weapon_manager.weapon_activated.connect(_on_weapon_activated)
		_update_display(_weapon_manager.active_slot)
	_outline_panel = _create_outline_panel()
```

- [ ] **Step 4: Add `flash_slots_full()` method**

Add this public function at the bottom of `src/ui/weapon_button.gd`:

```gdscript
func flash_slots_full() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_outline_panel.visible = true
	UiAnimations.jitter_bounce(_icon_button)
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_interval(0.8)
	_flash_tween.tween_callback(func() -> void: _outline_panel.visible = false)
```

- [ ] **Step 5: Verify the file parses**

Open Godot or run syntax check. Confirm no errors.

- [ ] **Step 6: Commit**

```bash
git add src/ui/weapon_button.gd
git commit -m "feat: add red outline flash and jitter animation to WeaponButton"
```

---

### Task 3: Trigger `flash_slots_full()` from `ModifierDrop`

**Files:**
- Modify: `src/drops/modifier_drop.gd`

- [ ] **Step 1: Replace silent return with feedback call**

In `src/drops/modifier_drop.gd`, replace the body of `_pickup()`:

**Before:**
```gdscript
func _pickup(player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if not _has_weapon_with_empty_slot(weapon_manager):
		return
	var popup = player.get_parent().get_node("WeaponPopup")
	popup.open_for_modifier(weapon_manager, modifier, _on_modifier_applied)
```

**After:**
```gdscript
func _pickup(player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if not _has_weapon_with_empty_slot(weapon_manager):
		var weapon_button := player.get_parent().get_node_or_null("WeaponButton")
		if weapon_button != null:
			weapon_button.flash_slots_full()
		return
	var popup = player.get_parent().get_node("WeaponPopup")
	popup.open_for_modifier(weapon_manager, modifier, _on_modifier_applied)
```

- [ ] **Step 2: Verify the file parses**

Open Godot or run syntax check. Confirm no errors.

- [ ] **Step 3: Manual test — happy path (slots not full)**

1. Run the game
2. Pick up a modifier drop when a weapon has an empty modifier slot
3. Confirm the weapon popup opens normally — no animation fires

- [ ] **Step 4: Manual test — full slots feedback**

1. Fill all modifier slots on all weapons (equip 3 modifiers per weapon for every weapon slot)
2. Approach a modifier drop and press interact
3. Confirm:
   - The weapon button icon gets a red 2px border
   - The icon plays a squash-and-stretch jitter animation (~0.35s)
   - The red border disappears after ~0.8s
   - The weapon popup does NOT open
   - The tooltip still works normally after the animation

- [ ] **Step 5: Manual test — rapid re-trigger**

1. With full slots, spam the interact button near a modifier drop multiple times quickly
2. Confirm the animation resets cleanly each time (no stuck outline, no doubled tweens)

- [ ] **Step 6: Commit**

```bash
git add src/drops/modifier_drop.gd
git commit -m "feat: flash weapon button when modifier slots are full"
```
