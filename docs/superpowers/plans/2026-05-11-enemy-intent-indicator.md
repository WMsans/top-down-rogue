# Enemy Intent Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a red `!` indicator above enemies during their WINDUP state, telegraphing incoming attacks — classic Soul Knight style.

**Architecture:** A standalone `IntentIndicator` scene (Node2D + Label) handles all its own animation (flash-in, idle pulse, exit) via tweens. The base `Enemy` class instantiates it on entering WINDUP and triggers `hide_indicator()` when leaving WINDUP. The scene self-destructs after exit animation.

**Tech Stack:** Godot 4.6, GDScript, pixel font (`SDS_8x8.ttf`)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/fx/intent_indicator.gd` | Create | Script: animation lifecycle (show/hide/idle) |
| `scenes/fx/intent_indicator.tscn` | Create | Scene: Node2D root + Label child |
| `src/enemies/enemy.gd` | Modify | Integration: instantiate on WINDUP entry, hide on exit |

---

### Task 1: Create intent indicator script

**Files:**
- Create: `src/fx/intent_indicator.gd`

- [ ] **Step 1: Write the script**

```gdscript
extends Node2D

const FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

@onready var label: Label = $Label

var _show_tween: Tween = null
var _idle_tween: Tween = null

func _ready() -> void:
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = 14
	settings.font_color = Color(1.0, 0.1, 0.1, 1.0)
	settings.outline_size = 2
	settings.outline_color = Color(0, 0, 0, 1)
	label.label_settings = settings
	label.text = "!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	modulate.a = 0.0
	scale = Vector2.ZERO


func show_indicator() -> void:
	_kill_tweens()
	visible = true
	_show_tween = create_tween().set_process_mode(Tween.TWEEN_PAUSE_PROCESS)
	_show_tween.set_parallel(true)
	_show_tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.08).from(Vector2.ZERO).set_ease(Tween.EASE_OUT)
	_show_tween.tween_property(self, "modulate:a", 1.0, 0.08).from(0.0)
	_show_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.07).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_show_tween.chain().tween_callback(_start_idle)


func hide_indicator() -> void:
	_kill_tweens()
	var t := create_tween().set_process_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2.ZERO, 0.1).set_ease(Tween.EASE_IN)
	t.tween_property(self, "modulate:a", 0.0, 0.1).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)


func _start_idle() -> void:
	_idle_tween = create_tween().set_process_mode(Tween.TWEEN_PAUSE_PROCESS).set_loops()
	_idle_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _kill_tweens() -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
```

- [ ] **Step 2: Commit**

```bash
git add src/fx/intent_indicator.gd
git commit -m "feat: add intent indicator script"
```

---

### Task 2: Create intent indicator scene

**Files:**
- Create: `scenes/fx/intent_indicator.tscn`

- [ ] **Step 1: Write the scene file**

```gdscript
[gd_scene format=3 uid="uid://intent_indicator"]

[node name="IntentIndicator" type="Node2D"]
script = "res://src/fx/intent_indicator.gd"

[node name="Label" type="Label" parent="."]
offset_left = -16.0
offset_top = -8.0
offset_right = 16.0
offset_bottom = 8.0
text = "!"
horizontal_alignment = 1
vertical_alignment = 1
```

> Note: The `Label` offset values create an approximate 32×16 bounding rect. The `label_settings` (font, color, outline) are set programmatically in the script's `_ready()`.

- [ ] **Step 2: Commit**

```bash
git add scenes/fx/intent_indicator.tscn
git commit -m "feat: add intent indicator scene"
```

---

### Task 3: Integrate indicator into enemy base class

**Files:**
- Modify: `src/enemies/enemy.gd:30-49` (add field), `src/enemies/enemy.gd:268-285` (modify `_change_state`), `src/enemies/enemy.gd:420-422` (add helper methods at end)

- [ ] **Step 1: Preload the indicator scene and add a tracking field**

Add the preload and field after the existing private vars (after line 50, before `func _ready()`):

```gdscript
const INDICATOR_SCENE := preload("res://scenes/fx/intent_indicator.tscn")
var _intent_indicator: Node2D = null
```

- [ ] **Step 2: Add show/hide in `_change_state`**

Modify `_change_state` to manage the indicator lifecycle. Replace the existing `_change_state` function (lines 268-285) with:

```gdscript
func _change_state(new_state: int) -> void:
	if new_state == State.HURT:
		_prev_state = _state
		_state = new_state
		_state_timer = hurt_duration
		_cleanup_indicator()
		return

	if _state == State.WINDUP and new_state != State.WINDUP:
		_cleanup_indicator()

	_state = new_state
	match new_state:
		State.WINDUP:
			_state_timer = windup_duration
			_settle_timer = 0.0
			_show_intent_indicator()
		State.COOLDOWN:
			_state_timer = cooldown_duration
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
```

- [ ] **Step 3: Add helper methods for indicator lifecycle**

Add the following methods before `_on_death()` (after line 420):

```gdscript
func _show_intent_indicator() -> void:
	if not is_inside_tree():
		return
	var indicator: Node2D = INDICATOR_SCENE.instantiate()
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		indicator.position = sprite.position + Vector2(0, -16)
	add_child(indicator)
	_intent_indicator = indicator
	indicator.show_indicator()


func _cleanup_indicator() -> void:
	if _intent_indicator and is_instance_valid(_intent_indicator):
		_intent_indicator.hide_indicator()
	_intent_indicator = null
```

- [ ] **Step 4: Commit**

```bash
git add src/enemies/enemy.gd
git commit -m "feat: integrate intent indicator into enemy WINDUP state"
```

---

### Task 4: Verify in-game

- [ ] **Step 1: Run the project**

```bash
# Open in Godot editor and run, or use headless:
# godot --headless --quit 2>&1 | head -20
```

Since this is a Godot game project without automated tests, verify by:
1. Running the game
2. Approaching enemies to trigger their chase → windup sequence
3. Confirming a red `!` appears above enemies during windup with a scale-in flash
4. Confirming the `!` pulses gently during windup
5. Confirming the `!` disappears (scale+fade out) when the attack fires or the enemy is interrupted

- [ ] **Step 2: Verify edge cases**
  - Kill an enemy during windup — indicator should disappear
  - Multiple enemies windup simultaneously — each shows own indicator
  - Pause during windup — indicator pauses and resumes correctly
  - Boss enemy — same behavior as regular enemies
  - Elite enemies (1.3x scale) — indicator position scales correctly
