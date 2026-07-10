# Exaggerated Enemy Hurt Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the enemy's on-hit body reaction exaggerated — a big jelly (elastic-spring) squash-stretch plus a directional recoil snap that springs back like 1940s animation.

**Architecture:** All work is in `src/enemies/enemy.gd` (Approach A from the spec). The `Sprite2D` child's `scale`, `rotation`, and `position` are animated with `Tween`s; the physics body, collision, and movement are untouched. Hit direction is plumbed from `on_hit_impact` into `_on_hit` via a `_last_hit_dir` member. Death entry kills the hurt tweens and resets the sprite transform so `_process_death` owns it exclusively.

**Tech Stack:** Godot 4 / GDScript, gdUnit4 for tests.

## Global Constraints

- Only the `Sprite2D` child transform is animated — never `global_position`, the `CharacterBody2D`, or collision.
- Base sprite `scale` is `Vector2.ONE`; base `position`/`rotation` are captured once in `_ready`.
- No code comments unless a line is genuinely non-obvious (matches file style).
- Fresh worktrees have no `.godot/` import cache: run `godot --headless --path . --import` once before the first test run.
- Tests run via the wrapper with `GODOT_BIN` set: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`. Headless boot takes ~30-60s before output — wait for it.
- A `Nonexistent function 'new' in base 'GDScript'` crash means a parse error; scroll up for the real `SCRIPT ERROR: Parse Error` line.

---

### Task 1: Amplified squash-stretch (elastic spring)

Replace the modest `(1.4, 0.7)` squash with a big `(1.65, 0.6)` stretch that elastic-springs back to `(1, 1)`.

**Files:**
- Modify: `src/enemies/enemy.gd` (constants block near line 46-47; `_play_squash` near line 862-872)
- Test: `tests/unit/test_enemy_visual_identity.gd` (append)

**Interfaces:**
- Consumes: existing `_squash_tween: Tween` member, existing `_play_squash()` call site in `_on_hit`.
- Produces: `const SQUASH_STRETCH: Vector2 = Vector2(1.65, 0.6)`, `const SETTLE_DURATION: float = 0.32`. Removes `SQUASH_SCALE` and `SQUASH_DURATION`. `_play_squash()` snaps `Sprite2D.scale` to `SQUASH_STRETCH` synchronously, then tweens to `Vector2.ONE` over `SETTLE_DURATION`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_hit_snaps_squash_to_stretch() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	add_child(e)
	await get_tree().process_frame
	e.health = 100
	e.hit(5)
	assert_that(sprite.scale).is_equal(Enemy.SQUASH_STRETCH)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
Expected: FAIL — `Enemy.SQUASH_STRETCH` does not exist yet (parse error or invalid identifier).

- [ ] **Step 3: Replace the constants**

In `src/enemies/enemy.gd`, replace these two lines:

```gdscript
const SQUASH_SCALE: Vector2 = Vector2(1.4, 0.7)
const SQUASH_DURATION: float = 0.18
```

with:

```gdscript
const SQUASH_STRETCH: Vector2 = Vector2(1.65, 0.6)
const SETTLE_DURATION: float = 0.32
```

- [ ] **Step 4: Update `_play_squash` to use the new constants**

In `src/enemies/enemy.gd`, replace the body of `_play_squash`:

```gdscript
func _play_squash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	sprite.scale = SQUASH_STRETCH
	_squash_tween = create_tween()
	_squash_tween.set_trans(Tween.TRANS_ELASTIC)
	_squash_tween.set_ease(Tween.EASE_OUT)
	_squash_tween.tween_property(sprite, "scale", Vector2.ONE, SETTLE_DURATION)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
