# Enemy AI Improvements Design

## Summary

Fix the `speed = 0` bug that prevents spawned enemies from moving, add a wander behavior so enemies don't stand frozen when idle, add an exclamation-mark telegraph during attack windup, and fix the RangedEnemy's direct `global_position` manipulation to use proper velocity-based movement.

## Scope

Three files changed. No new files, no architectural refactors.

| File | Changes |
|------|---------|
| `src/enemies/enemy.gd` | Wander behavior (rename IDLE→WANDER), `!` popup telegraph, default speed |
| `src/enemies/melee_enemy.gd` | Add `speed` init in `if weapon_resource:` branch |
| `src/enemies/ranged_enemy.gd` | Add `speed` init in `if weapon_resource:` branch; fix keep-away to use `velocity` |

---

## 1. Speed Bug Fix

**Root cause**: When `weapon_resource` is set (the normal spawn path from `spawn_dispatcher.gd` and `cave_spawner.gd`), both `MeleeEnemy._ready()` and `RangedEnemy._ready()` enter the `if weapon_resource:` branch, which sets `weapon`, `_attack_range`, and `cooldown_duration` — but never `speed`. Speed stays at the default `0.0`. Later, `spawn_dispatcher` does `enemy.speed = enemy.speed * speed_mult`, which is `0.0 * speed_mult = 0.0`.

**Fix**:
- `MeleeEnemy._ready()` — in the `if weapon_resource:` branch, add `speed = 60.0` before `super._ready()`
- `RangedEnemy._ready()` — in the `if weapon_resource:` branch, add `speed = 50.0` before `super._ready()`
- Base `Enemy` — change default `@export var speed: float = 0.0` to `50.0` as a safety net

---

## 2. Wander Behavior

**Current**: IDLE state does nothing. Enemy stands frozen until player enters detection radius.

**New**: WANDER state (renamed from IDLE). Enemy moves in random directions with intermittent pauses.

### State Machine

```
WANDER ──(player detected + LOS)──> CHASE
CHASE ──(player lost or no LOS)──> WANDER
CHASE ──(within attack range + settled)──> WINDUP
WINDUP ──(timer done)──> ATTACK
WINDUP ──(loses LOS)──> WANDER
ATTACK ──(immediate)──> COOLDOWN
COOLDOWN ──(timer done, player visible)──> CHASE
COOLDOWN ──(timer done, no player)──> WANDER
Any ──(hit)──> HURT
HURT ──(timer done)──> previous state
Any ──(HP <= 0)──> DEATH
```

The only transition change from current: WINDUP abort and COOLDOWN expiry now go to WANDER instead of IDLE (semantic rename).

### Wander Logic (in `_process_idle` → stays named `_process_idle` but handles WANDER state)

New private members in base `Enemy`:
- `_wander_direction: Vector2` — current wander direction
- `_wander_timer: float` — time remaining in current wander phase
- `_wander_is_paused: bool` — whether currently in pause phase

Behavior cycle:
1. Pick random `_wander_direction`, set `_wander_timer = randf_range(1.0, 3.0)`, `_wander_is_paused = false`
2. Move at `speed * 0.5` in `_wander_direction` (via `velocity`, handled by `_physics_process`)
3. When `_wander_timer` expires, enter pause: `_wander_is_paused = true`, `_wander_timer = randf_range(0.5, 1.5)`, `velocity = Vector2.ZERO`
4. When pause timer expires, goto 1
5. If player detected + LOS at any point: abort wander, transition to CHASE

Movement uses `velocity` (same as chase), so `_physics_process` already handles `move_and_slide()` for both WANDER and CHASE states (see section below).

### Physics process update

Current `_physics_process` only calls `move_and_slide()` for CHASE and HURT. Must also call it for WANDER:

```gdscript
if _state == State.WANDER or _state == State.CHASE or _state == State.HURT:
    move_and_slide()
```

---

## 3. Exclamation Mark Telegraph

A bold `"!"` Label pops above the enemy's head during WINDUP, similar to Metal Gear Solid alert.

### Setup (in `_ready()`)

Create a `Label` as child of `Enemy`:
- Position: `Vector2(0, -16)` relative to enemy
- Text: `"!"`
- Font size: Large enough to be visible (e.g., 20–24pt)
- Color: Red and/or white (e.g., `Color.RED`, bold)
- Initial scale: `Vector2.ZERO` (invisible)
- Horizontal alignment: CENTER

### Trigger

In `_change_state(State.WINDUP)`:
- Kill any existing exclamation tween
- Create tween: scale `Vector2.ZERO` → `Vector2(1.2, 1.2)` (0.05s) → `Vector2.ONE` (0.05s) with elastic/back ease

On WINDUP complete (→ ATTACK) or abort (→ WANDER):
- Tween scale to `Vector2.ZERO` over ~0.05s, then optionally hide

The label should face toward the player — update its `global_rotation` per frame in `_process()` using `get_facing_direction()` during WINDUP.

---

## 4. RangedEnemy Keep-Away Fix

**Current bug**: `RangedEnemy._process_chase()` moves by directly modifying `global_position` (lines 57, 59, 66), bypassing `CharacterBody2D` physics. Meanwhile `_physics_process` still calls `move_and_slide()` in CHASE state, causing potential conflicts. Additionally, `velocity` is never set, so separation steering via `_apply_separation()` has no effect on movement.

**Fix**: Replace direct `global_position` manipulation with velocity-based movement:
- Set `velocity = move_dir * speed` instead of `global_position += ...`
- Strafing: set `velocity = perpendicular * _strafe_direction * strafe_speed`
- Remove the post-move `_apply_separation()` call — separation is already applied via `velocity` + `move_and_slide()`
- Apply separation to the move_dir before computing velocity (same as base class)

---

## 5. Enemy Subclass Defaults

Recommended export defaults for balanced gameplay:

| Parameter | MeleeEnemy | RangedEnemy | BossEnemy |
|-----------|-----------|------------|-----------|
| `speed` | 60 | 50 | 40 |
| `detection_radius` | 150 | 250 | 400 |
| `windup_duration` | 0.35 | 0.4 | 0.5 |
| `cooldown_duration` | 0.5 | 0.6 (weapon override) | 0.5 (weapon override) |
| `_attack_range` | weapon reach (~28) | 180 | 200 |

Wander speed is always `speed * 0.5`.

---

## 6. Edge Cases

- **Player null/invalid during wander**: Continue wandering (no crash, no state change)
- **Wander into wall**: `move_and_slide()` handles collision naturally — enemy slides along wall, picks new direction on next cycle
- **Multiple enemies in wander**: Separation steering prevents stacking (already works)
- **Elite enemies**: Wander and telegraph work the same; elite stat modifications apply on top
- **Boss Enemy**: Wander still applies (boss patrols arena when player is out of range). Boss already sets `speed` correctly, unaffected by the speed bug
- **Exclamation label cleanup**: Label is freed with the enemy on `queue_free()`, no manual cleanup needed
