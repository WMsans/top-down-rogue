# Cave forest cleanup — design

## Intent

The cave forest (2026-10-23) reads as messy, and trees / big rocks have no
collision for the player. Make it calmer and physically solid.

## Goals

1. Fewer prop variants, one palette (Colour1), round trees + pines only.
2. Trees fade when the player or an enemy is behind them.
3. Fewer trees and rocks per chunk.
4. Trees and big rocks block the player (and keep blocking enemies).
5. Kept prop textures use DawnBringer 32 colours only.

Non-goals: changing flora/edge-rock decor, the planner's group logic, other
pack palettes. Anti-goal: the player starts colliding with enemies.

## Approaches (recolour)

- **A. Hand-checked colour table, overwrite PNGs — picked.** 11 source
  colours, each mapped by hand so ramps stay distinct; zero runtime cost.
- B. Automatic nearest DB32 colour: merges the two bright leaf greens and
  turns leaf shadow olive-brown.
- C. Runtime palette shader: per-prop shader cost, overkill for 11 colours.

## Decisions

### Kept props (`assets/biomes/caves.tres`)

All under `textures/Assets/NaturalDecorsTreesAndRocksv1/`:

| Role | Texture |
|------|---------|
| round tree | `Trees/Colour1/160x160Trees_3.png` |
| round tree | `Trees/Colour1/160x160Trees_4.png` |
| round tree | `Trees/Colour1/96x128Tree_6.png` |
| pine | `Trees/Colour1/160x160Trees_8.png` |
| pine | `Trees/Colour1/96x128Tree_10.png` |
| rock | `Rocks/Colour1/64x64pxRocks_2.png` |
| rock | `Rocks/Colour1/96x96pxRocks_3.png` |

Dead trees, birches and the Colour2–5 trees leave `tree_defs`; their
ext_resources are removed. Roles/families are reassigned across the kept
trees (round = main group family, pine = secondary family) — builder's call.

### Recolour table (applied in place to the 7 PNGs above only)

| Source | DB32 | Use |
|--------|------|-----|
| `#150E13` | `#000000` | outline |
| `#211B2B` | `#222034` | deep shadow |
| `#3F1A28` | `#45283c` | trunk / rock shadow |
| `#5E3B30` | `#663931` | trunk mid |
| `#8D6A2B` | `#8a6f30` | trunk light |
| `#2D440E` | `#323c39` | leaf shadow |
| `#4C7615` | `#4b692f` | leaf mid |
| `#79A40F` | `#6abe30` | leaf light |
| `#504057` | `#595652` | rock dark |
| `#757A8B` | `#847e87` | rock mid |
| `#A0ACB8` | `#9badb7` | rock light |

Exact-match replace (`magick -fuzz 0 -fill <db32> -opaque <src>`), alpha
untouched. One-off; not committed as a script. Verify afterwards that every
opaque pixel is a DB32 colour.

### Density (`ForestDef` values in caves.tres)

`secondary_groups` 2 → 1, `rock_attempts` 3 → 1. Further tuning by eye.

### Collision

- New 2D physics layer 5 `prop_body` (value 16) in `project.godot`.
- `ForestProp` layer = `prop_body | attackable_hit` (16 | 128). It drops
  `enemy_body`; enemies are blocked via nav-grid blockers, which already exist.
- Player mask = terrain | layer 2 | `prop_body` (3 | 16 = 19) in
  `player_controller.gd`; `scenes/player.tscn` kept consistent. Dash still
  zeroes the mask as before.
- Trees keep a trunk-only circle (walk behind the canopy). Rocks get a
  `trunk_radius` roughly matching their opaque footprint (builder measures;
  ~12 for the 64px rock, ~28 for the 96px one). The planner already spaces
  props by `trunk_radius`.
- Verify in-game that enemies are blocked by props; if not, debug the
  blocker path rather than adding physics to enemies.

### Tree fade

- Trees only (`kind == "tree"`). `ForestProp` adds an `Area2D` covering the
  canopy (sprite's opaque rect above the trunk), mask = `attackable_hit`
  (128), which catches player (129) and enemies (132).
- Ignore other `ForestProp` bodies (also on 128).
- While ≥1 body overlaps: tween sprite alpha to ~0.4; back to 1.0 when empty.
  The hit-flash tween must keep the faded alpha.

## Left to the builder

Exact rock radii, canopy rect sizing, fade alpha/duration, test updates
(`test_caves_biome_decor.gd`, `test_forest_prop.gd` layer assertions).
