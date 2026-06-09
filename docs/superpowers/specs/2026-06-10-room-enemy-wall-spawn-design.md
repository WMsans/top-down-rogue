# Room Enemy Wall-Spawn Fix

**Date:** 2026-06-10
**Status:** Approved (design)

## Problem

Enemies can spawn inside solid terrain, but only in **rooms** (template-marker
spawns), never in open **terrain**. The cause is an asymmetry between the three
spawn paths:

| Path | File | Wall validation |
|------|------|-----------------|
| Ambient terrain spawns | `src/core/cave_spawner.gd` | `_is_clear_of_walls()` — reads a 13×13 footprint via `read_region`, requires all `MAT_AIR` |
| Terrain compositions / arena features | `src/core/composition_dispatcher.gd` | `mask_air` / `_is_air()` — single-pixel air read |
| **Room template markers** | `src/core/spawn_dispatcher.gd` | **none** — enemy placed verbatim at the marker's world position |

Room enemies originate from authored PNG markers, decoded in
`spawn_dispatcher._spawn_for_slot()` and dispatched through
`_spawn_entity()` → `_spawn_enemy()` (`spawn_dispatcher.gd:123-175`). The
marker's world position is used directly with no solidity check, so any marker
that sits on or near a wall pixel — from authoring, rotation rounding, or wall
thickness — produces an enemy embedded in solid terrain.

## Goal

Give the room enemy path the same wall awareness the other two paths already
have: never place a room enemy inside solid terrain. When a marker lands on a
wall, relocate the enemy to the nearest open spot; if none is reachable nearby,
skip that spawn.

## Scope

- **In scope:** normal enemy markers (type `1`) and elite enemy markers
  (type `2`) in `spawn_dispatcher`.
- **Out of scope — bosses (type `6`):** boss arenas are large open spaces where
  wall-clipping is not a concern, and the boss death-portal is bound to the
  *original* marker position via `_on_boss_died` (`spawn_dispatcher.gd:172`).
  Nudging a boss would desync the portal for no benefit. Boss spawns are left
  unchanged.
- **Out of scope:** chests (`3`, `5`), shops (`4`), lanterns (`8`). The user
  scoped this fix to enemies only. (A chest sealed in a wall is a known
  follow-up, not part of this change.)

## Design

### 1. Shared footprint helper

Extract the "is this square footprint entirely air?" test — currently
`cave_spawner._is_clear_of_walls()` — into a small shared static helper so the
room path and the cave path cannot drift apart.

New file: `src/core/spawn_validation.gd`

```gdscript
class_name SpawnValidation
extends RefCounted

const DEFAULT_HALF: int = 6   # 13×13 footprint ≈ enemy body; matches cave_spawner

# True if every cell in the square footprint centered on world_pos is MAT_AIR.
# Reads actual chunk material via world_manager.read_region (same source as
# player-spawn validation), not the async terrain_physical probe cache.
# Cells outside any active chunk read as 255 and count as NOT clear, so we never
# spawn into unloaded terrain.
static func footprint_clear(world_manager, world_pos: Vector2, half: int = DEFAULT_HALF) -> bool:
    if world_manager == null or not is_instance_valid(world_manager):
        return false
    var origin := Vector2i(int(floor(world_pos.x)) - half, int(floor(world_pos.y)) - half)
    var side := half * 2 + 1
    var data: PackedByteArray = world_manager.read_region(Rect2i(origin, Vector2i(side, side)))
    if data.size() != side * side:
        return false
    var air := MaterialRegistry.MAT_AIR
    for i in range(data.size()):
        if data[i] != air:
            return false
    return true
```

`cave_spawner._is_clear_of_walls()` is rewritten to delegate:

```gdscript
func _is_clear_of_walls(world_pos: Vector2) -> bool:
    return SpawnValidation.footprint_clear(_world_manager, world_pos, SPAWN_CLEAR_HALF)
```

`SPAWN_CLEAR_HALF` (= 6) in `cave_spawner` is kept as the value it passes, so
cave-spawner behavior is byte-for-byte unchanged.

### 2. Nudge-else-skip in spawn_dispatcher

Add a spiral search that returns the nearest clear position, or `null` when the
marker is boxed in. The spiral lives in `spawn_dispatcher` because only the room
path needs to relocate.

