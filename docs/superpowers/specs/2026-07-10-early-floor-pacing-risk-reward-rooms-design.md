# Early-Floor Pacing & Procedural Risk/Reward Rooms — Design

**Date:** 2026-07-10
**Status:** Approved for planning

## Problem

The game is too punishing at the start of a floor, for three compounding reasons:

1. **Ambient crowds are full-density right next to spawn.** `cave_spawner.gd` spawns
   Minecraft-style ambient enemies with no scaling by distance from origin `(0,0)`, so
   the opening seconds can be a wall of bodies.
2. **Elite rooms and elite enemies appear immediately.** Elite arena rooms
   (`is_elite_chest` templates) roll anywhere in the play area, and `elite_chance`
   is a flat `0.15` everywhere — so hard content lands adjacent to spawn.
3. **Progression rooms are too sparse and random.** The player can wander a long time
   before finding a chest or shop, so there is little agency to "advance" (obtain
   weapons and modifiers).

## Goals

- Make the area near spawn (`(0,0)`, the center of the floor) gentler: fewer ambient
  enemies, no elites.
- Give the player frequent, legible **risk/reward rooms** — Slay-the-Spire-style choices
  translated into diegetic, in-world interactables — so there is always a decision that
  advances the run.
- Keep elites and the boss where they belong: the outer half of the floor and the boss
  ring (Chebyshev sector distance 8).

## Non-goals

- No node-map / menu-driven event UI. All choices are made by physically acting in the
  world (Slay-the-Spire *decisions*, not its *presentation*).
- No per-weapon upgrade system (Rest Spring was cut for this reason).
- No fixed-anchor "guaranteed reward ring." Reward/event rooms are fully procedural.
- No changes to boss placement, the bedrock wall, or the secret-room system.

## World-layout facts this builds on

- `SectorGrid` (`src/core/sector_grid.gd`): sectors are `384px`. Origin `(0,0)` is spawn.
  Play area is Chebyshev sector distance `0..7`; the boss ring is at distance `8`
  (`WALL_INNER_SECTORS = 8`). `resolve_sector()` rolls each non-fixed sector
  independently (seeded) for empty-vs-room, weighted by `RoomTemplate.weight` against
  `EMPTY_WEIGHT = 1.5`.
- `enemy_tier_for_distance(dist)` already maps sector distance `0..8` to three tiers
  (0–2, 3–5, 6–7).
- `CaveSpawner` (`src/core/cave_spawner.gd`): ambient spawner, `mob_cap = 70`, groups of
  3–5, flat `elite_chance = 0.15`, no origin-distance scaling.
- `PickupContext` (`src/player/pickup_context.gd`): any node exposing
  `get_pickup_type()`, `should_auto_pickup()`, `populate_info_card()`,
  `set_highlighted()`, and `interact()` automatically gets proximity highlight, an info
  popup (`WeaponInfoPopup`), and interact-key handling. This is the substrate for both
  room Signs and room interactables.
- Rooms are authored as `RoomTemplate`s; "carved" set-piece rooms use
  `cavern_carve = true` + an `ArenaComposition` whose `features: Array` place content
  (see `src/core/features/*` and `feature_chest_spawn.gd`, `composition_dispatcher.gd`).
- Loot already exists as pickups: `weapon_drop.gd`, `modifier_drop.gd`,
  `shop_modifier_drop.gd`; `CompositionDispatcher.spawn_chest(pos, rare)` spawns chests.

---

## Pillar 1 — Gentle global crowd reduction near spawn

Add an **origin-distance density ramp** to `CaveSpawner`. On each spawn tick, compute the
player's Chebyshev sector distance from origin (reuse the pattern already in
`_pick_pooled_weapon`: `grid.world_to_sector(player_pos)` →
`grid.chebyshev_distance(sector, Vector2i.ZERO)`), then derive a multiplier:

```
density_mult = lerp(NEAR_ORIGIN_MULT, 1.0, clampf(dist / WALL_INNER_SECTORS, 0, 1))
```

with `NEAR_ORIGIN_MULT ≈ 0.45`. The multiplier scales, each tick:

- **Effective mob cap:** `int(mob_cap * density_mult)` used in the cap check.
- **Spawn probability:** multiply the `spawn_rate * BASE_SPAWN_CHANCE` gate in
  `_validate_position()`.
- **Group size:** scale `group_size_min`/`group_size_max` (floor at 1).

Also trim the baseline: `mob_cap 70 → 50`.

This is a smooth global falloff, not a hard safe-bubble: the innermost tier is light but
not empty, ramping to full density by the outer ring.

## Pillar 2 — Elites gated out of the early zone

- **Elite arena rooms:** in `SectorGrid.resolve_sector()`, add `ELITE_MIN_DIST = 3`. When
  the weighted roll selects a template with `is_elite_chest == true` and the sector's
  Chebyshev distance from origin is `< ELITE_MIN_DIST`, treat the roll as **empty**
  (do not reroll into a different room — keeping the seeded determinism simple). Elite
  rooms therefore only appear at distance `≥ 3`.
- **Ambient elites:** scale `CaveSpawner`'s per-enemy elite roll by the same
  `density_mult` (or directly by `dist`), so near-spawn ambient enemies are almost never
  elite while the outer floor keeps its full `elite_chance`.

## Pillar 3 — Procedural risk/reward rooms

### Placement & frequency

No fixed backbone. All new rooms are `RoomTemplate`s placed by the existing procedural
roll in `resolve_sector()`. To make them frequent enough to feel like the primary way to
advance:

- Give reward/event templates a raised `weight` (tune during implementation; start each
  around `2.0–3.0`).
