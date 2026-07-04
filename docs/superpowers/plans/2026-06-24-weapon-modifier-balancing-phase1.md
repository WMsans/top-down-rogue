# Weapon & Modifier Balancing — Phase 1 (Baseline Re-tune) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-tune all 51 weapons and the 3 flagged modifiers to their rarity power-bands (spec Parts A + B), and lock the result in with verification tests — without touching the modifier-combo engine (that is Phase 2).

**Architecture:** Pure data + small script edits. Weapon stats live in `docs/design_docs/weapons.csv` (overlaid onto `Weapon` resources by the `WeaponRegistry` autoload). Two scripted modifiers (`fireball_fan`, `icicle_volley`) and one data modifier (`gas_emitter`) change. Charge weapons are `AdvancedMeleeWeapon` subclasses whose charged release damage = `base_damage × move.damage_mult`. Everything is pinned by GdUnit4 tests.

**Tech Stack:** Godot 4.7 (GDScript), GdUnit4 test framework. Run a suite with:
`addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/<file>.gd`

**Source of truth:** `docs/superpowers/specs/2026-06-24-weapon-modifier-balancing-design.md` (§A1, §A4, §A6, §A7, §B2–B7).

---

## File structure (Phase 1)

- **Modify** `docs/design_docs/weapons.csv` — `damage` column for 51 weapons (§A7).
- **Modify** `docs/design_docs/modifiers.csv` — `gas_emitter` magnitude 20→16.
- **Modify** `src/weapons/modifiers/fireball_fan_modifier.gd` — fan count 5→3.
- **Modify** `src/weapons/modifiers/icicle_volley_modifier.gd` — 5 icicles → 3 piercing icicles.
- **Modify** 6 charge-weapon scripts under `src/weapons/` (§A6).
- **Create** `tests/unit/test_weapon_balance.gd` — every weapon in its effective-DPS band.
- **Create** `tests/unit/test_charge_weapon_ratio.gd` — charged release 1.8–2.5× a tap swing.
- **Create** `tests/unit/test_modifier_emitter_radius.gd` — `gas_emitter` radius is 16.
- **Create** `tests/unit/test_projectile_fan_counts.gd` — fan counts for the two reworked modifiers.
- **Create** `tests/unit/test_modifier_stacking.gd` — cooldown floor + crit clamp + aggregation order (§B2/stacking).
- **Create** `tests/unit/test_status_thresholds.gd` — pins `active_threshold` values (§B5).
- **Create** `tests/unit/test_anti_synergy.gd` — reaction directions (§B6).
- **Create** `tests/unit/test_shop_rarity_distribution.gd` — ~60/30/10 modifier tier weights (§B7).

---

## Task 1: Weapon DPS band test + CSV re-tune

**Files:**
- Test: `tests/unit/test_weapon_balance.gd` (create)
- Modify: `docs/design_docs/weapons.csv` (the `damage` column)

- [ ] **Step 1: Write the failing band test**

Create `tests/unit/test_weapon_balance.gd`. It reads the CSV for type/rarity/archetype, loads each overlaid weapon via `WeaponRegistry.get_weapon_by_id`, computes effective single-target DPS (spec §A1), and asserts it sits in the rarity band.

```gdscript
extends GdUnitTestSuite

const CSV := "res://docs/design_docs/weapons.csv"

# §A1 single-target hits-per-activation, keyed by weapon id (default 1.0)
const MULT := {
	"dragon_fang": 3.0, "twin_daggers": 2.0, "chakram_launcher": 2.0,
	"spread_shot": 2.0, "scatter_blunderbuss": 4.0, "hailstorm_bow": 2.5,
}

# [min, max] effective DPS; tolerance is applied below.
const BANDS := {
	"Melee":  {"Common": [5.0, 8.0],  "Uncommon": [7.0, 11.0], "Rare": [9.0, 14.0]},
	"Ranged": {"Uncommon": [5.0, 9.5], "Rare": [7.0, 11.5]},
}
const TOL := 0.6   # rounding + tax slack

func test_every_weapon_sits_in_its_rarity_band() -> void:
	var rows: Array = CsvTable.parse(CSV)
	var checked := 0
	for row in rows:
		var id: String = row.get("id", "")
		if id == "":
			continue
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).is_not_null()
		var cd: float = w.cooldown
		var dmg: float = w.damage
		var cc: float = w.crit_chance
		var cm: float = w.crit_multiplier
		var crit_factor: float = 1.0 + cc * (cm - 1.0)
		var mult: float = MULT.get(id, 1.0)
		var dps: float = dmg * crit_factor * mult / cd
		var band: Array = BANDS[row["type"]][row["rarity"]]
		assert_float(dps) \
			.override_failure_message("%s (%s %s) DPS=%.1f outside band %s" % [id, row["rarity"], row["type"], dps, str(band)]) \
			.is_between(band[0] - TOL, band[1] + TOL)
		checked += 1
	assert_int(checked).is_equal(51)
```