```gdscript
const NUDGE_CELL: int = 8      # search step (one passability cell)
const NUDGE_MAX_RINGS: int = 3 # outward radius ≈ 24px

# Returns world_pos unchanged if its footprint is clear; otherwise the nearest
# clear position within NUDGE_MAX_RINGS; otherwise null (caller skips the spawn).
func _resolve_clear_position(world_pos: Vector2) -> Variant:
    if SpawnValidation.footprint_clear(_world_manager, world_pos):
        return world_pos
    for ring in range(1, NUDGE_MAX_RINGS + 1):
        var r := ring * NUDGE_CELL
        # Walk the ring's perimeter, nearest cells first.
        for dy in range(-ring, ring + 1):
            for dx in range(-ring, ring + 1):
                if abs(dx) != ring and abs(dy) != ring:
                    continue  # interior already covered by smaller rings
                var cand := world_pos + Vector2(dx * NUDGE_CELL, dy * NUDGE_CELL)
                if SpawnValidation.footprint_clear(_world_manager, cand):
                    return cand
    return null
```

`_spawn_entity` validates before spawning enemies, leaving boss (`6`) and all
non-enemy markers on their current direct path:

```gdscript
func _spawn_entity(marker: int, world_pos: Vector2, sector_dist: int, floor_num: int, is_boss_room: bool) -> void:
    match marker:
        1: _spawn_enemy_validated(world_pos, sector_dist, floor_num, false, false)
        2: _spawn_enemy_validated(world_pos, sector_dist, floor_num, false, true)
        3: _spawn_chest(world_pos, false)
        4: _spawn_shop(world_pos)
        5: _spawn_chest(world_pos, true)
        6: _spawn_enemy(world_pos, sector_dist, floor_num, true, false)  # boss: unchanged
        7: pass
        8: _spawn_lantern(world_pos)

func _spawn_enemy_validated(world_pos: Vector2, sector_dist: int, floor_num: int, is_boss: bool, is_elite: bool) -> void:
    var resolved: Variant = _resolve_clear_position(world_pos)
    if resolved == null:
        return  # boxed in — skip rather than embed in a wall
    _spawn_enemy(resolved, sector_dist, floor_num, is_boss, is_elite)
```

`_spawn_enemy` itself is unchanged.

## Data flow

```
chunks_generated
  → _on_chunks_generated → _spawn_for_slot (decode markers, apply rotation)
    → _spawn_entity(marker, world_pos, …)
        marker 1/2  → _spawn_enemy_validated
                        → _resolve_clear_position (SpawnValidation.footprint_clear, spiral)
                            clear  → _spawn_enemy(resolved …)
                            null   → skip
        marker 6    → _spawn_enemy (boss, unchanged)
        other       → existing handlers (unchanged)
```

## Edge cases

- **Marker already in air:** fast path returns it unchanged — zero behavior
  change for the common case.
- **Marker in a wall with adjacent air:** relocated to the nearest clear cell,
  staying within ~24px of the authored position.
- **Marker fully boxed in (no clear cell within 3 rings):** skipped. Acceptable
  — better a missing enemy than one stuck in a wall.
- **Position in unloaded terrain (read returns 255 / wrong size):** treated as
  not clear, so the spiral continues and may skip. Consistent with
  cave_spawner's existing rule.

## Testing

New unit test `tests/unit/test_spawn_validation.gd`:

- `footprint_clear`: all-air region → true; region with any non-air cell → false;
  region with a `255` (out-of-chunk) cell → false; wrong-sized read → false.
  Uses a stub `world_manager` exposing `read_region(Rect2i)`.

New unit test for the spiral (in `tests/unit/test_spawn_dispatcher.gd` or a
focused test), driving `_resolve_clear_position` against a stub material source:

- Marker on air → returns the same position.
- Marker on a wall with air one cell away → returns that nearest cell.
- Marker fully enclosed within the search radius → returns `null`.

Existing `cave_spawner` behavior is covered by its current tests, which must
still pass after the delegation refactor.

## Files touched

- **New:** `src/core/spawn_validation.gd` — shared `footprint_clear` helper.
- **New:** `tests/unit/test_spawn_validation.gd`.
- **Edit:** `src/core/spawn_dispatcher.gd` — add `_resolve_clear_position`,
  `_spawn_enemy_validated`; route markers `1`/`2` through validation.
- **Edit:** `src/core/cave_spawner.gd` — `_is_clear_of_walls` delegates to
  `SpawnValidation.footprint_clear`.
- **Edit/New:** spiral unit test.
