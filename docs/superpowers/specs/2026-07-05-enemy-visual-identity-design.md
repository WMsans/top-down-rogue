# Enemy Visual Identity + Action Juice — Design

Implements the "Enemy Visual Identity" section of `docs/design_docs/implementation_todo2.md` (Phase 2), plus additional tween/particle feedback for enemy actions requested alongside it.

## Goals

- Replace placeholder textures (`melee_test.png`, `ranged_test.png`) on the enemy archetypes that actually spawn today with the existing caves sprite art.
- Give idle/moving enemies a lightweight two-frame "breathing" animation instead of a static sprite.
- Add particle- and tween-driven juice to existing combat feedback moments (hurt, walking, attack windup, attacking, dash windup, dashing, death).
- Add an elite visual overlay so elite enemies read as distinct at a glance.
- Do all of this using the existing per-enemy state machine (`enemy.gd`: `WANDER, CHASE, WINDUP, ATTACK, COOLDOWN, HURT, DEATH`) as the hook surface — no new states.

## Non-goals

- No per-biome sprite palettes. All biomes reuse the caves sprite set as a placeholder; biome-specific art is a future pass.
- No behavior/stat changes for enemy variants (skirmisher, armored, cultist, etc.). Those remain unimplemented; this pass only makes their sprite art pluggable for when that behavior work lands.
- No boss sprite changes (`boss_enemy.gd` keeps its current placeholder texture — boss art is separate Phase 3 work).
- No directional (left/right) sprite flipping. The caves sprites are not authored as walk-cycle direction frames, just a normal/breathe-out pair.

## 1. Sprite-to-archetype mapping

Sprite variant assignment is **fixed per archetype/weapon**, not random, matching what actually spawns today per `spawn_dispatcher.gd`:

| Script | Condition | Sprite set |
|---|---|---|
| `melee_enemy.gd` | (default) | `grunt` |
| `lunge_enemy.gd` | (default) | `brute` |
| `ranged_enemy.gd` | `weapon_resource` is `AimedBurstWeapon` | `archer` |
| `ranged_enemy.gd` | `weapon_resource` is `SplitShotWeapon` or `FanWeapon` | `lobber` |
| `sniper_enemy.gd` | (default) | `mage` |
| `boss_enemy.gd` | — | unchanged (out of scope) |

The remaining caves sprite sets (`skirmisher`, `armored`, `cultist`) are not assigned to any scene in this pass — they're wired into the shared animation component so a future behavior script can point at them without new plumbing.

## 2. Idle/walk animation system

New component `EnemyAnimator` (`src/enemies/feedback/enemy_animator.gd`), a small node sibling to `Sprite2D` holding `texture_normal` and `texture_breathe` (the two frames per sprite set) and driving the enemy's existing `Sprite2D` node.

Behavior, read each `_physics_process` from the owning enemy's state and velocity:

- **Idle** (`WANDER` and not moving): swap between `texture_normal`/`texture_breathe` on a fixed ~0.6s timer.
- **Moving** (`CHASE`, or `WANDER` while drifting): swap rate scales with `velocity.length() / speed` — faster movement flickers faster.
- **Lunge dash-prep** (`LungeEnemy` in `WINDUP`): hold `texture_breathe` only, no flicker — reads as "coiled."
- **Lunge dashing** (`LungeEnemy` in `ATTACK`): hold `texture_normal` only, no flicker — reads as "extended."
- **Non-lunge WINDUP/ATTACK** (melee/ranged/sniper): continue the "moving" flicker rate — these archetypes don't have a distinct coil/extend visual, so windup/attack keeps whatever rate their current velocity implies.

`EnemyAnimator` exposes `set_textures(normal: Texture2D, breathe: Texture2D)` so archetype scenes just assign the two textures.

## 3. Action VFX

All new particle effects use `GPUParticles2D` with a `ParticleProcessMaterial`, following the existing procedural-node pattern in `src/enemies/feedback/dash_fire_vfx.gd` (a `start(direction)` / `stop()` API on a small `Node2D` subclass) — but ported to GPU particles rather than CPU. `dash_fire_vfx.gd` itself is converted from `CPUParticles2D` to `GPUParticles2D` in this pass, keeping its existing public API and color-ramp behavior unchanged.

