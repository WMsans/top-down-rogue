# Phase 4: Enemies & Combat Design

**Date:** 2026-05-04
**Status:** Approved

## Overview

Complete the remaining Phase 4 enemy and combat tasks: basic melee enemies, ranged enemies, elite enemies, and bosses. All enemies carry visible weapons that drop on death. Enemy attacks are telegraphed (Soul Knight / Enter the Gungeon style) with clear wind-up animations. Weapon pool expands to support enemy variety.

Ref: `docs/design_docs/implementation_todo.md` Phase 4 (lines 72-88).

## Remaining Tasks

| Task | Priority | Difficulty | Status |
|------|----------|------------|--------|
| Enemy base class (state machine) | P1 | Medium | **This design** |
| Basic melee enemies | P1 | Medium | **This design** |
| Enemy spawning (integrate new types) | P1 | Medium | **This design** |
| Ranged enemies | P2 | Medium | **This design** |
| Elite enemies | P2 | High | **This design** |
| Boss generation / defeat / abilities | P2 | High | **This design** |

## Design Decisions

| Decision | Choice |
|----------|--------|
| AI pattern | Finite state machine: IDLE → CHASE → WINDUP → ATTACK → COOLDOWN, with HURT/DEATH interrupts |
| Attack telegraphing | Wind-up phase with sprite flash + scale pulse before damage |
| Enemy-weapon tie | Enemy carries a `.duplicate()`-ed Weapon resource; that weapon drops on death |
| Ranged enemies | New RangedWeapon class + Projectile scene |
| Elite system | Data-driven flag on base class (`is_elite: bool`), stat multipliers + one ability. No wrapper. |
| Boss enemies | Multi-phase (3 phases) health-gated with chained transitions, escalating attack patterns |
| Spawning coherence | Expand CaveSpawner and SpawnDispatcher to spawn new enemy types |
| Enemy separation | CHASE state applies separation steering (min 16px gap) |
| Mob cap | 25 (configurable), with perf budget note for future profiling |
| Theme | Placeholder — colored rects, behaviors first, polish deferred to Phase 6 |

---

## 1. Enemy State Machine

All enemies share a finite state machine built into the `Enemy` base class.

### States

| State | Behavior | Enter condition | Exit condition |
|-------|----------|-----------------|----------------|
| IDLE | Stand still, face last direction | Spawn, or player leaves detection | Player enters `detection_radius` → CHASE |
| CHASE | Navigate toward player (separation steering, 16px min gap). Ranged enemies maintain `preferred_distance`. | Player detected in radius | Within `_attack_range` AND `_settle_timer >= min_attack_settle_time` → WINDUP; player leaves detection → IDLE |
| WINDUP | Stop moving. Play telegraph: sprite flash red 0.1s intervals, weapon scale pulse (1.0→1.2→1.0). Cannot be re-staggered. | Chase target in range | Timer (`windup_duration`) expires → ATTACK; death → DEATH |
| ATTACK | Execute attack via virtual `_execute_attack()`. Brief state (one frame to fire/use weapon). | Windup complete | Attack call returns → COOLDOWN; death → DEATH |
| COOLDOWN | Wait, slight deceleration to zero. | Attack finished | Timer (`cooldown_duration`) expires → CHASE (or IDLE if player far) |
| HURT | Knockback at 180 px/s in hit direction, sprite flash white, weapon hidden. Re-staggerable (timer resets on new hit). Duration: 0.2s. | `hit()` called while alive | Timer expires → resume previous non-HURT state (usually CHASE) |
| DEATH | Sprite scales to 0 over `death_duration` (0.3s). Weapon and gold drops spawned at halfway point. | `health <= 0` from any state | `death_duration` expires → `queue_free()` |

### State Transit Diagram

