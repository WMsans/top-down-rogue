# Enemy & Status Performance Pass — Design

Date: 2026-06-05
Branch context: `feat/content-expansion`

## Problem

With ~110 enemies on screen the game runs at 40–50 fps instead of a stable 60.
Prior commits raised it from 7 to ~40 fps; this pass targets the next tier.

Godot profiler (≈110 enemies; `×220` physics counts = 110 enemies × 2 physics
steps per frame) shows:

- **Physics 2D — 32.79 ms** (dominant; exceeds the entire 16.6 ms 60fps budget).
  - `Integrate Forces` 18.39 ms.
- **Script `_process` — 11.87 ms**.
- **StatusComponent** — `_process` 3.65 + `update` 3.61 + `tick` 0.91 +
  `_poll_terrain` 2.65 ≈ 11 ms across 111 components.
- Terrain/GPU (`rebuild_dirty` 5.87, readbacks ~5.5, probes 3.24) — already
  optimized by recent commits; **out of scope** for this pass.

### Root causes

1. **110 detection `Area2D`s.** Each enemy creates a radius-150 `Area2D` with
   `collision_mask = 1` in `_ready()`. Player *and* every enemy sit on physics
   layer 1 (`collision_layer = 129`), so each detection circle tracks overlaps
   against every nearby enemy, not just the player — thousands of pointless
   area-body pairs maintained every physics step. The code only ever reads the
   resulting `_player_in_range` bool.
2. **Enemy-vs-enemy physical collision.** All enemies on layer 1 with default
   mask 1, so `move_and_slide` resolves ~110 mutually-overlapping circle bodies
   each step — most of `Integrate Forces`.
3. **O(n²) separation steering.** `enemy.gd._apply_separation()` loops over all
   `attackable` nodes and calls `get_tree().get_nodes_in_group("attackable")`
   (allocating a fresh ~110-element array) per enemy per frame — a second crowd
   system duplicating the physics one.
4. **Per-frame string/group lookups** across all enemies:
   `get_node_or_null("StatusComponent")`, repeated
   `get_tree().get_first_node_in_group("player")`.
5. **Unconditional status signal.** `StatusComponent.tick()` calls
   `changed.emit()` every frame even for enemies with zero stains, firing
   `StatusVisuals.refresh` ×111.

## Decisions (confirmed with user)

- **Crowd separation: steering only.** Disable enemy-vs-enemy physical
  collision; keep crowd spacing via steering, made O(n). Enemies still collide
  with terrain and the player. Enemies softly overlap instead of hard-blocking
  each other.
- **Scope: physics + script/status.** Terrain/GPU readback work deferred.

## Changes

### 1. Remove per-enemy detection areas

Delete the `DetectionArea` `Area2D` + child `CollisionShape2D` created in
`enemy.gd._ready()` and their `body_entered`/`body_exited` handlers. Replace
`_player_in_range` with a direct distance check against the cached player,
computed once per `_process`:

```gdscript
_player_in_range = _player_ref and is_instance_valid(_player_ref) \
    and global_position.distance_squared_to(_player_ref.global_position) \
        <= detection_radius * detection_radius
```

Behaviorally identical — the area only ever toggled that one bool. Removes ~110
monitoring circles from the physics world.

### 2. Stop enemies colliding with each other

Add a dedicated `enemy_body` physics layer in `project.godot` `[layer_names]`
(e.g. `2d_physics/layer_3="enemy_body"`; exact bit chosen during
implementation). Configure:

- **Enemy `collision_layer`:** drop shared layer 1; keep `attackable_hit`
  (layer 8) for being hit + the new `enemy_body` layer.
- **Enemy `collision_mask`:** terrain + player (both reachable via layer 1), so
  enemies still collide with terrain and player. The `enemy_body` layer is
  *not* in the mask, so enemies ignore each other.
- **Player `collision_mask`:** add `enemy_body` so the player still
  pushes/blocks enemies.

Weapon/projectile hit detection uses `attackable_hit` (layer 8) and is
untouched. Removes ~110 mutually-colliding bodies — the bulk of
`Integrate Forces`.

### 3. O(n) crowd steering via a spatial hash

Add a lightweight `SwarmGrid` (RefCounted), owned and rebuilt once per frame by
`world_manager`: a spatial hash keyed on cells of `separation_radius`,
populated from the `attackable` group. API:

- `rebuild(nodes: Array)` — clear and re-bin (called once/frame by world_manager).
- `query_neighbors(pos: Vector2) -> Array` — enemies in the 3×3 cells around
  `pos`.

`enemy.gd`:

- Cache the `SwarmGrid` reference in `_ready()` (one lookup, e.g. via
  world_manager group), not per frame.
- `_apply_separation()` iterates only `query_neighbors(global_position)` instead
  of the whole group; the per-pair math is unchanged so spacing feel is
  preserved.

Drops steering from O(n²) (~12k iterations + 110 array allocations/frame) to
~O(n).

### 4. Cache per-frame node lookups in enemy.gd

- Cache the `StatusComponent` child reference in `_ready()`; use it in
  `_physics_process` and `_get_effective_speed` instead of
  `get_node_or_null("StatusComponent")`.
- Reuse the cached `_player_ref` (with `is_instance_valid` guard) instead of
  re-calling `get_tree().get_first_node_in_group("player")` in
  `_base_effective_speed`, `_get_cooldown_multiplier`, and `_is_targeted`.

### 5. Gate StatusComponent signal + early-out idle entities

In `status_component.gd`:

- In `update()`/`tick()`: if `_stains` is empty **and** `_burn_accum == 0` and
  it is not a terrain-poll frame, return early — skip decay/reactions/effects
  and emit nothing.
- Replace the unconditional `changed.emit()` in `tick()` with emission only when
  state actually changed (a stain added/decayed/cleared, or a burn tick). A
  local dirty flag set by the mutating paths is sufficient.

Behavior is identical for stained entities; idle enemies' steady-state status
cost collapses to near-zero, and `StatusVisuals.refresh` stops firing ×111/frame.

## Non-goals

- Terrain collision rebuild and GPU readback optimization (`rebuild_dirty`,
  `read_terrain_probe`, `read_collider_buffer_coalesced`, probe batching).
- Changing AI behavior, attack timing, or status mechanics.
- Reworking `player_controller.gd`'s `attackable`-group iteration (not a
  measured hotspot).

## Verification

Re-open the Godot profiler with the same ~110-enemy scene and confirm:

- `Physics 2D` drops well below 16.6 ms.
- `Enemy._physics_process` / `_process` and the separation cost shrink.
- `StatusComponent` per-frame cost falls for idle enemies.
- Stable 60 fps.

Gameplay sanity check: enemies still chase, attack, get blocked by terrain and
the player, take blood/status reactions, and crowd-space without hard-stacking.

## Risks

- **Layer reorg** is the highest-risk change; a wrong bit could break
  player/terrain collision or hit detection. Mitigate by verifying each
  interaction (enemy↔terrain, enemy↔player, weapon↔enemy, enemy↔enemy)
  explicitly after the change.
- **Steering grid staleness:** rebuilt once/frame in `_process`; enemies read it
  the same frame. Acceptable for soft separation.