- Lower `EMPTY_WEIGHT` from `1.5` to `~1.0` so fewer sectors are empty.

Both values are tuning knobs; the plan should expose them clearly and include a test that
pins the resulting reward-room density within a target band.

### Diegetic interaction + Signs

Every risk/reward room is **diegetic** — the player commits by acting, never through a
menu. Each room contains a **Sign**: a static node that reuses the `PickupContext` hooks
(`should_auto_pickup() → false`, `populate_info_card()` returns the room's description) so
that standing near it shows the room's risk/reward in the existing `WeaponInfoPopup`,
exactly like reading a weapon drop. The Sign has no `interact()`; it is informational
only. The room's interactable(s) implement `interact()` (and their own
`populate_info_card()` where useful).

### Shared substrate

- **`InteractableShrine` base** (`src/core/interactables/` or similar): a node exposing
  the `PickupContext` contract (highlight + info popup + `interact`). Concrete rooms
  subclass or configure it.
- **`FeatureShrine` / room compositions:** each room is an `ArenaComposition`
  (`cavern_carve`) with a feature that carves the space and places the shrine + Sign,
  mirroring `feature_chest_spawn.gd` / `feature_enemy_pack.gd`.
- **Curse status:** one new lasting negative status built on the existing Noita-style
  status system. A curse **persists until cured** by a Purge Font **or** until the player
  descends to the next floor — whichever comes first. `LevelManager.advance_floor()`
  clears active curses. Consumed by Devil's Bargain, Wheel of Fortune, and Purge Font.
- **Drop-item-on-machine:** an interaction where the player deposits a held weapon/modifier
  onto a machine. Shared by the Transmutation Forge (and future Duplicator).

### Roster (10 new rooms + boosted Shop/Treasure anchors)

The existing **Shop** and a plain **Treasure** chest room stay in the procedural pool as
the no-gamble anchors, with the boosted weights above.

| Room | Sign text (intent) | Diegetic commit | Risk → Reward |
|------|--------------------|-----------------|----------------|
| **Blood Altar** | "Offer blood for power" | Step into the blood pool | −HP or −max-HP → guaranteed rare weapon/modifier |
| **Purge Font** | "Cleanse a curse" | Walk in (spends gold) | Remove an active curse, or heal if none |
| **Transmutation Forge** | "Sacrifice to reforge" | Drop a weapon/modifier on it | Consume the deposited item → reroll/upgrade another held item |
| **Wheel of Fortune** | "Spin, if you dare" | Activate (spends gold) | Jackpot (rare drop) / nothing / backfire (spawns an elite) |
| **Mimic Chest** | "Too good to be true?" | Shoot it open | Great loot **or** it's a mimic → ambush wave |
| **Devil's Bargain** | "Power at a price" | Pick up the cursed modifier | Strong modifier bound to a permanent curse |
| **Whispering Idol** | "Make a pact" | Touch the idol | Floor-long buff bound to a floor-long hex (enraged/faster spawns) |
| **Trial Gauntlet** | "Prove yourself" | Walk through the sealed door | Hard elite wave → relic-tier loot |
| **Greed Vault** | "Take it and run" | Grab the gold/chest | Loot, but touching it starts continuous spawns until you leave |
| **Reactor Chamber** | "Volatile — beware" | Just entering | Status-hazard-flooded loot room; reactions hit player *and* enemies |

---

## Implementation phases (single plan, ordered by dependency)

**Phase 1 — Pacing + substrate**
- Pillar 1 density ramp + `mob_cap` trim in `CaveSpawner`.
- Pillar 2 elite gating in `SectorGrid` + ambient-elite scaling in `CaveSpawner`.
- Room-placement weight changes (`EMPTY_WEIGHT`, reward/event weights).
- `InteractableShrine` base + `Sign` node (reusing `PickupContext`).
- Treasure anchor room (composition + chest feature) as the first roster proof.

**Phase 2 — Easy diegetic rooms**
- Mimic Chest, Greed Vault, Reactor Chamber, Trial Gauntlet, Blood Altar.
  (No new subsystems; use chests, ambush spawns, status hazards, HP cost.)

**Phase 3 — Subsystem rooms**
- Curse status → Devil's Bargain, Wheel of Fortune, Purge Font
  (+ `advance_floor()` curse clear).
- Drop-item-on-machine → Transmutation Forge.
- Floor-long pact → Whispering Idol.

## Testing

Follow existing unit-test patterns:

- `test_sector_grid` — elite gating at `dist < 3` yields empty; boosted weights produce
  reward rooms within a target density band; seeded determinism preserved.
- `test_cave_spawner` — density ramp reduces effective cap / group size / spawn
  probability near origin and reaches full at the outer ring; ambient elite chance scales
  down near origin.
- Per-room composition tests mirroring `test_arena_composition` / `test_feature_*`:
  each room's feature carves the space and places its shrine + Sign.
- Curse status test: applied by Devil's Bargain/Wheel, cleared by Purge Font and by
  `advance_floor()`.

## Risks & mitigations

- **Scope.** 10 rooms + curse status + pact + item-sacrifice is large. Mitigated by the
  phased plan and shared substrate; Phases 2 and 3 can ship incrementally.
- **Density tuning.** Lowering `EMPTY_WEIGHT` and raising reward weights can over-fill the
  floor. Mitigated by the density-band test and keeping both values as explicit knobs.
- **Diegetic legibility.** Players must understand a gamble before committing. Mitigated
  by the mandatory Sign in every room, reusing the proven weapon-info popup.
- **Determinism.** Elite gating must not break seeded reproducibility. Mitigated by
  converting a gated roll to *empty* rather than rerolling.