```
                    ┌────────────────────────────────────────────┐
                    │                                            ▼
 ┌──IDLE──┐     ┌──CHASE──┐     ┌─WINDUP─┐     ┌─ATTACK─┐    ┌─COOLDOWN─┐
 │ stand  │────▶│ move to │────▶│telegraph│────▶│ fire/  │───▶│  pause   │──┐
 │ still  │     │ player  │     │ 0.35s  │     │ swing  │    │weapon.cd │  │
 └──IDLE──┘     └──CHASE──┘     └─WINDUP─┘     └─ATTACK─┘    └─COOLDOWN─┘  │
      ▲              ▲               ▲               ▲              │        │
      │              │               │               │              │        │
      │              ├───────────────┴───────┬───────┴──────────────┘        │
      │              │                       │                                │
      │              │     HURT (any state except DEATH)                      │
      │              │  ┌─ knockback 0.2s ─▶ resume ─────────────────────────┘
      │              │  │
      │              └──┼─────────────────────────────────────────────────────┘
      │                 │
      │           DEATH (any state)
      │     flash-out 0.3s → queue_free + drop loot
      └─────────────────────────────────┘
```

### Enemy Base Class Extensions (`src/enemies/enemy.gd`)

New exports and fields added to existing `Enemy`:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `detection_radius` | float | 150.0 | Circle radius for player detection |
| `windup_duration` | float | 0.35 | Telegraph duration (seconds) |
| `death_duration` | float | 0.3 | Scale-to-zero animation duration |
| `hurt_duration` | float | 0.2 | Knockback + flash duration |
| `is_elite` | bool | false | Set at spawn; enables elite stat scaling + ability |
| `elite_ability` | int | `EliteAbility.NONE` | Only active when `is_elite` |
| `separation_radius` | float | 16.0 | Min px between enemies in CHASE |
| `min_attack_settle_time` | float | 0.5 | Seconds player must stay in `_attack_range` before WINDUP transitions (prevents kiting oscillation) |
| `_state` | int | IDLE | Current FSM state |
| `_state_timer` | float | 0.0 | Countdown within current state |
| `_settle_timer` | float | 0.0 | Increments while player in range, resets on exit. Gates CHASE→WINDUP. |
| `_prev_state` | int | IDLE | State to resume after HURT |
| `_player_ref` | Node2D | — | Cached player reference |
| `_attack_range` | float | 32.0 | **Protected**. Subclasses set this from weapon in `_ready()`. State machine reads this directly; no virtual needed. |
| `_detection_shape` | CollisionShape2D | — | Resized to `detection_radius` in `_ready()` |

### Separation Steering (CHASE state)

Every frame in CHASE, for each other `Enemy` within `separation_radius`, add a repulsion vector away from that enemy (magnitude proportional to overlap). The final movement direction is `(toward_player + sum_separation_vectors).normalized()`.

### Virtual Methods (New)

```gdscript
func _execute_attack() -> void     # Subclass-defined attack logic
func _can_see_player() -> bool      # Line-of-sight check (optional override)
```

### Enemy Scene Update (`scenes/enemy.tscn`)

Add `Area2D` child named `DetectionArea` with `CollisionShape2D` (CircleShape2D). Radius set to `detection_radius` in `_ready()`. `body_entered`/`body_exited` signals filter with `body.is_in_group("player")` — other enemies entering the area are ignored. Maintains `_player_in_range: bool` flag for state machine.

---

## 2. Enemy Types & Weapon Tying

Each enemy subclass instantiates a `Weapon` resource via `.duplicate()` at spawn time. The weapon determines combat behavior AND drops on death. **Resources are duplicated so floor scaling does not mutate shared `.tres` files.**

### MeleeEnemy (`src/enemies/melee_enemy.gd`)

```gdscript
class_name MeleeEnemy extends Enemy
```

| Export | Type | Default | Notes |
|--------|------|---------|-------|
| `weapon` | MeleeWeapon | (required) | Duplicated on spawn. Determines damage, arc, cooldown. |
| `windup_duration` | float | 0.35 | Overrides base default |
| `cooldown_duration` | float | weapon.cooldown | Recovered from weapon (post-duplicate) |

**`_ready()`**: `weapon = weapon.duplicate()`. Set `_attack_range = weapon.reach`.  
**WINDUP**: Stops, sprite flashes red, weapon visual pulses (scale 1.0→1.2→1.0).  
**ATTACK**: Calls `weapon.use(self)`, triggering the same arc-hitbox system the player uses.  
**DEATH**: `_on_death()` adds `weapon` resource to a `WeaponDrop` scene. Gold per `drop_table`.

### RangedEnemy (`src/enemies/ranged_enemy.gd`)

