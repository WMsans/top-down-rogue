# Charge + Combos — Design

**Sub-project 2 of Phase 7 (Weapon & Modifier Content Expansion).**

Implements the *behavior* behind nine melee weapons whose CSV descriptions promise
hold-to-charge attacks and multi-step combo sequences. CSV stat data and `.tres` files
already exist; this pass builds the combat systems they need.

Weapons in scope: `willowblade`, `blood_blade`, `executioner`, `void_sword`,
`dragon_fang`, `grand_knight_sword`, `deep_dark_blade`, `phantom_blade`, `qinggang_sword`.

Builds on Sub-project 1 (crit + status), which already landed: `Weapon.roll_crit()`,
`Weapon._on_crit()`, and `StatusComponent.add_stain()`.

---

## Goals

- A **charge** input: hold a weapon's slot key to build charge, release to fire. A quick
  tap fires the weapon's light attack; a held release fires its charged attack.
- A **combo** sequencer: a weapon's attack is an ordered list of *moves* run either as a
  player-driven **tap-chain** or an automatic **flurry**.
- Three hand-built **move shapes** — slash, thrust, spin — each a bespoke animation in the
  spirit of the existing `MeleeWeapon._process_swing` phase machine.
- All nine weapons playable, wired through pure-script per-weapon subclasses.

## Non-goals

- No change to the ten already-functional stat-only weapons (they stay on
  `melee_weapon.gd`).
- No mouse aiming (aiming remains auto-target / movement-based).
- No new ranged/projectile behavior (that is Sub-project 3).
- Animation *feel* is tuned manually, not unit-tested.

---

## Architecture overview

```
weapon_manager (_input: press + release per slot)
        │  on_press / on_release
        ▼
Weapon  (base API: on_press, on_release, get_charge_ratio — defaults preserve today)
        ▲
MeleeWeapon  (existing single-arc swing; pose/trail/easing/hit helpers — unchanged behavior)
        ▲
AdvancedMeleeWeapon  (NEW: charge controller + combo sequencer + move runner + 3 move shapes)
        ▲
per-weapon subclasses (NEW, pure script: build their move lists in _init)
  WillowbladeWeapon, BloodBladeWeapon, ExecutionerWeapon, VoidSwordWeapon,
  DragonFangWeapon, GrandKnightWeapon, DeepDarkWeapon, PhantomBladeWeapon, QinggangWeapon
```

Chosen approach: **one `AdvancedMeleeWeapon` base plus small per-weapon subclasses.**
The weapons genuinely mix charge and multi-shape moves (willowblade and executioner are
tap-light + charged-heavy), so charge, combo, and moves are one cohesive feature rather
than separable components. Only `void_sword` carries behavior special enough to override a
hook; the rest differ only in the move lists they build in code.

---

## Section 1 — Input & charge plumbing

`weapon_manager._input` currently fires on keydown only (Z/X/C → slots 0/1/2). It is
extended to forward both press and release to the slot's weapon, via a small charge-aware
API added to `Weapon`:

```gdscript
# Weapon (base) — defaults preserve current instant-fire behavior
func on_press(user: Node) -> void:
    use(user)              # unchanged: self-gates on is_ready()
func on_release(user: Node) -> void:
    pass
func get_charge_ratio() -> float:
    return 0.0             # for the visual charge tell
```

`weapon_manager` behavior:
- **keydown** for a slot with a non-null weapon → `_activate_weapon(weapon)` (visual /
  `weapon_activated` as today) then `weapon.on_press(_player)`.
- **keyup** for that slot → `weapon.on_release(_player)`.
- Track the pressed slot so the matching keyup is routed to the same weapon even if the
  player switches slots mid-hold (release is delivered to the weapon that was pressed).

Charge accrual needs **no new per-frame plumbing**: `Weapon.tick(delta)` already runs every
physics frame for every inventory weapon. `AdvancedMeleeWeapon` accrues charge inside `tick`
gated by a `_charging` flag set in `on_press`.

The existing ten weapons and the tap-chain combo weapons never override `on_release`, so
their behavior is byte-for-byte unchanged: press → `use()` → immediate swing.

---

## Section 2 — `AdvancedMeleeWeapon` core

`class_name AdvancedMeleeWeapon extends MeleeWeapon`. Inherits `_apply_pose`,
`_spawn_trail`, the easing helpers, `_blade_to_sprite_rot`, and the arc-hit query. The base
`MeleeWeapon._process_swing` is *not* used by the subclass; the subclass runs its own
move-driven update loop (Section 3) while reusing the inherited helpers.

### Charge controller

```gdscript
@export var charge_time_full: float = 0.6   # seconds of hold to reach ratio 1.0
@export var tap_threshold: float    = 0.12  # hold under this on release => light attack
var _charging: bool = false
var _charge_time: float = 0.0
```

- `on_press`: a weapon is chargeable when `charged_moves` is non-empty. If `is_ready()`
  and chargeable → `_charging = true`, `_charge_time = 0`. If not chargeable, fall through
  to base `on_press` → `use()` (the tap-chain / single-move path).