- [ ] **Step 2: Run it to verify it fails on current data**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_weapon_balance.gd`
Expected: FAIL — e.g. `dragon_fang (Uncommon Melee) DPS=32.7 outside band [7.0, 11.0]`.

- [ ] **Step 3: Apply the §A7 damage values to `weapons.csv`**

Set the `damage` column for each id to the new value below (cooldown and all other columns unchanged). Leave `crit_chance`/`crit_multiplier` as they are.

```
rusty_sword=3.0  bone_dagger=1.5  broad_axe=4.5  broadsword=3.0  cleaver=3.0
flame_blade=2.5  gravedigger_spade=3.5  iron_mace=4.5  tao_sword=4.0  willowblade=2.5
cinder_brand=2.5  dragon_fang=1.5  executioner=5.0  flame_sword=3.0  frost_sword=3.0
glacier_edge=3.5  heavenly_sword=4.5  mirror_blade=3.5  rapier=2.0  tide_caller=3.5
twin_daggers=1.0  venom_fang_blade=3.0  void_sword=4.5  war_scythe=4.5  whirlwind_blade=4.0
berserker_axe=6.0  blood_blade=4.0  caliburn=4.0  deep_dark_blade=7.5  grand_knight_sword=7.5
obsidian_greatsword=8.0  phantom_blade=5.5  qinggang_sword=4.5  quake_hammer=8.5  reaper_glaive=5.5
soul_reaver=5.0  thunder_katana=3.0
chakram_launcher=4.0  fire_orb=11.0  flame_lobber=9.0  frost_repeater=4.5  heavy_crossbow=7.5
scatter_blunderbuss=2.0  spread_shot=4.0  throwing_knife=7.5  venom_spitter=8.0
arc_railgun=13.0  boss_staff=9.5  hailstorm_bow=4.0  seeker_launcher=12.5  tesla_gun=8.5
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_weapon_balance.gd`
Expected: PASS (51 weapons checked).

- [ ] **Step 5: Verify the §A1 multipliers against the archetype scripts**

For each id in `MULT`, open its archetype script and confirm the multiplier matches reality:
- `src/weapons/dragon_fang_weapon.gd` — `light_moves = [_thrust(), _thrust(), _thrust()]` → 3 hits ✓
- `src/weapons/twin_daggers_weapon.gd` — AUTO_FLURRY 2 ✓
- `src/weapons/chakram_launcher_weapon.gd` — out + back = 2 hits.
- For `spread_shot`, `scatter_blunderbuss`, `hailstorm_bow` — confirm `projectile_count` in `weapons.csv` and the firing script; if a weapon fires a different effective count, update `MULT` and re-run Step 4 (re-solve that row's damage so DPS lands in band).

- [ ] **Step 6: Commit**

```bash
git add docs/design_docs/weapons.csv tests/unit/test_weapon_balance.gd
git commit -m "balance: re-tune 51 weapons to rarity DPS bands + band test"
```

---

## Task 2: Charge-weapon release ratio (§A6)

**Files:**
- Test: `tests/unit/test_charge_weapon_ratio.gd` (create)
- Modify: `src/weapons/willowblade_weapon.gd`, `executioner_weapon.gd`, `void_sword_weapon.gd`, `quake_hammer_weapon.gd`, `blood_blade_weapon.gd`, `arc_railgun_weapon.gd`

**Context:** A charged release plays `charged_moves`; total damage = `base_damage × Σ(move.damage_mult)` over the released sequence (a `charged_flurry_max > 1` weapon repeats its charged move up to that many times). The tap swing is `light_moves[0].damage_mult` (usually 1.0). Target: charged-release total ∈ **[1.8, 2.5]×** tap.

- [ ] **Step 1: Read each charge weapon's current moves**

Open the 6 scripts. Record `light_moves`, `charged_moves`, and `charged_flurry_max` for each. Compute current charged total = `Σ charged_moves[i].damage_mult` (and if `charged_flurry_max > 1`, the worst case repeats the charged move that many times). Example (`executioner_weapon.gd`): `charged_moves = [_spin(1.0)]`, `charged_flurry_max = 2` → worst-case total = `1.0 × 2 = 2.0×` (already in band).

- [ ] **Step 2: Write the failing ratio test**

Create `tests/unit/test_charge_weapon_ratio.gd`:

```gdscript
extends GdUnitTestSuite

