# SP-B.1 — SP-B Modifier Scripts

**Date:** 2026-06-16
**Branch:** feat/content-expansion
**Phase 7 sub-project:** B.1 (6.5) — the 7 modifier scripts riding on SP-B's statuses & combat hooks
**Depends on:** SP-A (DataModifier dispatch, `resolve_hit` chokepoint) and SP-B (statuses
`steam`/`lightning`/`stun`, verbs `apply_knockback`/`add_timed_status`/`place_steam`/`heal`/`add_gold`)

## 1. Problem

SP-B shipped all the infrastructure (statuses, combat verbs, entity hooks) for seven content
modifiers, but the modifiers themselves are unbuilt. Their CSV rows already exist in
`modifiers.csv`; with no behavior, all seven currently fall through `WeaponRegistry._make_modifier`
to a `DataModifier` that does not yet handle their effect verbs (`spawn_projectile`, `knockback`,
`pull`, `bounty`, `stun`, conditional `apply_status`). This sub-project supplies the behavior layer.

### 1.1 The seven modifiers (CSV rows, already authored)

| id | rarity | category | trigger | condition | effect | element | magnitude | magnitude2 |
|---|---|---|---|---|---|---|---|---|
| chain_spark | Rare | projectile | on_crit | — | spawn_projectile | lightning | 3 | 0 |
| steam_burst | Rare | trigger | on_hit | target_status:wet | apply_status | steam | 3 | 0 |
| concussive_edge | Uncommon | trigger | on_hit | — | stun | — | 0.5 | 0.2 |
| repulsor_nova | Rare | utility | on_charge | — | knockback | — | 80 | 0 |
| shockwave_stomp | Uncommon | utility | on_swing | — | knockback | — | 40 | 0 |
| magnet_field | Common | utility | on_swing | — | pull | — | 48 | 0 |
| midas_touch | Uncommon | utility | on_kill | — | bounty | — | 5 | 0 |

## 2. Approach: Hybrid (DataModifier + one bespoke script)

Six modifiers are parameterized verbs that extend `DataModifier`'s existing dispatch tables; they
need no new files and route through `_make_modifier`'s existing `DataModifier` fallback. Only
**chain_spark** — which chains lightning to multiple targets and draws arc VFX — becomes a bespoke
`Modifier` subclass in the established `lightning_bolt`/`penetrating_shockwave` pattern.

This keeps `DataModifier` the declarative path for simple parameterized effects and isolates the one
genuinely spatial/visual behavior in its own file.

## 3. Infra additions (2, minimal)

### 3.1 `on_crit` modifier hook