- `tick`: while `_charging`, `_charge_time += delta` (clamped at `charge_time_full`).
- `get_charge_ratio()`: `clampf(_charge_time / charge_time_full, 0, 1)`.
- `on_release`: if `_charging`:
  - hold `< tap_threshold` → run the **light** attack;
  - else → run the **charged** attack, passing `get_charge_ratio()`;
  - then `_charging = false`, start cooldown.

The charge ratio is exposed for a visual tell driven from `update_visual` (e.g. a pulsing
blade tint / scale on the active weapon). Tap responsiveness: the light attack fires on
release, whose latency is just the key-up — negligible for a tap.

### Combo sequencer

A weapon's light attack (and a charged attack) is an ordered `Array[Move]` run in one of
two modes:

```gdscript
enum ComboMode { TAP_CHAIN, AUTO_FLURRY }
@export var combo_mode: int = ComboMode.TAP_CHAIN
@export var combo_reset_time: float = 0.5   # tap-chain idle window before reset
var light_moves: Array = []                 # built by subclass in _init/_setup_moves
var charged_moves: Array = []               # optional; empty => no charged attack
var _combo_index: int = 0
var _combo_reset_timer: float = 0.0
var _flurry_queue: Array = []               # remaining moves of an in-progress flurry
var _flurry_timer: float = 0.0
```

- **TAP_CHAIN** — each `on_press`/`use()` plays `light_moves[_combo_index]`, advances the
  index, and sets `_combo_reset_timer = combo_reset_time`. `tick` counts the timer down;
  on expiry, or after the last step, `_combo_index` resets to 0. Per-step cooldown is the
  weapon `cooldown`; combo continuity is governed by the reset window, not cooldown.
- **AUTO_FLURRY** — one trigger loads the whole sequence into `_flurry_queue`; `tick`
  pops and plays the next move when the current move's duration elapses, locking further
  input until the queue drains. Cooldown spans the whole flurry.

**Unification:** a *charged* attack can launch an auto-flurry whose length scales with
charge ratio. That is the entire mechanism behind executioner ("up to two spins") and
blood_blade ("burst of lunging swings") — no special code, just
`charged_moves` repeated `count(ratio)` times into the flurry queue.

So every weapon decomposes into: a **light** attack (single move or tap-chain) and an
optional **charged** attack (single move or charge-scaled flurry).

### Per-weapon hook

```gdscript
func _setup_moves() -> void: pass     # subclass builds light_moves / charged_moves
func _on_charge_tick(user, delta, ratio) -> void: pass   # e.g. void pull
```

`_setup_moves()` is called from `_init` so `duplicate(true)` reconstructs the move lists
(it re-runs `_init`, then copies exported stats over). This sidesteps the
`@export`-vs-`duplicate()` hazard: move lists are plain vars rebuilt deterministically, not
CSV-overlaid values that would revert.

---

## Section 3 — Bespoke move library (pure script)

A move is a lightweight inner struct — **not** a `Resource`, no `.tres`:

```gdscript
class Move extends RefCounted:
    var shape: int                 # SLASH | THRUST | SPIN
    var reach: float
    var arc: float
    var damage_mult: float = 1.0
    var dash_distance: float = 0.0 # forward lunge applied to the player
    var force_crit: bool = false   # guaranteed crit this move
    var ignore_parry: bool = false # ghost through guard
    var swing_dir: float = 0.0     # 0 = alternate; ±1 = forced up/down (qinggang)
```

Constructed in code via factory helpers on the base class, mirroring how tuning lives in
`@export` vars today:

```gdscript
func _slash(reach, arc, dmg := 1.0, dir := 0.0) -> Move
func _thrust(reach, dash := 0.0, force_crit := false, ignore_parry := false) -> Move
func _spin(reach, dmg := 1.0) -> Move
```

Global tuning stays in `@export` vars on `AdvancedMeleeWeapon` (prep/action/return
durations per shape, scale curves), exactly like the current swing.

Each shape is a **hand-built phase animation** like `_process_swing`, sharing the inherited
pose/trail application:

- **`_animate_slash`** — the existing arc swing, alternating direction (or forced by
  `swing_dir`). Hitbox: arc query via the generalized
  `_hit_attackables(user, origin, dir, reach, arc, dmg_mult, force_crit, ignore_parry)`.
- **`_animate_thrust`** — blade snaps to point along facing; pommel drives forward
  (`pos += facing * reach`) with a fast-out / snap-back easing; narrow stab. Hitbox: a
  short **forward capsule** along facing (new query helper). Applies `dash_distance`.
- **`_animate_spin`** — blade sweeps a full 360° around the player with a body lean; hitbox
  is the full circle (`arc = TAU`) sampled across the spin's action window so each enemy is
  hit once.

Cross-cutting move effects:
- `force_crit` → the hit path skips `roll_crit()` and treats the hit as a crit (and fires
  `_on_crit`).
- `ignore_parry` → the hit path skips the `try_parry` branch.
- `dash_distance` → during the move's action phase, the player is pushed along facing. The
  player exposes a small `request_dash(dir, speed, time)` that sets a decaying dash
  velocity in its movement integration (so terrain collision is respected via the existing
  `CharacterBody2D` motion). If a player hook is impractical, fall back to bounded
  `move_and_collide` from the weapon.