- **Hurt**: keep the existing hit-flash + squash tween (`_play_hit_flash`, `_play_squash` in `enemy.gd`). Add a brief impact-spark `GPUParticles2D` burst at the hit point, hooked into `_on_hit()`.
- **Walking**: light footstep dust puff while `CHASE`-moving, emitted every other "step" (paced off the animator's flicker timer). Skipped for lunge (dash trail already communicates motion) and ranged/sniper (they strafe/reposition more than walk).
- **Preparing attack** (`WINDUP`, non-lunge): a subtle glow pulse plus a small rising particle wisp, layered with the existing `_show_exclaim()` telegraph.
- **Attacking** (`ATTACK`, non-lunge): a brief arc/slash particle burst at `_execute_attack()` time, direction-aligned to `get_facing_direction()`.
- **Preparing dash** (`LungeEnemy` `WINDUP`): a new `dash_windup_vfx.gd` component — inward-tightening particle swirl + crouch glow, telegraphing the coil before the lunge.
- **Dashing** (`LungeEnemy` `ATTACK`): existing `DashFireVfx` trail, ported to `GPUParticles2D` per above; behavior otherwise unchanged.

## 4. Elite visual overlay

Elites (`is_elite = true`, currently 20% of melee spawns) get, layered on top of the existing `_apply_elite_scaling()` stat bump:

- The existing `shaders/visual/outline.gdshader` (already supports `outline_width`/`outline_color` uniforms) applied as the `Sprite2D`'s material, with `outline_color` set per `EliteAbility` below.
- The existing scale increase from `_apply_elite_scaling()` (no separate change needed).
- A distinct tint blended into `_base_modulate` per `EliteAbility`: FAST = cyan, TANK = steel-grey, TELEPORT = purple, ENRAGE = red. `EliteAbility.NONE` elites (if any) get a neutral gold tint. The outline color matches this same per-ability tint.

## 5. Enhanced death animation

Extends `_process_death()` in `enemy.gd` (currently a linear scale-to-zero over `death_duration`):

- Directional knockback rotation: while scaling down, the sprite also rotates toward the direction of `_knockback_velocity` at the moment of death (falls back to `get_facing_direction()` if knockback is negligible).
- Dissolve-to-particles: a `GPUParticles2D` burst tinted with the enemy's `_base_modulate` fires at death, timed to accompany the shrink rather than replace it.

## Implementation components (new/changed files)

- New: `src/enemies/feedback/enemy_animator.gd` — idle/walk/dash-hold frame driver.
- New: `src/enemies/feedback/attack_slash_vfx.gd` — melee/ranged attack burst.
- New: `src/enemies/feedback/dash_windup_vfx.gd` — lunge dash-prep swirl.
- New: `src/enemies/feedback/hurt_spark_vfx.gd` — hit-point impact spark.
- New: `src/enemies/feedback/death_dissolve_vfx.gd` — death particle burst.
- Reused: `shaders/visual/outline.gdshader` for the elite glow (no new shader needed).
- Changed: `src/enemies/feedback/dash_fire_vfx.gd` — `CPUParticles2D` → `GPUParticles2D`.
- Changed: `src/enemies/enemy.gd` — minimal new hook calls in `_on_hit()`, `_change_state()`, `_execute_attack()`, `_process_death()`; elite tint/shader application alongside `_apply_elite_scaling()`.
- Changed: `src/enemies/lunge_enemy.gd` — wire dash-prep/dash VFX components.
- Changed scenes: `melee_enemy.tscn`, `lunge_enemy.tscn`, `ranged_enemy.tscn`, `sniper_enemy.tscn` — real caves textures assigned, `EnemyAnimator` node added.

## Testing

- Existing `tests/unit/test_enemy_state_machine.gd` should continue to pass unchanged (no state machine changes, only new hooks off existing transitions).
- Manual verification in-editor: spawn each of the 5 mapped archetypes and an elite melee enemy, observe idle breathing, walk flicker rate scaling with speed, windup/attack/dash VFX, hurt spark, and death dissolve.