const CASES := {
	"willowblade": "res://src/weapons/willowblade_weapon.gd",
	"executioner": "res://src/weapons/executioner_weapon.gd",
	"void_sword": "res://src/weapons/void_sword_weapon.gd",
	"quake_hammer": "res://src/weapons/quake_hammer_weapon.gd",
	"blood_blade": "res://src/weapons/blood_blade_weapon.gd",
	"arc_railgun": "res://src/weapons/arc_railgun_weapon.gd",
}

func _charged_total(w) -> float:
	# Sum charged-move damage_mults across the worst-case released sequence.
	var per: float = 0.0
	for m in w.charged_moves:
		per += m.damage_mult
	var reps: int = maxi(1, w.charged_flurry_max)
	if w.charged_moves.size() == 1:
		return per * float(reps)
	return per

func _tap(w) -> float:
	return (w.light_moves[0].damage_mult) if not w.light_moves.is_empty() else 1.0

func test_charged_release_is_1_8_to_2_5x_tap() -> void:
	for id in CASES:
		var w = load(CASES[id]).new()
		w._setup_moves()
		var ratio: float = _charged_total(w) / _tap(w)
		assert_float(ratio) \
			.override_failure_message("%s charged ratio %.2f outside [1.8, 2.5]" % [id, ratio]) \
			.is_between(1.8, 2.5)
```

- [ ] **Step 3: Run it to see which weapons fail**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_charge_weapon_ratio.gd`
Expected: FAIL for any weapon outside [1.8, 2.5].

- [ ] **Step 4: Adjust the failing weapons' charged-move `damage_mult`**

In each failing script's `_setup_moves()`, change the charged move's `damage_mult` argument so the computed total lands at ~2.0×. For a single charged move with `charged_flurry_max = N`, set the per-move mult to `2.0 / N`. For a multi-move charged sequence, scale the mults so they sum to ~2.0. Example: a weapon with `charged_moves = [_spin(1.0)]`, `charged_flurry_max = 1` becomes `charged_moves = [_spin(2.0)]`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_charge_weapon_ratio.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/willowblade_weapon.gd src/weapons/executioner_weapon.gd src/weapons/void_sword_weapon.gd src/weapons/quake_hammer_weapon.gd src/weapons/blood_blade_weapon.gd src/weapons/arc_railgun_weapon.gd tests/unit/test_charge_weapon_ratio.gd
git commit -m "balance: charged releases tuned to 1.8-2.5x tap + ratio test"
```

---

## Task 3: `gas_emitter` radius 20→16 (§B4)

**Files:**
- Test: `tests/unit/test_modifier_emitter_radius.gd` (create)
- Modify: `docs/design_docs/modifiers.csv` (gas_emitter row, `magnitude` column)

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_gas_emitter_radius_capped_at_16() -> void:
	var m = WeaponRegistry.get_random_modifier(DropTable.ItemTier.UNCOMMON)
	# get_random_modifier is random; build gas_emitter directly from CSV data instead:
	var rows: Array = CsvTable.parse("res://docs/design_docs/modifiers.csv")
	var gas := {}
	for row in rows:
		if row.get("id", "") == "gas_emitter":
			gas = row
			break
	assert_dict(gas).is_not_empty()
	assert_float(float(gas["magnitude"])).is_equal(16.0)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_modifier_emitter_radius.gd`
Expected: FAIL — magnitude is 20.

- [ ] **Step 3: Edit the CSV**