The arc-hit method is generalized from the current `_hit_attackables_in_arc` (which reads
the weapon's `arc_angle`/`weapon_reach` members) to accept per-move `reach`/`arc`/mult and
the `force_crit`/`ignore_parry` flags. `MeleeWeapon`'s own call site passes its members, so
its behavior is unchanged.

---

## Section 4 — Per-weapon mapping

Only `void_sword` needs more than a move list; every other special trait is a move flag.

| Weapon | Light attack | Charged attack | Mode / special |
|---|---|---|---|
| `willowblade` | quick slash | thrust, `force_crit` | charge; data-only |
| `executioner` | slash (chop) | spin flurry, `count = 1 + round(ratio)` (max 2) | charge → flurry |
| `blood_blade` | quick slash | slash flurry, each `dash_distance > 0` | charge → flurry |
| `void_sword` | — | wide slash | charge; **subclass** `_on_charge_tick` pulls nearby enemies inward |
| `dragon_fang` | thrust → thrust → thrust | — | `AUTO_FLURRY` |
| `grand_knight_sword` | slash → slash → thrust | — | `TAP_CHAIN` |
| `deep_dark_blade` | spin → thrust | — | `TAP_CHAIN` |
| `phantom_blade` | up-slash → thrust, `ignore_parry` | — | `TAP_CHAIN` |
| `qinggang_sword` | slash↑ → slash↓ (forced `swing_dir`) | — | `TAP_CHAIN` |

`VoidSwordWeapon._on_charge_tick` applies an inward velocity/translation to enemies within
a radius each charge frame (a physics-shape query for `attackable` bodies, like the
existing hit query). Strength may scale with `ratio`.

---

## Section 5 — Data wiring

Behavior lives in **pure-script subclasses**, not data. Each weapon's `.tres` is re-pointed
from `melee_weapon.gd` to its subclass script; the subclass builds its move list in
`_init` → `_setup_moves`. CSV continues to overlay stats (name/damage/cooldown/crit) and is
**not extended** with combo/charge columns.

```gdscript
class_name GrandKnightWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
    combo_mode = ComboMode.TAP_CHAIN
    light_moves = [_slash(44, 2.0), _slash(44, 2.0), _thrust(40)]
```

`WeaponRegistry`:
- Loads each `.tres` by id and overlays CSV — works unchanged (`AdvancedMeleeWeapon` is a
  `Melee`-type `Weapon`, so `_validate_type` passes).
- New scripts are registered in `weapon_scripts` for completeness.
- Base stat exports the `.tres` already carries (e.g. `weapon_reach`, `arc_angle`) remain
  valid as global defaults; per-move geometry overrides them in code.

**Manual-test path:** add an equip-by-id console command (building on the existing console /
cheat command system) so each weapon can be feel-tested in-editor without relying on drops.

---

## Section 6 — Testing

Headless GUT unit tests under `tests/unit` (extending the existing suite):

- **Charge controller** — hold `< tap_threshold` selects the light attack; `>=` selects the
  charged attack; `get_charge_ratio` clamps 0→1; executioner flurry `count` scales with
  ratio.
- **Combo sequencer** — tap-chain advances the index, resets after `combo_reset_time`, and
  wraps after the last step; auto-flurry emits N moves and locks input until drained;
  cooldown spans the flurry.
- **Move hit detection** (physics queries, like `test_ranged_weapon`) — thrust hits a
  forward target and misses a flank target; slash hits within its arc; spin hits all-around;
  `force_crit` bypasses the roll and fires `_on_crit`; `ignore_parry` skips the parry
  branch; `dash_distance` moves the player.
- **Data load** — each of the nine weapons loads as its expected class with the expected
  move count and combo mode (extend `test_csv_weapon_data` / `test_weapon_resources`).

Animation feel (bespoke) is verified manually in-editor.

---

## Risks & mitigations

- **Move runner vs. inherited swing machine** — `AdvancedMeleeWeapon` runs its own update
  loop instead of `MeleeWeapon._process_swing`. Mitigation: reuse the inherited *helpers*
  (pose/trail/easing/hit), not the orchestration; keep `MeleeWeapon` untouched so the ten
  simple weapons are unaffected.
- **`duplicate(true)` dropping move lists** — mitigated by building them in `_init` so they
  reconstruct on every instance (see [[weapon-csv-fields-must-be-export]]).
- **Player dash hook** — if `request_dash` proves awkward, fall back to weapon-side bounded
  `move_and_collide`; either way the lunge respects terrain.
- **Input routing on mid-hold slot switch** — release is delivered to the weapon that was
  pressed, tracked by the pressed slot.

## Out of scope / future

Charge & combo *modifiers* (`arc_volley`, `triangular_volley`, `splitting_rounds`,
`bouncing_bullets`, `penetrating_shockwave`, `lightning_bolt`) are Sub-project 4 and build
on the combo-step and charge hooks established here.