```gdscript
class_name RangedEnemy extends Enemy
```

| Export | Type | Default | Notes |
|--------|------|---------|-------|
| `weapon` | RangedWeapon | (required) | Duplicated on spawn |
| `detection_radius` | float | 250.0 | Longer awareness |
| `preferred_distance` | float | 120.0 | Tries to maintain this gap from player |
| `windup_duration` | float | 0.4 | |
| `strafe_speed` | float | 40.0 | Lateral speed when too close |
| `back_away_acceleration` | float | 200.0 | Acceleration away from player when closer than `preferred_distance - 20px` |
| `min_attack_settle_time` | float | 0.5 | Overrides base default. Longer settle prevents oscillation when player rushes. |

**`_ready()`**: `weapon = weapon.duplicate()`. Set `_attack_range = preferred_distance * 1.5`.  
**CHASE**: Compute `dist = distance_to(player)`. If `dist < preferred_distance - 20px`: accelerate away from player. If `dist > preferred_distance + 20px`: move toward player. Strafing is done via sideways movement: pick a random lateral direction (±1), move perpendicular to the player vector at `strafe_speed`. Re-roll lateral direction every 1.5s. The `_settle_timer` gates the transition to WINDUP — the player must remain continuously within `_attack_range` for `min_attack_settle_time` seconds. If the player rushes, the enemy keeps retreating and the settle timer resets, preventing rapid WINDUP→CHASE→WINDUP oscillation.  
**WINDUP**: Aims at player (sprite + weapon visual rotate to face target).  
**ATTACK**: Calls `weapon.use(self)`, spawning projectiles toward the player.  
**DEATH**: Drops `weapon` resource + gold.

### Elite System (data-driven, no wrapper)

Elite is **not** a subclass. It is a flag on the base `Enemy`:

```gdscript
# In enemy.gd
enum EliteAbility { NONE, FAST, TANK, TELEPORT, ENRAGE }

@export var is_elite: bool = false
@export var elite_ability: int = EliteAbility.NONE
```

At spawn time, `SpawnDispatcher` or `CaveSpawner` sets `is_elite = true` and picks a random `elite_ability`. The `Enemy._ready()` method applies elite scaling when `is_elite`:

**Stat modifiers (elite base)**:
| Stat | Multiplier | Notes |
|------|-----------|-------|
| `max_health` | 3.0x | Applied after floor scaling |
| `weapon.damage` | 1.5x | On duplicated weapon resource |
| `speed` | 1.3x | |
| `scale` | 1.3x | Visual size |

**Visual**: Glowing outline shader material, larger health bar.

**Elite Ability stacking order** (applied after elite base multipliers):

| Ability | Effect | Constraints |
|---------|--------|-------------|
| FAST | `windup_duration` and `cooldown_duration` halved | **Floor**: `max(0.2, windup / 2)`. Minimum 0.2s telegraph even when halved. |
| TANK | `max_health *= 2.0` (total 6x base). `speed` set to `0.7 * speed_base` (overrides elite 1.3x, applied to original base speed) | Net speed: 0.7x of a non-elite. Intent: slower than normal enemies. |
| TELEPORT | On hit (`HURT` enter): blink 64px in random direction after knockback completes | 0.5s cooldown between teleports. Random angle, clamped to not teleport into solid terrain. |
| ENRAGE | When `health < max_health * 0.3`: `weapon.damage *= 2.0`, `speed *= 1.5` | Active while below 30% HP. Reverts if healed (not applicable currently but correct). |

**DEATH**: Drops the enemy's weapon (with elite-scaled stats preserved) + one extra modifier from drop table.

### BossEnemy (`src/enemies/boss_enemy.gd`)

```gdscript
class_name BossEnemy extends Enemy
```

| Export | Type | Default | Notes |
|--------|------|---------|-------|
| `boss_name` | String | "Boss" | Display in HUD |
| `phase_count` | int | 3 | Health-gated phases |
| `current_phase` | int | 1 | |
| `weapon` | RangedWeapon | (required) | Duplicated on spawn via `weapon.duplicate()` in `_ready()` |
| `hazard_interval` | float | 5.0 | Seconds between arena hazard spawns (phase 3 only) |
| `hazard_count` | int | 3 | Hazards per spawn cycle |
| `hazard_duration` | float | 10.0 | How long each hazard persists |
| `hazard_damage` | float | 5.0 | Damage per second to player standing in hazard |