Expected: PASS (all tests in the suite, including the new one).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: amplify enemy squash-stretch with elastic spring"
```

---

### Task 2: Directional recoil (snap + spring settle)

The sprite snaps/leans in the hit direction and jolts along it, then elastic-springs both `rotation` and `position` back to base. Zero-direction hits skip recoil.

**Files:**
- Modify: `src/enemies/enemy.gd` (member vars near line 63-71; constants block; `_ready` near line 117; `on_hit_impact` near line 802; `_on_hit` near line 875)
- Test: `tests/unit/test_enemy_visual_identity.gd` (append)

**Interfaces:**
- Consumes: `SETTLE_DURATION` (from Task 1), existing `_on_hit()` and `on_hit_impact(impact_point, hit_dir, damage)`.
- Produces:
  - Members: `_recoil_tween: Tween`, `_last_hit_dir: Vector2`, `_sprite_base_position: Vector2`, `_sprite_base_rotation: float`.
  - Constants: `RECOIL_ANGLE: float = 0.4`, `RECOIL_OFFSET: float = 5.0`.
  - `_play_recoil(hit_dir: Vector2) -> void`: no-ops when `hit_dir` is ~zero; otherwise snaps `Sprite2D.rotation` to `_sprite_base_rotation + sign * RECOIL_ANGLE` (sign `+1` if `hit_dir.x >= 0` else `-1`) and `Sprite2D.position` to `_sprite_base_position + hit_dir.normalized() * RECOIL_OFFSET`, then elastic-springs both back.
  - `on_hit_impact` sets `_last_hit_dir = hit_dir` before calling `hit(damage)`. `_on_hit` calls `_play_recoil(_last_hit_dir)` then resets `_last_hit_dir = Vector2.ZERO`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_hit_leans_sprite_toward_right_hit() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	add_child(e)
	await get_tree().process_frame
	e.health = 100
	e._last_hit_dir = Vector2.RIGHT
	e.hit(5)
	assert_float(sprite.rotation - e._sprite_base_rotation).is_greater(0.0)


func test_hit_leans_sprite_toward_left_hit() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	add_child(e)
	await get_tree().process_frame
	e.health = 100
	e._last_hit_dir = Vector2.LEFT
	e.hit(5)
	assert_float(sprite.rotation - e._sprite_base_rotation).is_less(0.0)


func test_zero_direction_hit_does_not_lean() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	add_child(e)
	await get_tree().process_frame
	e.health = 100
	e.hit(5)
	assert_float(sprite.rotation).is_equal_approx(e._sprite_base_rotation, 0.0001)
	assert_that(sprite.position).is_equal(e._sprite_base_position)
	assert_that(sprite.scale).is_equal(Enemy.SQUASH_STRETCH)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
Expected: FAIL — `_last_hit_dir` / `_sprite_base_rotation` do not exist yet (parse or invalid-identifier error).

- [ ] **Step 3: Add member variables**

In `src/enemies/enemy.gd`, find the tween member block (the lines declaring `_flash_tween`, `_squash_tween`, `_death_tween`):

```gdscript
var _flash_tween: Tween = null
var _squash_tween: Tween = null
var _death_tween: Tween = null
```

Add directly after it:

```gdscript
var _recoil_tween: Tween = null
var _last_hit_dir: Vector2 = Vector2.ZERO
var _sprite_base_position: Vector2 = Vector2.ZERO
var _sprite_base_rotation: float = 0.0
```

- [ ] **Step 4: Add the recoil constants**

In `src/enemies/enemy.gd`, directly below the `SETTLE_DURATION` constant added in Task 1, add:

```gdscript
const RECOIL_ANGLE: float = 0.4
const RECOIL_OFFSET: float = 5.0
```

- [ ] **Step 5: Capture the sprite base transform in `_ready`**

In `src/enemies/enemy.gd`, find this line in `_ready`:

```gdscript
	_animator = get_node_or_null("EnemyAnimator")
```

Add directly after it:

```gdscript
	var base_sprite := get_node_or_null("Sprite2D")
	if base_sprite:
		_sprite_base_position = base_sprite.position
		_sprite_base_rotation = base_sprite.rotation
```

- [ ] **Step 6: Add `_play_recoil`**

In `src/enemies/enemy.gd`, add this function directly after `_play_squash`:

```gdscript
func _play_recoil(hit_dir: Vector2) -> void:
	if hit_dir.length_squared() <= 0.0001:
		return
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	var lean_sign := 1.0 if hit_dir.x >= 0.0 else -1.0
	sprite.rotation = _sprite_base_rotation + lean_sign * RECOIL_ANGLE
	sprite.position = _sprite_base_position + hit_dir.normalized() * RECOIL_OFFSET
	_recoil_tween = create_tween()
	_recoil_tween.set_parallel(true)
	_recoil_tween.set_trans(Tween.TRANS_ELASTIC)
	_recoil_tween.set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(sprite, "rotation", _sprite_base_rotation, SETTLE_DURATION)
	_recoil_tween.tween_property(sprite, "position", _sprite_base_position, SETTLE_DURATION)
