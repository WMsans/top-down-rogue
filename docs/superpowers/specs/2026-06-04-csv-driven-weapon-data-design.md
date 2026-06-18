# CSV-Driven Weapon & Modifier Data

## Goal

Make the weapon and modifier systems source their **universal** data from
`docs/design_docs/weapons.csv` and `docs/design_docs/modifiers.csv`, so designers
can tune balance and metadata in a spreadsheet instead of editing `.tres`
resources and GDScript classes.

## Data ownership

`weapons.csv` becomes the **catalog** and the source of truth for universal
fields. A new `weapon_texture` column is added.

| CSV column | Applied to | Notes |
|---|---|---|
| `id` | (filename key) | Matches `resources/weapons/<id>.tres` basename |
| `name` | `Weapon.name` | |
| `description` | `Weapon.description` | New field on `Weapon` |
| `type` | validation | `Melee` → `MeleeWeapon`, `Ranged` → `RangedWeapon`; warn on mismatch |
| `rarity` | `Weapon.rarity` | Word → `DropTable.ItemTier` (`Common`=0, `Uncommon`=1, `Rare`=2) |
| `cooldown` | `Weapon.cooldown` | float |
| `damage` | `Weapon.damage` | float |
| `modifier_slots` | `Weapon.modifier_slot_count` | int |
| `weapon_texture` | `weapon_texture` / `icon_texture` | **New column**, `res://` path, `load()`-ed |
| `pre_attached_modifier1..3` | modifier slots | Modifier ids, looked up in the modifier registry |

The `.tres` files keep **only type-specific tuning**:

- Melee: `weapon_reach`, `arc_angle`, and the swing-animation block.
- Ranged: `projectile_speed`, `projectile_lifetime`, `spread_angle`,
  `projectile_count`, `projectile_texture`.

Their `name` / `rarity` / `cooldown` / `damage` lines are **trimmed**, and
`flame_blade.tres`'s pre-attached lava-emitter sub-resource is removed (it moves
to the CSV's `pre_attached_modifier1`).

`modifiers.csv` owns modifier `name`, `description`, and `suppresses_base_use`.
Modifier *behavior* stays in the GDScript classes (e.g. `LavaEmitterModifier`).

## Components

### 1. `src/util/csv_table.gd` (new)

Single-purpose static parser:

```
static func parse(path: String) -> Array[Dictionary]
```

- Built on `FileAccess.get_csv_line()` so quoted fields containing commas (e.g.
  descriptions) parse correctly.
- First row is the header; each subsequent non-empty row becomes a `Dictionary`
  keyed by header name with string values.
- Missing file → `push_warning` and return `[]`.

### 2. `Weapon.description: String` (new field)

Add `@export var description: String = ""` to `src/weapons/weapon.gd`. Surface it
in `get_base_stats()` is **not** required for this work (out of scope).

### 3. `WeaponRegistry` overlay (extend existing autoload)

Loading and tier bucketing already live here, so the CSV overlay belongs here too
rather than in a new autoload.

- Parse `res://docs/design_docs/weapons.csv` and
  `res://docs/design_docs/modifiers.csv` in `_ready` (before tier bucketing).
- **Weapons:** iterate CSV rows as the catalog. For each row:
  1. `load("res://resources/weapons/<id>.tres")`. Missing / not a `Weapon` →
     `push_warning`, skip the row.
  2. `duplicate(true)` the resource (the registry's canonical copy).
  3. Overlay universal fields: `name`, `description`, `cooldown` (float),
     `damage` (float), `modifier_slot_count` (int), `rarity` (word → `ItemTier`),
     and `weapon_texture` via `load(path)` when the column is non-empty.
  4. Validate `type` against the script class; `push_warning` on mismatch but
     continue.
  5. For each non-empty `pre_attached_modifier*`, build the modifier (see below)
     and `add_modifier(slot_index, mod)`.
  6. Store in `_all_weapons` and a new `_weapons_by_id` dictionary.
- **`get_weapon_by_id(id: String) -> Weapon`** (new): returns
  `_weapons_by_id[id].duplicate(true)`, or `null` + `push_warning` if unknown.
- **Modifiers:** parse `modifiers.csv` into `id → {name, description,
  suppresses_base_use}`. `_make_modifier(id) -> Modifier` instantiates
  `modifier_scripts[id].new()` and overlays the CSV `name` / `description` /
  `suppresses_base_use` (`"Yes"`/`"No"` → bool). Unknown id → `push_warning`,
  return `null`. Used by both pre-attached modifiers and `get_random_modifier`.

### 4. Migrate direct `.tres` call sites

`src/core/spawn_dispatcher.gd` and `src/core/cave_spawner.gd` currently `preload`
the `.tres` files as `const`s and assign them directly. After trimming, those
preloads no longer carry the universal fields. Replace the constants with
`WeaponRegistry.get_weapon_by_id("<id>")` calls at point of use so they receive
the CSV-overlaid weapon.

## Rarity mapping

| CSV word | `DropTable.ItemTier` |
|---|---|
| `Common` | `COMMON` (0) |
| `Uncommon` | `UNCOMMON` (1) |
| `Rare` | `RARE` (2) |

Unknown word → `push_warning`, default to `COMMON`.

## Texture column values

Populate the new `weapon_texture` column from current behavior:

- Melee (`rusty_sword`, `bone_dagger`, `broad_axe`, `flame_blade`):
  `res://textures/Weapons/sword_01c.png` (the `MeleeWeapon` script default).
- `throwing_knife`: `.../icons/16x16/bow_01a.png`
- `fire_orb`: `.../icons/16x16/bow_01e.png`
- `spread_shot`: `.../icons/16x16/bow_02a.png`
- `boss_staff`: `.../icons/16x16/bow_03a.png`

(Full paths under `res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/`.)

## Error handling

Each of the following emits a `push_warning` and degrades gracefully rather than
crashing:

- CSV row with no matching `.tres` → skip the row.
- Unknown rarity word → default `COMMON`.
- Unknown modifier id (pre-attached or random) → skip that modifier.
- `type` column not matching the resource's script → keep the resource, warn.
- Missing CSV file → empty catalog, warn.

## Testing

- **`csv_table` parser:** header parsing, a quoted field containing a comma,
  blank trailing cells, missing file → `[]`.
- **Rarity mapping:** each word → expected `ItemTier`; unknown → `COMMON`.
- **Registry weapons:** `rusty_sword` has `damage == 3.0` (CSV) and
  `weapon_reach == 28.0` (tres); `flame_blade` has a `LavaEmitterModifier` in slot
  0; `boss_staff` rarity is `RARE`.
- **Modifier overlay:** `lava_emitter` carries CSV `name` / `description` and
  `suppresses_base_use == false`.
- **Update `tests/unit/test_weapon_resources.gd`:** universal fields now come via
  `WeaponRegistry.get_weapon_by_id(...)` (preloaded `.tres` no longer carry them);
  type-specific fields (`weapon_reach`, `projectile_speed`, `spread_angle`) still
  asserted against the preloaded `.tres`.

## Out of scope / caveats

- **Export builds:** the CSVs live under `res://docs/design_docs/`. Reading them
  works in-editor and in tests, but an exported build needs `*.csv` added to the
  export filter (or the files relocated under `res://resources/`). Path is kept
  as-is per the request; this caveat is noted for whoever ships a build.
- No new weapons or modifiers are added; this is a data-plumbing change only.
- `WeaponRegistry`'s existing `get_random_weapon` / tier-bucket API is unchanged
  apart from now operating on CSV-overlaid resources.