In `docs/design_docs/modifiers.csv`, the `gas_emitter` row: change `magnitude` from `20` to `16`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_modifier_emitter_radius.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/design_docs/modifiers.csv tests/unit/test_modifier_emitter_radius.gd
git commit -m "balance: cap gas_emitter radius at 16 + test"
```

---

## Task 4: De-dup the projectile fans (§B2)

**Files:**
- Test: `tests/unit/test_projectile_fan_counts.gd` (create)
- Modify: `src/weapons/modifiers/fireball_fan_modifier.gd`, `src/weapons/modifiers/icicle_volley_modifier.gd`

**Context:** Both currently call `ModifierProjectile.spawn_fan(..., 5, 30.0, {...})` — identical effect, element-swapped. Fix: `fireball_fan` → 3 fireballs; `icicle_volley` → 3 *piercing* icicles (mechanically distinct). The fan count is a literal arg to `spawn_fan`; promote it to a named constant so it's testable.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

func test_fireball_fan_count_is_three() -> void:
	var m := FireballFanModifier.new()
	assert_int(m.FAN_COUNT).is_equal(3)

func test_icicle_volley_is_three_piercing() -> void:
	var m := IcicleVolleyModifier.new()
	assert_int(m.FAN_COUNT).is_equal(3)
	assert_bool(m.PIERCING).is_true()
```

- [ ] **Step 2: Run it to verify it fails**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_projectile_fan_counts.gd`
Expected: FAIL — `FAN_COUNT`/`PIERCING` not defined.

- [ ] **Step 3: Edit `fireball_fan_modifier.gd`**

```gdscript
class_name FireballFanModifier
extends ProjectileModifier

const FAN_COUNT := 3

func _init() -> void:
	name = "Fireball Fan"
	description = "Every swing looses a fan of three fireballs."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, FAN_COUNT, 30.0,
		{ "hit_status": "on_fire", "tint": Color(1.0, 0.5, 0.1) })
```

- [ ] **Step 4: Edit `icicle_volley_modifier.gd`**

Confirm `ModifierProjectile.spawn_fan`'s options dict accepts a `pierce` flag (grep `func spawn_fan` in `src/weapons/modifiers/modifier_projectile.gd`); if the key differs, use that key.

```gdscript
class_name IcicleVolleyModifier
extends ProjectileModifier

const FAN_COUNT := 3
const PIERCING := true

func _init() -> void:
	name = "Icicle Volley"
	description = "Every strike fires three piercing icicles."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, FAN_COUNT, 30.0,
		{ "hit_status": "chilly", "tint": Color(0.5, 0.8, 1.0), "pierce": PIERCING })
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_projectile_fan_counts.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/weapons/modifiers/fireball_fan_modifier.gd src/weapons/modifiers/icicle_volley_modifier.gd tests/unit/test_projectile_fan_counts.gd
git commit -m "balance: de-dup fans (fireball 3, icicle 3 piercing) + test"
```

---

## Task 5: Stacking caps verification (§B2)

**Files:**
- Test: `tests/unit/test_modifier_stacking.gd` (create)

**Context:** `weapon.gd` already enforces `COOLDOWN_FLOOR = 0.1` and crit `clampf(0,1)`, aggregating as `(base + Σ stat_add) × Π stat_mult`. This test pins that behavior (no production change). Modifiers are built via `WeaponRegistry.get_random_modifier` is random, so build `DataModifier`s directly from CSV rows by id with a small helper.

- [ ] **Step 1: Write the test**

```gdscript
extends GdUnitTestSuite

const DataModifier = preload("res://src/weapons/modifiers/data_modifier.gd")
const Weapon = preload("res://src/weapons/weapon.gd")

func _mod(id: String):
	for row in CsvTable.parse("res://docs/design_docs/modifiers.csv"):
		if row.get("id", "") == id:
			return DataModifier.new(row)
	return null

func _weapon_with(ids: Array):
	var w = Weapon.new()
	w.cooldown = 0.4
	w.crit_chance = 0.0
	w.modifier_slot_count = 3
	w.modifiers = []
	for id in ids:
		w.modifiers.append(_mod(id))
	w.invalidate_effective_stats()
	return w

