# Status Effect System — Design (Sub-project 1)

**Date:** 2026-06-04
**Scope:** First sub-project of the weapon/modifier content expansion (Phase 7 in
`docs/design_docs/implementation_todo.md`). Builds a Noita-style status effect system as a
core mechanic, plus the crit system that is one of its sources, and wires up the four
crit-driven weapons.

## Goal & context

The CSV data and `.tres` files for all 24 weapons and 11 modifiers already exist. What is
missing is the *behavior* the descriptions promise. We are building the shared combat
foundations first; this spec covers the status + crit foundation.

Status effects are intended as a **first-class core mechanic** (not a crit side-feature):

- The **same `StatusComponent` is shared by both player and enemies**.
- Modeled after **Noita**: status is meant to be one of the most common reasons the player
  dies (e.g. On Fire damage-over-time).
- Statuses include **harmful, neutral, and beneficial** kinds.
- Statuses **react to each other** (e.g. Wet/Bloody extinguish On Fire; Wet + Chilly →
  Frozen).
- Statuses are applied from **multiple sources**: terrain/material contact, weapon crits,
  and (later) modifiers.

The full ~30-status Noita catalog (Toxic, Poisoned, Drunk, Satiation tiers, Wormy Vision,
etc.) is **deferred**; this spec builds the framework plus a focused six-status fire/cold
set, and must keep adding new statuses cheap.

## Intensity model: Noita-style stain

Each status is tracked as a **stain amount** (float) on the entity:

- **Sources** add stain (`add_stain(id, amount)`).
- Stain **decays** toward 0 each frame at the status's `decay_rate` (units/sec).
- The status is **active** while its stain is above its `active_threshold`.
- **Reactions** transfer/consume stain between statuses (e.g. Wet stain drains On Fire
  stain). Standing in a source (lava, water) keeps topping the stain back up.

This model is what produces the emergent reaction feel and is the agreed approach over a
simpler timed-duration model.

## Architecture

Three new pieces, plus thin hooks on existing entities. The component is pure mechanism;
all data and reactions live in the registry; owners provide only damage + movement hooks.

### 1. `StatusRegistry` (autoload, data-driven)

Single source of truth. Defines each status as a `StatusDef` and holds the reaction rules.
Adding a future status = adding one `StatusDef` entry (plus any reaction rules).

`StatusDef` fields:

- `id: String`
- `display_name: String`
- `tint_color: Color`
- `decay_rate: float` (stain lost per second)
- `active_threshold: float`
- `category: int` (HARMFUL / NEUTRAL / BENEFICIAL)
- `effect: String` + params — e.g. `"burn"` with `dps`, `"movement_block"`, `"slow"` with
  factor.

Suggested file layout (following existing `src/` conventions):

- `src/autoload/status_registry.gd` (autoload) — defs + reaction rules + lookups.
- `src/status/status_def.gd` — `StatusDef` class.
- `src/status/status_component.gd` — `StatusComponent` node.

### 2. `StatusComponent` (Node, child of player and each enemy)

Shared holder. Owns `_stains: Dictionary` (id → float amount).

API:

- `add_stain(id: String, amount: float) -> void`
- `get_stain(id: String) -> float`
- `has_status(id: String) -> bool` (stain > threshold)
- `is_movement_blocked() -> bool` (Frozen / Stunned active)
- `clear(id: String) -> void`
- signal `changed` (drives visuals / HUD)

Each `_physics_process(delta)`:

1. **Decay** every stain toward 0 by `decay_rate * delta`.
2. Run **reactions** (consume/convert stains; see below).
3. Apply **active-status effects**: `burn` calls `owner.apply_status_damage(dps * delta)`;
   `movement_block`/`slow` are exposed via query methods the owner reads.
4. Poll the **terrain under the owner** (reusing the existing
   `terrain_physical.query(pos)` → `TerrainCell.material_id` pattern from
   `LavaDamageChecker`) and add stains from material:
   `WATER → Wet`, `LAVA`/fire → `On Fire`, `OIL → Oiled`, `BLOOD → Bloody`.
5. Emit `changed`.

The component locates `TerrainPhysical` in `_ready` the same way `LavaDamageChecker` /
`TerrainDamageReceiver` do (via the `WorldManager` node).

### 3. Owner hooks (small additions)

On `player_controller.gd` and `enemy.gd`:

- `apply_status_damage(amount: float) -> void` — player routes to
  `inventory.take_damage(amount, Vector2.ZERO)` (FX-free, exactly like lava damage today);
  enemy routes to its own health. DoT must **not** trigger knockback/hit-flash every tick.
- Movement code checks `status.is_movement_blocked()` (Frozen/Stunned) → zero out movement,
  and applies `slow` factor when Chilly is active. Mirrors the existing parry-stun idea.

The component never knows player-vs-enemy specifics: owners only provide
`apply_status_damage()` and read `is_movement_blocked()` / slow factor.

## Status catalog (this cycle)

Six statuses. Stain amounts are abstract units; "active" once stain ≥ `active_threshold`.