**`_ready()`**: `weapon = weapon.duplicate()`. Stores a separate `_original_weapon` reference (also `.duplicate()`) for drop purposes — see weapon mutation note below.  
**Phase thresholds**: Divide max_health into `phase_count` segments. Phase `k` is active while `health > max_health * (phase_count - k) / phase_count`.

**Phase transition chaining** (prevents skipped phases on burst damage):
```gdscript
func _check_phase_transition():
    while current_phase < phase_count and health <= _phase_threshold(current_phase + 1):
        current_phase += 1
        _transition_phase()
```
Where `_phase_threshold(p)` = `max_health * (phase_count - p + 1) / phase_count`. This ensures crossing two thresholds in one hit advances phases sequentially (calling `_transition_phase()` twice).

**`_transition_phase()`** (virtual, per-boss customization):

Default implementation:
| Phase | Attack Pattern |
|-------|---------------|
| 1 | Single projectile toward player (basic `weapon.use()`) |
| 2 | Adds `spread`: `_execute_attack()` now fires 3-projectile fan (weapon's `projectile_count` set to 3, `spread_angle` = 30°) |
| 3 | Adds `arena_hazard`: every `hazard_interval` seconds, spawns `hazard_count` lava pools at random positions within the boss arena. Each pool uses `TerrainSurface.place_lava(pos, 4.0)`. Pool radius: 4 cells. Persists for `hazard_duration`. |

**Weapon mutation and drop behavior** (intentional):
`_transition_phase()` mutates `weapon.projectile_count` and `spread_angle` on the duplicated weapon instance. Because `_ready()` stores a separate `_original_weapon` (pre-mutation duplicate of `boss_staff.tres`), the boss *drops the evolved weapon* — the one the player saw in phases 2–3 (3 projectiles, 30° spread). This is a feature: the boss wields its strongest form, and defeating it rewards that form. The `_original_weapon` (1 projectile, 10° spread) is kept only as a reference for post-death comparison; it is not used for drops.

**Boss arena**: Already spawned by `SpawnDispatcher` at room marker `6`. Boss `died` signal → spawn portal at arena center (portal scene exists at `scenes/portal.tscn`).

**DEATH**: Drops the evolved `weapon` resource (post-mutation) + gold + guaranteed random modifier from RARE tier.

---

## 3. Weapon Expansion

### New Classes

#### RangedWeapon (`src/weapons/ranged_weapon.gd`)

```gdscript
class_name RangedWeapon extends Weapon
```

| Export | Type | Default | Notes |
|--------|------|---------|-------|
| `projectile_scene` | PackedScene | (required) | `scenes/projectile.tscn` |
| `projectile_speed` | float | 200.0 | |
| `projectile_lifetime` | float | 3.0 | Seconds before auto-destroy |
| `spread_angle` | float | 0.0 | Degrees of random deviation |
| `projectile_count` | int | 1 | Per volley |

`_use_impl(user)`: Spawns `projectile_count` projectiles, each evenly distributed within `spread_angle` arc, launched at `projectile_speed` toward the direction `user` is facing (or toward player for enemies). If `user` has no `_last_facing`, falls back to `Vector2.DOWN`.

#### Projectile (`src/weapons/projectile.gd`)

```gdscript
class_name Projectile extends Area2D
```

| Export | Type | Default | Notes |
|--------|------|---------|-------|
| `damage` | float | 0.0 | |
| `speed` | float | 200.0 | |
| `lifetime` | float | 3.0 | |
| `is_enemy_projectile` | bool | false | |
| `direction` | Vector2 | Vector2.RIGHT | Normalized travel direction |
| `source_node` | Node2D | null | The node that fired this projectile. Used to prevent self-hit. |

**Collision layers**: Projectile uses its own collision layer (layer 4 "projectiles"). Player body is on layer 1. Enemies are on layer 1. Projectile mask: layer 1 only (hits bodies on default layer).

**`_on_body_entered(body)`**:
```gdscript
if is_enemy_projectile and body.is_in_group("player"):
    body.on_hit_impact(global_position, direction, damage)
    queue_free()
elif not is_enemy_projectile and body.is_in_group("attackable"):
    if body != source_node:
        body.on_hit_impact(global_position, direction, damage)
        queue_free()
```
This prevents enemy projectiles from friendly-firing other enemies, and prevents projectiles from hitting their source (player or enemy).

**`_process(delta)`**: Move `direction * speed * delta`. If `lifetime` expires, `queue_free()`.  
**Visual**: `ColorRect` child (6x6 px). Red for enemy projectiles, yellow for player.

**Scene**: `scenes/projectile.tscn` — `Area2D` root, `CollisionShape2D` (6x6 rect), `ColorRect` (6x6).

### Weapon Resources

All are `.tres` resource files. Directory: `resources/weapons/` (new).

#### Melee Weapons

| File | Class | Damage | Cooldown | Reach | Arc | Tier |
|------|-------|--------|----------|-------|-----|------|
| `rusty_sword.tres` | MeleeWeapon | 3 | 0.50s | 28px | 90° | COMMON |
| `bone_dagger.tres` | MeleeWeapon | 2 | 0.25s | 20px | 60° | COMMON |
| `broad_axe.tres` | MeleeWeapon | 6 | 0.70s | 36px | 120° | UNCOMMON |
| `flame_blade.tres` | MeleeWeapon | 5 | 0.40s | 32px | 90° | RARE |

`flame_blade.tres` pre-populates `modifiers[0]` with a `LavaEmitterModifier` instance.

#### Ranged Weapons

All reference `scenes/projectile.tscn` as `projectile_scene`.

| File | Class | Damage | Cooldown | Speed | Spread | Count | Lifetime | Tier |
|------|-------|--------|----------|-------|--------|-------|----------|------|
| `throwing_knife.tres` | RangedWeapon | 3 | 0.60s | 300 | 0° | 1 | 2.0s | COMMON |
| `fire_orb.tres` | RangedWeapon | 4 | 0.90s | 150 | 0° | 1 | 1.5s | UNCOMMON |
| `spread_shot.tres` | RangedWeapon | 2 | 0.70s | 250 | 30° | 3 | 2.0s | UNCOMMON |
| `boss_staff.tres` | RangedWeapon | 6 | 0.50s | 200 | 10° | 1 | 3.0s | RARE |

### Enemy-to-Weapon Mapping

| Enemy Type | Weapon | Tier |
|------------|--------|------|
| DummyEnemy | rusty_sword | COMMON |
| MeleeEnemy | rusty_sword or bone_dagger (weighted random) | COMMON |
| RangedEnemy | throwing_knife or fire_orb (weighted random) | COMMON–UNCOMMON |
| MeleeEnemy (elite) | broad_axe or flame_blade (weighted random) | UNCOMMON–RARE |
| RangedEnemy (elite) | spread_shot | UNCOMMON |
| BossEnemy | boss_staff | RARE |

**Drop logic**: `_on_death()` in each enemy adds the duplicated weapon resource to drop resolution. When resolving, `DropTable.resolve()` already handles `WEAPON_POOL` entries. Add a new path: if the enemy's `weapon` is non-null, spawn a `WeaponDrop` scene with that exact resource. The enemy's weapon appears as a `weapon_drop.tscn` pickup, exactly as the player saw it.

### Weapon Scaling with Depth

Extend existing `SpawnDispatcher` floor scaling to apply to weapons:

| Floor | Melee Damage | Ranged Damage | HP |
|-------|-------------|--------------|-----|
| 1 | 1.0x | 1.0x | 1.0x |
| 2 | 1.2x | 1.15x | 1.25x |
| n | 1.0 + 0.2(n-1) | 1.0 + 0.15(n-1) | 1.0 + 0.25(n-1) |

Applied by multiplying the duplicated `enemy.weapon.damage` by the floor multiplier after duplication. The weapon resource dropped to the player retains these scaled values (no unscaling).

---

## 4. Spawning Integration

### CaveSpawner Updates (`src/core/cave_spawner.gd`)

| Change | Detail |
|--------|--------|
| `_enemy_scenes` → `Array[PackedScene]` | Replace single `enemy_scene` with array of melee/ranged scenes |
| Biome pool | Read `BiomeDef.enemy_pool` to determine which enemy scenes are available per biome |
| Elite chance | `BiomeDef.elite_chance` (default 0.15). Rolled per spawn. If successful, `is_elite = true` on the spawned enemy + random ability assigned. |
| Mob cap | 25 (configurable). Performance budget note: profiling needed if active projectiles + VFX cause frame drops. |
| Weapon assignment | After spawning, pick weapon from enemy's weapon pool, `.duplicate()`, assign to `enemy.weapon`, apply floor scaling |

### SpawnDispatcher Updates (`src/core/spawn_dispatcher.gd`)

| Marker | Old | New |
|--------|-----|-----|
| G=1 (enemy) | dummy_enemy.tscn | melee_enemy.tscn (80%) or ranged_enemy.tscn (20%) |
| G=2 (elite) | — | Same as G=1 but with `is_elite = true` + random ability |
| G=6 (boss) | (placeholder) | boss_enemy.tscn |

### BiomeDef Extension (`src/terrain/biome_def.gd`)

```gdscript
@export var enemy_pool: PoolDef           # Which enemy scenes spawn in this biome
@export var elite_chance: float = 0.15    # Probability a spawn becomes elite
@export var boss_scene: PackedScene       # Boss scene for this biome (optional)
```

### PoolDef Type (`src/weapons/pool_def.gd`)

```gdscript
class_name PoolDef extends Resource
```

A `Resource` holding an `Array[PoolEntry]`. Each `PoolEntry` has `scene: PackedScene` and `weight: float`. `PoolDef.pick_weighted() -> PackedScene` selects by weight. Used for enemy scene pools and weapon pools.

---

## 5. File Inventory

### New Files

```
src/enemies/
├── melee_enemy.gd             (MeleeEnemy extends Enemy)
├── ranged_enemy.gd            (RangedEnemy extends Enemy)
└── boss_enemy.gd              (BossEnemy extends Enemy)

src/weapons/
├── ranged_weapon.gd           (RangedWeapon extends Weapon)
├── projectile.gd              (Projectile extends Area2D)
└── pool_def.gd                (PoolDef extends Resource)

scenes/
├── melee_enemy.tscn           (instances enemy.tscn, script melee_enemy.gd)
├── ranged_enemy.tscn          (instances enemy.tscn, script ranged_enemy.gd)
├── boss_enemy.tscn            (instances enemy.tscn, script boss_enemy.gd)
└── projectile.tscn            (Area2D + projectile.gd)

resources/weapons/
├── rusty_sword.tres
├── bone_dagger.tres
├── broad_axe.tres
├── flame_blade.tres
├── throwing_knife.tres
├── fire_orb.tres
├── spread_shot.tres
└── boss_staff.tres
```

Note: No `elite_enemy.gd` or `elite_enemy.tscn` — elite is data-driven via `is_elite` flag on the base class.

### Modified Files

| File | Changes |
|------|---------|
| `src/enemies/enemy.gd` | Add state machine (7 states), elite flag + abilities, `duplicate()` weapon, separation steering, `_attack_range` (protected), detection Area2D resizing, DEATH animation, HURT re-stagger |
| `src/enemies/dummy_enemy.gd` | Override `_execute_attack()` (contact damage), assign default weapon, set `_attack_range` from weapon |
| `src/enemies/drop_table.gd` | Add `add_weapon_drop(weapon: Weapon)` so enemy's duplicated weapon is always included in resolve |
| `src/core/cave_spawner.gd` | Array enemy scenes, biome pool, elite flagging + ability, weapon duplication + scaling, mob cap 25 |
| `src/core/spawn_dispatcher.gd` | Wire new enemy scenes to markers, elite flagging for G=2, floor scaling on weapon damage |
| `src/autoload/weapon_registry.gd` | Register 8 new weapons in tier pools |
| `src/terrain/biome_def.gd` | Add enemy_pool, elite_chance, boss_scene |
| `scenes/enemy.tscn` | Add DetectionArea child (Area2D + CircleShape2D) |

---

## 6. Edge Cases

- **Enemy without weapon**: If weapon is null at spawn, enemy chases (IDLE→CHASE→IDLE loop) but never transitions to WINDUP. No weapon drop on death. Graceful degrade.
- **Weapon resource aliasing**: All spawners MUST call `.duplicate()` before assigning weapon to enemy. Enemies shown `.tres` as readonly source, never mutate in place.
- **Player leaves level mid-combat**: Despawn cycle cleans up. No lingering state.
- **Boss phase threshold overshoot**: Chained transition loop ensures all intermediate phases execute.
- **Ranged enemy kiting oscillation**: Settle timer prevents CHASE↔WINDUP jitter. Player must remain in `_attack_range` for `min_attack_settle_time` (0.5s) before WINDUP triggers. If player rushes, settle timer resets; enemy keeps retreating. Ranged enemies fight in place when cornered.
- **HURT re-stagger**: New hit while in HURT resets `_state_timer` to `hurt_duration` (0.2s). Knockback direction updates to latest hit direction.
- **Elite TANK + floor scaling**: TANK applies to base speed before elite multiplier. Net: `base_speed * 0.7` (not `base_speed * 1.3 * 0.7 = 0.91`).
- **Projectile hitting terrain**: Projectile `queue_free()` on any collision. Does not interact with terrain physics.
- **Enemy projectile friendly fire**: Prevented via `elif not is_enemy_projectile` guard. Enemy projectiles only hit the "player" group.
- **Boss without arena**: CaveSpawner never spawns boss scenes. Only SpawnDispatcher at marker 6, where arena exists.
- **Separation steering at mob cap**: With 25 enemies in tight quarters, separation forces may cause jitter. Steering vector is damped (0.5x weight) to avoid oscillation.
- **Detection radius shape resize**: `_ready()` sets `DetectionArea/CollisionShape2D.shape.radius = detection_radius`. No static mismatch.

## Testing

Unit tests (`tests/unit/`) using GdUnit4:

1. **State transitions**: Start IDLE, move player into detection → CHASE. Move into `_attack_range` → WINDUP. Expire timer → ATTACK → COOLDOWN → CHASE. Move player far → IDLE.
2. **HURT re-stagger**: Apply two hits within 0.1s. Verify `_state_timer` resets to `hurt_duration` on second hit.
3. **DEATH animation**: Kill enemy, verify scale interpolates to 0 over `death_duration`, weapon drop appears at halfway, `queue_free()` at end.
4. **Elite stat scaling**: Set `is_elite = true` on MeleeEnemy. Verify `max_health *= 3`, weapon `damage *= 1.5`, `speed *= 1.3`, `scale *= 1.3`.
5. **Elite TANK stacking**: Set `is_elite = true`, `elite_ability = TANK`. Verify speed = `base_speed * 0.7` (NOT `base_speed * 1.3 * 0.7`).
6. **Elite FAST floor**: Set `is_elite = true`, `elite_ability = FAST`, `windup_duration = 0.3`. Verify effective windup = `max(0.2, 0.15) = 0.2`.
7. **Boss phase chaining**: Set boss max_health = 100, deal 70 damage in one hit. Verify `current_phase` transitions from 1→2→3, with `_transition_phase()` called twice.
8. **Projectile collision guards**: Fire enemy projectile at another enemy. Verify it passes through (no hit). Fire player projectile at its source node. Verify it passes through.
9. **Weapon duplication**: Spawn MeleeEnemy with `rusty_sword.tres`, verify `enemy.weapon` is not the same object as the `.tres` resource. Modify `enemy.weapon.damage`, verify `.tres` unchanged.
10. **Separation steering**: Place two enemies at same position in CHASE. Verify they move apart.
11. **Ranged enemy distance**: Place RangedEnemy at distance 40px (closer than `preferred_distance - 20`). Verify it accelerates away from player.
12. **Settle buffer prevents oscillation**: Place RangedEnemy at distance 100px (within `_attack_range` but closer than `preferred_distance`). Advance time by 0.2s (less than `min_attack_settle_time`). Move player to distance 50px (exiting and re-entering range). Verify `_settle_timer` reset, enemy stays in CHASE, never enters WINDUP.
13. **Boss weapon evolution**: Spawn boss, transition to phase 2. Verify `weapon.projectile_count == 3` and `spread_angle == 30`. Kill boss, verify dropped weapon retains these evolved values (not the original 1 count / 10° spread).