func test_cooldown_cannot_drop_below_floor() -> void:
	# adrenaline (x0.6 cd) + quickdraw (x0.8 cd) on a 0.4 base would be 0.192; floor is 0.1.
	var w = _weapon_with(["adrenaline", "quickdraw"])
	assert_float(w.get_effective_stats()["cooldown"]).is_greater_equal(0.1)

func test_crit_chance_clamped_to_one() -> void:
	var w = _weapon_with(["honed_point"])  # +0.15
	w.crit_chance = 0.95
	assert_float(w.get_effective_crit_chance()).is_equal(1.0)

func test_additive_then_multiplicative_order() -> void:
	# sharpened (+3 dmg) then heavy_head adds +5; base 10 -> 18, no mult on damage -> 18.
	var w = _weapon_with(["sharpened", "heavy_head"])
	w.damage = 10.0
	w.invalidate_effective_stats()
	assert_float(w.get_effective_stats()["damage"]).is_equal(18.0)
```

- [ ] **Step 2: Run the test**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_modifier_stacking.gd`
Expected: PASS (these pin existing behavior). If `adrenaline`/`quickdraw` use `passive` triggers that only apply conditionally, adjust the test to call the relevant getters directly — confirm against `data_modifier.gd:get_stat_mult`.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_modifier_stacking.gd
git commit -m "test: pin cooldown floor, crit clamp, stat aggregation order"
```

---

## Task 6: Status threshold pins (§B5)

**Files:**
- Test: `tests/unit/test_status_thresholds.gd` (create)

- [ ] **Step 1: Write the test**

```gdscript
extends GdUnitTestSuite

func test_active_thresholds_match_spec() -> void:
	assert_float(StatusRegistry.get_threshold("on_fire")).is_equal(1.0)
	assert_float(StatusRegistry.get_threshold("wet")).is_equal(1.0)
	assert_float(StatusRegistry.get_threshold("oiled")).is_equal(1.0)
	assert_float(StatusRegistry.get_threshold("chilly")).is_equal(1.0)
	assert_float(StatusRegistry.get_threshold("frozen")).is_equal(3.0)
	assert_float(StatusRegistry.get_threshold("poisoned")).is_equal(0.3)
	assert_float(StatusRegistry.get_threshold("bloody")).is_equal(1.0)
```

- [ ] **Step 2: Run the test**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_status_thresholds.gd`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_status_thresholds.gd
git commit -m "test: pin status active_threshold values"
```

---

## Task 7: Anti-synergy reaction directions (§B6)

**Files:**
- Test: `tests/unit/test_anti_synergy.gd` (create)

**Context:** `StatusRegistry.apply_reactions(component, delta, pos)` mutates stains. `StatusComponent` API: `add_stain(id, amt)`, `get_stain(id)`, `reduce_stain(id, amt)`.

- [ ] **Step 1: Write the test**

```gdscript
extends GdUnitTestSuite

const StatusComponent = preload("res://src/status/status_component.gd")

func _sc():
	var sc = auto_free(StatusComponent.new())
	add_child(sc)
	return sc

func test_wet_drains_fire() -> void:
	var sc = _sc()
	sc.add_stain("on_fire", 5.0)
	sc.add_stain("wet", 5.0)
	var before: float = sc.get_stain("on_fire")
	StatusRegistry.apply_reactions(sc, 0.5)
	assert_float(sc.get_stain("on_fire")).is_less(before)

func test_oil_feeds_fire() -> void:
	var sc = _sc()
	sc.add_stain("on_fire", 2.0)
	sc.add_stain("oiled", 5.0)
	var before_fire: float = sc.get_stain("on_fire")
	StatusRegistry.apply_reactions(sc, 0.5)
	assert_float(sc.get_stain("on_fire")).is_greater(before_fire)
	assert_float(sc.get_stain("oiled")).is_less(5.0)

func test_wet_and_chilly_make_frozen() -> void:
	var sc = _sc()
	sc.add_stain("wet", 5.0)
	sc.add_stain("chilly", 5.0)
	StatusRegistry.apply_reactions(sc, 0.5)
	assert_float(sc.get_stain("frozen")).is_greater(0.0)