| Status   | Category        | Threshold | Decay/s | Active effect                                   |
|----------|-----------------|-----------|---------|-------------------------------------------------|
| On Fire  | harmful         | 1.0       | 1.0     | Burn DoT ~4 dps; orange tint; glow              |
| Wet      | neutral         | 1.0       | 0.5     | Blue-ish tint; suppresses ignition              |
| Oiled    | neutral/harmful | 1.0       | 0.3     | Dark tint; fire catches faster & burns hotter   |
| Chilly   | harmful         | 1.0       | 0.8     | Slows movement ~40%; pale-blue tint             |
| Frozen   | harmful         | 3.0       | 0.4     | `movement_block` (immobile); icy tint; brittle  |
| Bloody   | neutral         | 1.0       | 0.4     | Red tint; lightly suppresses fire               |

Numbers above are starting values and may be tuned during implementation/playtest.

### Sources

- **Terrain (polled):** LAVA/fire → On Fire, WATER → Wet, OIL → Oiled, BLOOD → Bloody.
- **Weapon crits:** flame_sword → On Fire; frost_sword / heavenly_sword → Chilly (ramps to
  Frozen).
- **Emergent:** taking damage and dying enemies already spawn BLOOD terrain → Bloody arises
  naturally from terrain polling.

### Reactions

Evaluated each frame in order; each rule is a few lines in `StatusRegistry`:

1. **Wet extinguishes Fire** — if Wet active, drain On Fire stain fast (Wet evaporates a bit
   quicker while doing so).
2. **Bloody dampens Fire** — like Wet but weaker drain.
3. **Oiled ignites & feeds Fire** — if Oiled present and an ignition source exists (On Fire
   stain, or standing in fire/lava), convert Oiled into extra On Fire stain (hotter,
   faster). Oiled + Wet → Wet wins (no ignition).
4. **Wet + Chilly → Frozen** — if both present, consume them and add to Frozen.
5. **Fire melts cold** — if On Fire active, rapidly drain Chilly and Frozen.
6. **Chilly → Frozen ramp** — sustained Chilly past a higher threshold tips into Frozen.

## Crit system

Crit is one source that applies statuses on hit.

- Two new `weapons.csv` columns: `crit_chance` (0–1) and `crit_multiplier` (default `2.0`),
  overlaid onto weapons in `WeaponRegistry._apply_csv_fields` exactly like cooldown/damage.
- `Weapon` gains `crit_chance`, `crit_multiplier`, and:
  - `get_effective_crit_chance() -> float` — starts from `crit_chance`, then each equipped
    modifier may adjust it via a new optional hook `Modifier.modify_crit_chance(weapon,
    base) -> float` (result clamped 0–1). This satisfies "default per-weapon chance, but
    modifiable by modifiers."
  - `roll_crit() -> bool`.
  - `_on_crit(target, hit_dir)` virtual hook (no-op in base).
- At hit resolution (melee `_hit_attackables_in_arc`, ranged on projectile hit): compute
  crit once; if crit, multiply damage by `crit_multiplier` before `on_hit_impact`, then call
  `_on_crit(target, hit_dir)`.
- Weapons reach the target's status via `target.get_node_or_null("StatusComponent")`.
  Projectiles carry the firing weapon's crit values + an optional on-crit status tag so
  ranged crits work too.

### Weapon wiring (4 this cycle)

| Weapon          | CSV crit             | `_on_crit` behavior                                   |
|-----------------|----------------------|-------------------------------------------------------|
| caliburn        | ~0.35 chance, x2.0   | none — pure crit damage ("high critical chance")      |
| flame_sword     | ~0.15 chance         | add On Fire stain to target (keeps pre-attached lava) |
| frost_sword     | ~0.15 chance         | add Chilly stain (ramps to Frozen)                    |
| heavenly_sword  | ~0.15 chance         | add Chilly/Frozen stain (wide arc already in `.tres`) |

All other CSV weapons get `crit_chance = 0` (no behavior change).

## Visuals / HUD

- **On-entity:** `StatusComponent.changed` drives a sprite `modulate` tint blended from
  active statuses' colors (orange fire, icy frozen, etc.). Reuse existing particle/light FX
  where cheap (On Fire can place a light like lava already does). Crit hits get a punchier
  hit-flash than normal hits.
- **HUD:** a minimal horizontal **status-icon strip** near the player health bar — one small
  icon per active status, fading as stain decays. The full Noita-style labeled panel from
  the reference screenshot is **deferred**; the strip proves the readout and is cheap to
  extend.

## Testing (GUT, matching `tests/unit/`)

- `StatusComponent`: stain add/decay/threshold; burn calls `apply_status_damage`;
  `is_movement_blocked` true when Frozen.
- Reactions: each of the 6 rules in isolation (Wet kills Fire; Bloody dampens Fire;
  Oiled feeds Fire; Wet + Chilly → Frozen; Fire melts Frozen; Chilly ramps to Frozen).
- Crit: `get_effective_crit_chance` with/without a fake +crit modifier; `roll_crit`
  boundaries at chance 0 and 1; damage multiplied on crit.
- CSV: `crit_chance` / `crit_multiplier` parsed and overlaid onto the four weapons.
- Integration: a weapon crit applies the expected stain to a target's `StatusComponent`.

## Out of scope (later sub-projects)

- The remaining ~24 statuses (Toxic, Poisoned, Drunk/boozed tiers, Satiation, Stunned,
  Dazed, Blinded, Twitchy, Wormy Vision, etc.).
- Full Noita-style labeled status panel UI.
- Charge / combo weapons, projectile behaviors, and the 10 unimplemented modifiers
  (sub-projects 2–4).
- willowblade's charge-gated guaranteed crit (depends on the charge system in sub-project 2).