```

- [ ] **Step 7: Call `_play_recoil` from `_on_hit` and reset the direction**

In `src/enemies/enemy.gd`, replace `_on_hit`:

```gdscript
func _on_hit() -> void:
	_play_hit_flash()
	_play_squash()
	_play_recoil(_last_hit_dir)
	if _hurt_vfx:
		_hurt_vfx.burst()
	_last_hit_dir = Vector2.ZERO
```

- [ ] **Step 8: Stash the hit direction in `on_hit_impact`**

In `src/enemies/enemy.gd`, find the final line of `on_hit_impact`:

```gdscript
	hit(damage)
```

Replace it with:

```gdscript
	_last_hit_dir = hit_dir
	hit(damage)
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
Expected: PASS (whole suite, including the three new tests and Task 1's test).

- [ ] **Step 10: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "feat: add directional recoil snap and spring settle to enemy hurt"
```

---

### Task 3: Death coordination (kill hurt tweens + reset transform)

On `DEATH` entry, stop the squash/recoil tweens and reset the sprite transform so `_process_death` starts clean and owns `scale`/`rotation` exclusively. Also fixes the pre-existing squash-vs-death conflict.

**Files:**
- Modify: `src/enemies/enemy.gd` (`_change_state` `State.DEATH` arm near line 680-684; add `_reset_hurt_transform` helper)
- Test: `tests/unit/test_enemy_visual_identity.gd` (append)

**Interfaces:**
- Consumes: `_squash_tween`, `_recoil_tween`, `_sprite_base_position`, `_sprite_base_rotation` (Tasks 1-2).
- Produces: `_reset_hurt_transform() -> void` — kills both hurt tweens (if valid) and sets `Sprite2D.scale = Vector2.ONE`, `rotation = _sprite_base_rotation`, `position = _sprite_base_position`. Called from the `State.DEATH` arm of `_change_state`.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_enemy_visual_identity.gd`:

```gdscript
func test_death_resets_hurt_transform_and_kills_tweens() -> void:
	var e: MockAnimatorEnemy = auto_free(MockAnimatorEnemy.new())
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	e.add_child(sprite)
	add_child(e)
	await get_tree().process_frame
	e.health = 100
	e._last_hit_dir = Vector2.RIGHT
	e.hit(5)
	e._change_state(Enemy.State.DEATH)
	assert_that(sprite.scale).is_equal(Vector2.ONE)
	assert_float(sprite.rotation).is_equal_approx(e._sprite_base_rotation, 0.0001)
	assert_that(sprite.position).is_equal(e._sprite_base_position)
	assert_bool(e._squash_tween.is_valid()).is_false()
	assert_bool(e._recoil_tween.is_valid()).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
Expected: FAIL — after `_change_state(DEATH)` the squash/recoil tweens are still valid and the sprite is still stretched/leaning.

- [ ] **Step 3: Add the `_reset_hurt_transform` helper**

In `src/enemies/enemy.gd`, add this function directly after `_play_recoil`:

```gdscript
func _reset_hurt_transform() -> void:
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.scale = Vector2.ONE
	sprite.rotation = _sprite_base_rotation
	sprite.position = _sprite_base_position
```

- [ ] **Step 4: Call it on DEATH entry**

In `src/enemies/enemy.gd`, find the `State.DEATH` arm of `_change_state`:

```gdscript
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
			if _death_vfx:
				_death_vfx.burst(_base_modulate)
```

Replace it with:

```gdscript
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
			_reset_hurt_transform()
			if _death_vfx:
				_death_vfx.burst(_base_modulate)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
Expected: PASS (whole suite).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/enemy.gd tests/unit/test_enemy_visual_identity.gd
git commit -m "fix: reset enemy sprite transform and kill hurt tweens on death"
```

---

## Verification

- [ ] Full suite green: `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh -a tests/unit/test_enemy_visual_identity.gd`
- [ ] Manual smoke (optional, in-editor): spawn a dummy enemy, hit it from different directions — the sprite should visibly stretch big and jelly back, and lean/jolt toward the strike; a killing blow should not glitch the death shrink/spin.