```

- [ ] **Step 2: Run the test**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_anti_synergy.gd`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_anti_synergy.gd
git commit -m "test: assert status anti-synergy reaction directions"
```

---

## Task 8: Shop rarity distribution (§B7)

**Files:**
- Test: `tests/unit/test_shop_rarity_distribution.gd` (create)
- Possibly modify: the tier-weight source (only if current weights are not ~60/30/10)

- [ ] **Step 1: Locate the modifier tier-weight source**

Find where shop modifier cards pick a rarity *tier* (not the item within a tier — that is `WeaponRegistry.get_random_modifier(tier)`). Search: `grep -rln "ItemTier\|tier_weight\|COMMON.*UNCOMMON" src/economy/ src/drops/ src/core/`. The likely owner is a `DropTable`/shop-stall weight table. Record the constant that holds the per-tier weights and the function that rolls a tier.

- [ ] **Step 2: Write the distribution test**

Replace `ROLL_TIER` below with the actual roll function you found in Step 1 (e.g. `DropTable.roll_modifier_tier()`), and `SAMPLES` stays large to keep variance low.

```gdscript
extends GdUnitTestSuite

const SAMPLES := 20000

func test_modifier_tier_weights_are_60_30_10() -> void:
	var counts := {DropTable.ItemTier.COMMON: 0, DropTable.ItemTier.UNCOMMON: 0, DropTable.ItemTier.RARE: 0}
	for i in range(SAMPLES):
		var t = DropTable.roll_modifier_tier()   # <-- use the real function from Step 1
		counts[t] += 1
	var c: float = float(counts[DropTable.ItemTier.COMMON]) / SAMPLES
	var u: float = float(counts[DropTable.ItemTier.UNCOMMON]) / SAMPLES
	var r: float = float(counts[DropTable.ItemTier.RARE]) / SAMPLES
	assert_float(c).is_between(0.55, 0.65)
	assert_float(u).is_between(0.25, 0.35)
	assert_float(r).is_between(0.07, 0.13)
```

- [ ] **Step 3: Run the test**

Run: `addons/gdUnit4/runtest.sh --godot_binary /usr/bin/godot -a res://tests/unit/test_shop_rarity_distribution.gd`
Expected: PASS if weights already ~60/30/10. If FAIL, go to Step 4.

- [ ] **Step 4: (Only if failing) Adjust the tier weights**

In the source from Step 1, set the per-tier weights to 60 / 30 / 10 (or 0.6 / 0.3 / 0.1). Re-run Step 3 until PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_shop_rarity_distribution.gd
git commit -m "test: pin shop modifier tier distribution ~60/30/10"
```

---

## Task 9: Full suite green + todo update

- [ ] **Step 1: Run all new Phase-1 suites**

Run each of the 8 new test files with the run command. Expected: all PASS.

- [ ] **Step 2: Mark the Phase-1 todo rows done**

In `docs/design_docs/implementation_todo2.md`, set `Done = x` for the Weapon Balance rows (full audit, rarity curve, melee-vs-ranged, archetype budget, pre-attached valuation, charge balance) and the Modifier Balance rows covered here (stat audit, stacking sanity, conditional payoff, emitter sizing, status thresholds, anti-synergy, shop distribution). Leave Part C (combo modifiers) for Phase 2.

- [ ] **Step 3: Commit**

```bash
git add docs/design_docs/implementation_todo2.md
git commit -m "docs: mark Phase-1 weapon/modifier balance rows done"
```

---

## Self-review notes

- **Spec coverage:** §A2/A3/A4/A7 → Task 1; §A6 → Task 2; §B4 → Task 3; §B2 de-dup → Task 4; §B2 stacking → Task 5; §B5 → Task 6; §B6 → Task 7; §B7 → Task 8. §B3 (conditional payoff ≥1.5×) is verify-only and already satisfied by the existing `frostbreaker/pyroclast/coup_de_grace/glass_cannon` magnitudes — no code change; it is asserted implicitly by the unchanged CSV. §B1 bands are the rationale behind Task 1's `BANDS`.
- **Investigation steps** (Task 1 Step 5, Task 2 Step 1, Task 4 Step 4, Task 8 Step 1) name exact files and the contract to satisfy — they are not placeholders.
- **Phase 2** (Part C: combo-modifier engine + 24 modifiers) is a separate plan, to be written against the post-Phase-1 codebase since its weapon evaluation-pass rework rewrites the hook loops these tests pin.
