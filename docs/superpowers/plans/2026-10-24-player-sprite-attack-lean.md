# Player Sprite & Attack Lean Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the player's `ColorRect` placeholder with an `AnimatedSprite2D` driven by the new idle/run sheets, and add a feet-pivoted skew/stretch tween toward the attack direction on every fired attack.

**Architecture:** A generated `SpriteFrames` `.tres` holds 8 looping animations (idle/run × front/back × left/right). `PlayerController` picks the animation each physics frame from facing and input, and owns the lean tween; `Weapon.use()` calls `user.play_attack_lean(dir)` after an attack fires. All existing juice (hit flash, squash, tints, invincibility blink) retargets from the `ColorRect` to the sprite.

**Tech Stack:** Godot 4 / GDScript, gdUnit4.

**Spec:** `docs/superpowers/specs/2026-10-24-player-sprite-attack-lean-design.md`

## Global Constraints

- Frames are 32×32. Idle: 20 frames on every row. Run: 18 frames on rows 0 and 2, 16 on rows 1 and 3.
- Rows: 0 front-left, 1 back-left, 2 front-right, 3 back-right.
- Sprite drawn at native size — never scaled down. Collision stays 8×12.
- Sprite node origin at the feet: `position = Vector2(0, 6)` (hitbox bottom), `offset = Vector2(0, -15)` (32px frame, feet at y≈30–31, so the frame's bottom edge lands about 1px below the node).
- Animation names: `idle_front_left`, `idle_back_left`, `idle_front_right`, `idle_back_right`, `run_front_left`, `run_back_left`, `run_front_right`, `run_back_right`. All loop. Idle 10 fps, run 15 fps.
- Left/right comes from the sheet rows — **no** `flip_h` and **no** negative `scale.x` anywhere.
- Lean: ~0.05s out, ~0.15s back with `TRANS_ELASTIC`/`EASE_OUT`. Hit squash kills any in-progress lean.
- Tests: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <test path>` (run `godot --headless --path . --import` first in a fresh worktree).

## Review Focus

1. Player facing left — sprite must not be mirrored by the old `scale.x = -1` code (`player_controller.gd:139-140`, `_play_squash` `sgn`). Pinned by `test_squash_keeps_positive_scale` (Task 1).
2. Invincibility blink and death/respawn visibility in `player_inventory.gd` (lines 46, 55, 75–79, 164) look up the node by name `"ColorRect"` — they must find the sprite or the blink silently stops. Pinned by `test_inventory_finds_sprite` (Task 1).
3. Weapons called with `null` user (existing tests do `w.on_press(null)`) — the lean hook must not crash. Pinned by `test_use_with_null_user_does_not_crash` (Task 2).
4. Getting hit mid-lean — the squash must win and the sprite must end at rest (`skew 0`, `scale (1,1)`). Pinned by `test_squash_kills_lean` (Task 2).
5. Perfectly vertical attack (`dir.x == 0`) — skew sign follows facing side, not 0. Pinned in `test_lean_target_*` (Task 2).

---

### Task 1: Sprite sheet animations replace the ColorRect

**Files:**
- Create: `textures/Player/player_sprite_frames.tres` (generated; plus the `.png.import` files Godot creates)
- Modify: `scenes/player.tscn` (replace `ColorRect` node)
- Modify: `src/player/player_controller.gd` (`_color_rect` → `_sprite`, animation selection, drop mirroring)
- Modify: `src/player/player_inventory.gd:34,46` (look up `"Sprite"`; type `CanvasItem`)
- Test: `tests/unit/test_player_controller.gd`, `tests/unit/test_player_sprite.gd`

**Interfaces:**
- Produces: `PlayerController._sprite: AnimatedSprite2D` (node named `Sprite`); `static func anim_name(facing: Vector2, facing_left: bool, moving: bool) -> StringName` on `PlayerController`.

- [ ] **Step 1: Generate the SpriteFrames resource**

Write a one-off script in the scratchpad (not committed) that emits a Godot text resource: `[gd_resource type="SpriteFrames" format=3]`, two `ext_resource` `Texture2D` entries for the sheets, one `AtlasTexture` sub_resource per frame (`region = Rect2(col*32, row*32, 32, 32)`), and a `[resource]` with `animations = [...]` per the Global Constraints. Then run `godot --headless --path . --import` and confirm it exits 0 and the `.png.import` files appear.

- [ ] **Step 2: Write failing tests**

In `tests/unit/test_player_sprite.gd`:

```gdscript
func test_sprite_frames_have_all_animations() -> void:
	var frames: SpriteFrames = load("res://textures/Player/player_sprite_frames.tres")
	for a in ["idle", "run"]:
		for d in ["front_left", "back_left", "front_right", "back_right"]:
			assert_bool(frames.has_animation("%s_%s" % [a, d])).is_true()
	assert_int(frames.get_frame_count(&"idle_back_right")).is_equal(20)
	assert_int(frames.get_frame_count(&"run_front_left")).is_equal(18)
	assert_int(frames.get_frame_count(&"run_back_left")).is_equal(16)
	assert_float(frames.get_animation_speed(&"run_front_right")).is_equal(15.0)

func test_anim_name() -> void:
	assert_str(PlayerController.anim_name(Vector2.DOWN, false, false)).is_equal("idle_front_right")
	assert_str(PlayerController.anim_name(Vector2.UP, true, true)).is_equal("run_back_left")
	assert_str(PlayerController.anim_name(Vector2(-1, 0), true, false)).is_equal("idle_front_left")

func test_scene_uses_sprite() -> void:
	var p: Node = auto_free(load("res://scenes/player.tscn").instantiate())
	assert_object(p.get_node_or_null("ColorRect")).is_null()
	var s: AnimatedSprite2D = p.get_node("Sprite")
	assert_vector(s.position).is_equal(Vector2(0, 6))
	assert_vector(s.offset).is_equal(Vector2(0, -15))

func test_inventory_finds_sprite() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	var sprite := AnimatedSprite2D.new(); sprite.name = "Sprite"; parent.add_child(sprite)
	var inv := PlayerInventory.new(); parent.add_child(inv)
	inv._ready()
	assert_object(inv._sprite).is_same(sprite)  # field renamed from _color_rect
```

In `tests/unit/test_player_controller.gd`: replace `controller._color_rect = auto_free(ColorRect.new())` with `controller._sprite = auto_free(AnimatedSprite2D.new())`, and add:

```gdscript
func test_squash_keeps_positive_scale() -> void:
	var controller: PlayerController = auto_free(PlayerController.new())
	controller._sprite = auto_free(AnimatedSprite2D.new())
	controller._facing_left = true
	controller._play_squash()
	controller._squash_tween.custom_step(0.03)  # mid-squash; tweens don't auto-run out of tree
	assert_float(controller._sprite.scale.x).is_greater(0.0)
	controller._squash_tween.custom_step(1.0)
	assert_vector(controller._sprite.scale).is_equal(Vector2.ONE)
```

- [ ] **Step 3: Run tests to verify they fail**

Run the gdUnit command on both files. Expected: FAIL (missing `.tres` animations / `anim_name` / `_sprite`).

- [ ] **Step 4: Implement**

- `player.tscn`: delete `ColorRect`; add `AnimatedSprite2D` named `Sprite` with the `.tres`, `animation = &"idle_front_right"`, `autoplay = "idle_front_right"`, position/offset per Global Constraints.
- `player_controller.gd`: `@onready var _sprite: AnimatedSprite2D = $Sprite`; delete the `pivot_offset` line in `_ready`; replace lines 139–140 with `_sprite.play(anim_name(_last_facing, _facing_left, input_dir != Vector2.ZERO))` (use the raw input direction, before status multipliers; `play()` with the current name is a no-op so this is safe per frame); all other `_color_rect` uses → `_sprite`; `_play_squash` uses `Vector2(1.3, 0.7)` → `Vector2.ONE` with no `sgn`.
- `anim_name`: back when `facing.y < 0`, else front; side from `facing_left`.
- `player_inventory.gd`: rename `_color_rect` → `_sprite: CanvasItem`, look up `"Sprite"` (check how `_ready` finds `parent_player` around line 46 and match the test's parent setup to it).

- [ ] **Step 5: Run tests to verify they pass**

Run both test files plus `tests/unit/test_player_dash.gd` and `tests/unit/test_player_inventory.gd`. Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add textures/Player scenes/player.tscn src/player tests/unit
git commit -m "feat(player): animated sprite replaces placeholder"
```

---

### Task 2: Attack lean tween

**Files:**
- Modify: `src/player/player_controller.gd` (lean helpers + tween, squash kills lean)
- Modify: `src/weapons/weapon.gd:25-37` (`use()` calls the hook)
- Test: `tests/unit/test_player_sprite.gd`, `tests/unit/test_weapon_lean.gd`

**Interfaces:**
- Consumes: `PlayerController._sprite` (Task 1).
- Produces: `func play_attack_lean(direction: Vector2) -> void`; `static func lean_target(direction: Vector2, facing_left: bool) -> Dictionary` returning `{"skew": float, "scale": Vector2}`; `var _lean_tween: Tween`.

Positive `Node2D.skew` tilts the top of the sprite to the right (verify by eye once and flip the sign if wrong).

- [ ] **Step 1: Write failing tests**

```gdscript
# test_player_sprite.gd
func test_lean_target_right_is_mostly_skew() -> void:
	var t := PlayerController.lean_target(Vector2.RIGHT, false)
	assert_float(t.skew).is_greater(0.2)
	assert_float(t.scale.y).is_between(1.0, 1.1)

func test_lean_target_left_skews_negative() -> void:
	assert_float(PlayerController.lean_target(Vector2.LEFT, false).skew).is_less(-0.2)

func test_lean_target_up_is_mostly_stretch() -> void:
	var t := PlayerController.lean_target(Vector2.UP, true)
	assert_float(t.scale.y).is_greater(1.2)
	assert_float(t.scale.x).is_less(1.0)
	assert_float(t.skew).is_between(-0.15, -0.01)  # small, toward facing (left)

func test_lean_target_down_facing_right_skews_right() -> void:
	var t := PlayerController.lean_target(Vector2.DOWN, false)
	assert_float(t.scale.y).is_greater(1.2)
	assert_float(t.skew).is_between(0.01, 0.15)

func test_squash_kills_lean() -> void:
	# controller + _sprite wired by hand as in test_player_controller.gd
	controller.play_attack_lean(Vector2.RIGHT)
	controller._play_squash()
	assert_bool(controller._lean_tween == null or not controller._lean_tween.is_valid()).is_true()

# test_weapon_lean.gd — inner class LeanSpy extends Node2D with
# get_facing_direction() -> Vector2.LEFT and play_attack_lean(d) appending to `dirs`
func test_use_calls_lean_with_facing() -> void:
	var w := TestWeapon.new(); var spy = auto_free(LeanSpy.new())
	w.use(spy)
	assert_array(spy.dirs).contains_exactly([Vector2.LEFT])

func test_use_on_cooldown_does_not_lean() -> void:
	# second immediate use() is blocked by cooldown → still exactly one call

func test_use_with_null_user_does_not_crash() -> void:
	TestWeapon.new().use(null)  # passes if no error
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL (`lean_target` / `play_attack_lean` / `_lean_tween` undefined; spy gets no calls).

- [ ] **Step 3: Implement**

- `lean_target`: with `ax = abs(dir.x)`, `ay = abs(dir.y)` of the normalized dir, side = `sign(dir.x)` or, when `ax < 0.01`, `-1` if `facing_left` else `1`:
  `skew = side * (LEAN_SKEW_H * ax + LEAN_SKEW_V * ay)`, `scale = Vector2(1 - LEAN_THIN * ay, 1 + LEAN_STRETCH_H * ax + LEAN_STRETCH_V * ay)`.
  Consts: `LEAN_SKEW_H := 0.35`, `LEAN_SKEW_V := 0.08`, `LEAN_STRETCH_H := 0.06`, `LEAN_STRETCH_V := 0.3`, `LEAN_THIN := 0.15`. Zero-length dir → rest (`skew 0`, `Vector2.ONE`).
- `play_attack_lean`: kill existing `_lean_tween`; parallel tween `skew`/`scale` to target over `0.05`, then chain back to `0.0`/`Vector2.ONE` over `0.15` elastic ease-out. Skip if `_sprite == null` or the squash tween is running.
- `_play_squash`: kill `_lean_tween` and reset `_sprite.skew = 0.0` first.
- `Weapon.use()`: after `_use_impl` (only reached past `is_ready()`), `if user != null and user.has_method("play_attack_lean") and user.has_method("get_facing_direction"): user.play_attack_lean(user.get_facing_direction())`. Keep it after the suppress check too (a suppressed base use still counts as the attack firing via modifiers).

- [ ] **Step 4: Run tests to verify they pass**

Run `tests/unit/test_player_sprite.gd`, `tests/unit/test_weapon_lean.gd`, `tests/unit/test_player_controller.gd`, then the whole `tests/unit` dir. Expected: all PASS.

- [ ] **Step 5: Eyeball it**

Run the game, attack in all 8 directions while facing each way: feet stay planted, top leans/stretches toward the attack, springs back. Tune the `LEAN_*` consts by eye if needed (keep tests' ranges true).

- [ ] **Step 6: Commit**

```bash
git add src/player/player_controller.gd src/weapons/weapon.gd tests/unit
git commit -m "feat(player): lean sprite toward attack direction"
```