No current path invokes modifiers on a crit — `Weapon.resolve_hit` calls only `_on_crit(target)`
(weapon's own `crit_status`). Add a hook:

- `src/weapons/modifier.gd`: add `func on_crit(_weapon: Weapon, _user: Node, _target: Node) -> void: pass`.
- `src/weapons/weapon.gd`, in `resolve_hit`, immediately after the existing `if is_crit: _on_crit(target)`:
  ```gdscript
  if is_crit:
      for m in modifiers:
          if m != null:
              m.on_crit(self, user, target)
  ```
  (Fold into the existing `if is_crit:` block.) Harmless no-op for every modifier except chain_spark.

### 3.2 `"pickup"` group on drops

`GoldDrop` (Area2D, self-magnets within 100px) and `Drop` (RigidBody2D, no magnet) are in **no
group**, so `magnet_field` cannot find them without a physics scan. Add each to a `"pickup"` group:

- `src/drops/gold_drop.gd` `_ready()`: `add_to_group("pickup")`.
- `src/drops/drop.gd` `_ready()`: `add_to_group("pickup")`.

`WeaponDrop` and `ModifierDrop` extend `Drop`, so they inherit membership.

## 4. DataModifier extensions (6 modifiers)

All additions live in `src/weapons/modifiers/data_modifier.gd`, extending the existing dispatch
methods. New constants at top of file as noted.

### 4.1 knockback — shockwave_stomp (on_swing), repulsor_nova (on_charge)

In `on_attack(weapon, user, ctx)`, add an `effect == "knockback"` branch alongside the existing
`spawn_material` branch:

- **Trigger gating:**
  - `trigger == "on_swing"` → fire on every swing.
  - `trigger == "on_charge"` → fire only when `ctx.get("charged", false)` and
    `ctx.get("charge_ratio", 0.0) >= 1.0` (mirrors `penetrating_shockwave_modifier`).
- **Radius** derives from magnitude so nova out-ranges stomp without a new CSV column:
  `radius = magnitude * KNOCKBACK_RADIUS_FACTOR` where `const KNOCKBACK_RADIUS_FACTOR := 1.8`
  (stomp ≈ 72px, nova ≈ 144px).
- **Effect:** for each node in `attackable` within `radius` of `user` that is a `Node2D` and
  `has_method("apply_knockback")`:
  `var dir := (n.global_position - user.global_position)` (fall back to `Vector2.DOWN` if zero);
  `n.apply_knockback(dir, magnitude)`.

Helper `_radial_targets(user, radius) -> Array[Node2D]` keeps the query reusable (shared with §4.2).

### 4.2 pull — magnet_field (on_swing)

In `on_attack`, add an `effect == "pull"` branch (trigger `on_swing`):

- For each node in group `"pickup"` within `magnitude` (48px) of `user`:
  - **GoldDrop** (has `_velocity`): nudge toward user — give it velocity toward the player so its
    existing magnet/move loop carries it in. Concretely: add a directed impulse to `_velocity`
    (`drop._velocity += dir * PULL_IMPULSE`), `const PULL_IMPULSE := 220.0`.
  - **RigidBody2D `Drop`**: `drop.apply_central_impulse(dir * PULL_IMPULSE)`.
- Type detection by `is GoldDrop` / `is Drop`; skip anything else.

`magnitude` (48) is the pull radius and is intentionally easy to retune in the CSV.

### 4.3 bounty — midas_touch (on_kill)

In `on_kill(weapon, user, target)`, add an `effect == "bounty"` branch:

- `var inv = user.get_node_or_null("PlayerInventory")`;
  `if inv != null and inv.has_method("add_gold"): inv.add_gold(int(magnitude))` (5).

This sits beside the existing `on_kill` heal/stat_add branches.

### 4.4 stun-chance — concussive_edge (on_hit)

In `on_hit_target(weapon, user, target)`, add an `effect == "stun"` branch:

- `if randf() < magnitude2 (0.2):` get `target`'s `StatusComponent`; if present,
  `sc.add_timed_status("stun", magnitude)` (0.5s).

### 4.5 conditional steam — steam_burst (on_hit, condition target_status:wet)

The existing `on_hit_target` `apply_status` branch adds the stain **unconditionally**. Two changes:

1. **Honor the condition.** Gate the `apply_status` branch on `_condition_met(target)` (the helper
   already parses `target_status:wet`). Empty condition → `true`, so the SP-A status-edge modifiers
   (venom/soaking/greased/frostbite/ember/rending) are unaffected — **no regression**.
2. **Steam erupts a cloud.** When `element == "steam"` and the condition is met:
   `TerrainSurface.place_steam(target.global_position, STEAM_BURST_RADIUS, STEAM_BURST_DENSITY)`
   (`const STEAM_BURST_RADIUS := 14.0`, `const STEAM_BURST_DENSITY := 180`) **and** stain the struck
   target (`sc.add_stain("steam", magnitude)`). The cloud terrain-polls steam onto any nearby foe —
   this is the "spreading the burn" behavior. For non-steam elements, behavior is unchanged
   (`sc.add_stain(element, magnitude)`).

## 5. Bespoke: chain_spark

New `src/weapons/modifiers/chain_spark_modifier.gd` (`class_name ChainSparkModifier extends Modifier`),
registered in `WeaponRegistry._ready`: `modifier_scripts["chain_spark"] = preload(...)`. Name,
description, and `suppresses_base_use` are overlaid from the CSV by `_make_modifier` (existing path).

Constants:
- `const RANGE := 160.0` (chain reach, mirrors `lightning_bolt`)
- `const MAX_TARGETS := 3` (== CSV magnitude; read from a `var chain_count := 3` for clarity)
- `const DAMAGE := 6`
- `const LIGHTNING_DURATION := 0.4` (matches the `lightning` status default_duration)
- `const STUN_CHANCE := 0.25`
- `const STUN_DURATION := 0.3`
- `const TINT := Color(0.9, 0.95, 1.0)`

`on_crit(weapon, user, target)`:
1. Collect up to `MAX_TARGETS` nearest nodes in group `"attackable"` within `RANGE` of `user`
   (Node2D, valid). The directly-struck `target` may be included; ordering is by distance.
2. For each chained node `n`:
   - `if n.has_method("on_hit_impact"): n.on_hit_impact(n.global_position, (n.global_position - user.global_position).normalized(), DAMAGE)`
   - `var sc = n.get_node_or_null("StatusComponent"); if sc: sc.add_timed_status("lightning", LIGHTNING_DURATION)`
     (reacts with `wet`→steam via SP-B reaction rule 7)
   - `if randf() < STUN_CHANCE and sc: sc.add_timed_status("stun", STUN_DURATION)`
   - `LightningArcFX.play(host, user.global_position, n.global_position, TINT)`

A private `_nearest_targets(user, count, range) -> Array[Node2D]` does the bounded nearest-N query.

## 6. chain_spark VFX: LightningArcFX

New `src/weapons/fx/lightning_arc_fx.gd` (`class_name LightningArcFX extends Node2D`). Self-drawing
(no scene or texture asset — uses `_draw`, as the codebase already does in `collision_overlay`).

- **`static func play(host: Node, from: Vector2, to: Vector2, tint: Color) -> void`** — instantiates
  the node, `host.add_child(fx)`, stores `from`/`to`/`tint` in local space, computes the jagged
  point list once, starts a tween. If `host` is null, no-op. (chain_spark resolves `host` as the
  world chunk container via the same pattern as `ModifierProjectile._resolve_parent`, falling back to
  `user.get_parent()`.)
- **Jagged bolt:** subdivide `from`→`to` into `SEGMENTS` (≈7) steps; perturb each interior point
  perpendicular to the segment by `randf_range(-JITTER, JITTER)` (`JITTER ≈ 6px`). Store the list.
- **`_draw()`** renders in one pass:
  - bolt: `draw_polyline(points, wide faint tint, 3.0)` underlay for glow + `draw_polyline(points,
    bright tint, 1.0)` core.
  - impact flash at `to`: a small `draw_circle(to_local, r, tint)` plus a few short radial spikes
    (`draw_line`) for a starburst.
- **Tween:** over `LIFETIME ≈ 0.15s`, drive `modulate.a` 1→0 (and a slight flash scale-up via
  `queue_redraw` each step or a single `scale` tween), then `queue_free()`.

`lightning_bolt_modifier` may later drop its `wall.png` placeholder for `LightningArcFX`; out of
scope here but the helper is built to allow it.

## 7. Registration summary

| Modifier | Path |
|---|---|
| chain_spark | bespoke script, registered in `modifier_scripts` |
| steam_burst, concussive_edge, repulsor_nova, shockwave_stomp, magnet_field, midas_touch | `DataModifier` fallback (no registration) |

## 8. Files touched

| File | Change |
|---|---|
| `src/weapons/modifier.gd` | add `on_crit` no-op hook |
| `src/weapons/weapon.gd` | `resolve_hit` invokes `on_crit` on modifiers when `is_crit` |
| `src/weapons/modifiers/data_modifier.gd` | knockback, pull, bounty, stun, conditional-steam branches + `_radial_targets` helper + constants |
| `src/weapons/modifiers/chain_spark_modifier.gd` (+`.uid`) | new bespoke modifier |
| `src/weapons/fx/lightning_arc_fx.gd` (+`.uid`) | new self-drawing arc VFX |
| `src/autoload/weapon_registry.gd` | register `chain_spark` |
| `src/drops/gold_drop.gd`, `src/drops/drop.gd` | `add_to_group("pickup")` |
| tests | see §9 |

## 9. Testing (gdUnit4)

Run headless per `AGENTS.md` (import first, then `GdUnitCmdTool`). Use lightweight stub nodes
(Node2D with `apply_knockback`/`on_hit_impact`/`health` and a child `StatusComponent`) as in existing
tests.

- **`test_data_modifier.gd`** (extend):
  - knockback: in-range target receives `apply_knockback`; out-of-range skipped; nova fires only at
    `charged && charge_ratio>=1.0`, stomp fires every swing; radius scales with magnitude.
  - pull: GoldDrop in range gains velocity toward user, RigidBody Drop gets an impulse; nodes outside
    `"pickup"` or outside radius untouched.
  - bounty: `add_gold(5)` called on user's PlayerInventory on kill.
  - stun: `magnitude2 = 1.0` always stuns (`add_timed_status("stun", 0.5)`); `0.0` never does.
  - steam_burst: target with `wet` stain → `place_steam` invoked + steam stain added; target without
    `wet` → nothing; verify existing unconditional status-edge modifiers (empty condition) still apply.
- **`test_chain_spark.gd`** (new): caps at 3 targets, respects `RANGE` (far enemy excluded), calls
  `on_hit_impact` + adds `lightning` per chained target; `STUN_CHANCE` forced 0/1 drives stun on/off.
- **`test_weapon.gd`** (or resolve_hit test): `on_crit` modifier hook fires on crit, not on non-crit.
- **`test_lightning_arc_fx.gd`** (smoke): `play()` spawns a node under host, `_draw` runs without
  error, node auto-frees after lifetime.

## 10. Acceptance

- All six DataModifier verbs dispatch correctly; chain_spark chains to ≤3 enemies with lightning +
  stun roll and draws arc + impact VFX.
- `on_crit` modifier hook added and invoked only on crit.
- Drops are in the `"pickup"` group; magnet_field pulls both gold and item drops.
- steam_burst honors the `wet` condition and erupts a steam cloud; SP-A status-edge modifiers
  unchanged.
- `chain_spark` registered; the other six resolve via `DataModifier` with no registration.
- All existing tests green; new tests added and green.
