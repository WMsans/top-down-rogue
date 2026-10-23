# Cave Forest Vegetation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the uniform 16px decor scatter with composed forest patches. Trees and big rocks are solid,
breakable props that sit on open floor only. Small glowing flora clusters at their roots and lights the cave.

**Architecture:**
- A pure `ForestPlanner` turns one chunk's material bytes, the world seed and a `ForestDef` into a deterministic list
  of placements:
  - a patch mask from world-space noise
  - a main triangle group, secondary groups and wall-edge rocks
  - root flora clusters, and a sprinkle of flora outside patches
- `FloorChunk` instantiates the placements. Flora becomes ground sprites feeding the existing baked light. Props become
  `ForestProp` nodes.
- A `ForestProp` is a `StaticBody2D` on the actor + attackable layers. It takes hits via the existing `destructible`
  path, plays wood/stone dig FX plus simulated dust, and blocks enemy navigation through an overlay on
  `PassabilityGrid`.

**Tech Stack:** Godot 4, GDScript, gdUnit4.

**Spec:** `docs/superpowers/specs/2026-10-23-cave-forest-vegetation-design.md`

## Global Constraints

- Caves biome only. The configuration is data-driven on `BiomeDef` so other biomes can opt in.
- No new per-object `PointLight2D`. Flora light goes through `FloorChunk._bake_decor_lights` (one light per chunk).
- Props are never part of the fire or terrain simulation. Fire, lava and gas never affect them.
- Canopies never fade.
- Placement is deterministic per `(world_seed, chunk coord)`. Chunks regenerate pristine terrain on reload, so the same
  bytes produce the same placements.
- A destroyed prop stays destroyed for the rest of the floor, including across chunk reloads.
- Homing and auto-aim scan the `attackable` group. Props join `destructible` only, never `attackable`.
- Tests run headless:
  `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/<file>.gd`.
  In a fresh worktree, run `godot --headless --path . --import` once first.

## Review Focus

1. **Actor standing just south of a trunk:** props draw at `z_index = 2`, above actors, not y-sorted (see Task 3).
   An actor's head within about 6px of the trunk base is drawn under the roots. Expected: barely noticeable, because
   the trunk collision keeps actors out of that band. Check in game (Task 6).
2. **Many enemy shots landing on one grove:** each dust splash reads a whole chunk texture back from the GPU.
   Expected: dust is rate-limited per prop. Pinned by `test_dust_rate_limited` in Task 3.
3. **A chunk unloads while its props are alive:** expected: their nav blockers are released. Pinned by
   `test_free_releases_nav_blocker` in Task 3.
4. **Next floor reuses the same chunk coords:** expected: trees appear again, because the destroyed registry is keyed
   by seed. Pinned by `test_destroyed_registry_is_per_seed` in Task 3.
5. **The cave spawner picks a spot inside a trunk:** expected: rejected. Pinned by
   `test_footprint_rejects_prop_blocker` in Task 1.

---

### Task 1: Prop blockers in navigation and spawn validation

**Files:**
- Modify: `src/core/nav/passability_grid.gd`
- Modify: `src/core/spawn_validation.gd`
- Test: `tests/unit/test_passability_blockers.gd` (new)

**Interfaces:**
- Produces:
  - `PassabilityGrid.add_blocker(world_pos: Vector2, radius: float) -> void`
  - `PassabilityGrid.remove_blocker(world_pos: Vector2, radius: float) -> void`
  - `is_solid_cell` / `is_solid_world` return true for blocked cells, regardless of the tiles.
  - `SpawnValidation.footprint_clear` returns false if any footprint corner is blocked.
- `NavField.is_solid_world` already delegates to `grid`, so it needs no change.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_passability_blockers.gd`:
  - `test_blocker_marks_cells_solid`:
    - `g := PassabilityGrid.new(8, 256, lut)` with an all-zero tile set for chunk `(0,0)`.
    - `g.add_blocker(Vector2(100, 100), 6.0)`.
    - Assert `g.is_solid_world(Vector2(100,100))` is true and `g.is_solid_world(Vector2(140,100))` is false.
  - `test_blocker_survives_tile_update`: add the blocker, then `g.set_tile(Vector2i(0,0), zero_tile)`. Still solid.
  - `test_overlapping_blockers_refcount`:
    - Add two blockers at the same position, then remove one: still solid.
    - Remove the second: not solid.
  - `test_footprint_rejects_prop_blocker`:
    - A stub world manager whose `read_region` returns all-`MAT_AIR` bytes of the requested size, and whose `nav_field`
      exposes a `grid` with a blocker at `(50,50)` radius 6.
    - Assert `SpawnValidation.footprint_clear(stub, Vector2(50,50))` is false and
      `SpawnValidation.footprint_clear(stub, Vector2(200,200))` is true.

- [ ] **Step 2: Run the tests and confirm they fail.**
  Run `... -a res://tests/unit/test_passability_blockers.gd`. Expected: FAIL (`add_blocker` not found).

- [ ] **Step 3: Implement.**
  - `PassabilityGrid` gains `var _blocked: Dictionary = {}  # Vector2i cell -> int refcount`.
  - `add_blocker` and `remove_blocker` walk every cell whose 8px square overlaps the disc (bounding square of the
    radius, in `world_to_cell` units). They increment or decrement the count, erasing it at 0.
  - `is_solid_cell` checks `_blocked.has(cell)` first.
  - In `footprint_clear`, after the material check: when `world_manager.get("nav_field")` is non-null, return false if
    `nav_field.grid.is_solid_world(...)` is true for any of the four footprint corners. Material walls are already
    rejected by the byte check, so only prop blockers add new rejections here.

- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "feat(nav): prop blockers overlay on passability grid"`

---

### Task 2: Dust splash API

**Files:**
- Modify: `src/core/terrain_modifier.gd:170-236` (`place_gas_splash`)
- Modify: `src/core/world_manager.gd` (wrapper next to `place_gas_splash`, around line 239)
- Modify: `src/core/terrain_surface.gd` (wrapper next to `place_gas_splash`)

**Interfaces:**
- Produces: `TerrainSurface.place_dust_splash(world_pos: Vector2, radius: float, outward_speed: float, source_material: int, bias_dir: Vector2 = Vector2.ZERO) -> void`.
  - It writes `MAT_DUST` into air pixels:
    - byte 1 = density `200` (matches `DUST_BURST_DENSITY` in `shaders/compute/melee_arc.glsl`)
    - byte 2 = `source_material`, which tints the dust like dust created by digging
    - byte 3 = packed velocity, the same encoding as gas

- [ ] **Step 1: Refactor.**
  - Extract the body of `place_gas_splash` into
    `_place_velocity_splash(world_pos, radius, material_id: int, density: int, source_byte: int, outward_speed, bias_dir)`.
  - `place_gas_splash` calls it with `MAT_GAS, density, 0`.
  - Add `place_dust_splash`, which calls it with `MAT_DUST, 200, source_material`.
  - Add pass-through wrappers on `world_manager.gd` and `terrain_surface.gd`, following the `place_gas_splash` pattern.

- [ ] **Step 2: Run the existing suite to check for regressions.**
  Run `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit`.
  Expected: the same pass and fail counts as on `master` before this change. Record the baseline first.
  This needs the GPU, so there's no unit test for it; it is verified visually in Task 6.

- [ ] **Step 3: Commit.** `git commit -m "feat(terrain): place_dust_splash with source material"`

---

### Task 3: ForestPropDef and the ForestProp runtime, plus dig-aware hits

**Files:**
- Create: `src/core/forest_prop_def.gd`
- Create: `src/props/forest_prop.gd`
- Modify: `src/weapons/weapon.gd:224-236` (`resolve_hit`)
- Modify: `src/weapons/projectile.gd:62-64,83-85` (the two `destructible` branches)
- Test: `tests/unit/test_forest_prop.gd` (new)

**Interfaces:**
- Consumes:
  - `PassabilityGrid.add_blocker/remove_blocker` (Task 1), reached via `get_tree().get_first_node_in_group("world_manager").nav_field.grid`, with null guards.
  - `TerrainSurface.place_dust_splash` (Task 2).
  - `TerrainImpact.play_impact(pos, material_id, intensity, parent)`.
- Produces:
  - `class_name ForestPropDef extends Resource` with these exports:
    - `texture: Texture2D`
    - `kind: String = "tree"` (`"tree"` | `"rock"`)
    - `role: String = "any"` (`"bright"` | `"dark"` | `"odd"` | `"any"`)
    - `family: String = ""`
    - `trunk_radius: float = 6.0`
    - `hp: float = 10.0`
    - `tint: Color = Color(0.7, 0.7, 0.75, 1)`
    - `weight: float = 1.0`
  - `ForestPropDef.impact_material() -> int` returns `MAT_WOOD` for trees and `MAT_STONE` for rocks.
  - `ForestPropDef.base_inset() -> int`: the number of fully transparent rows at the bottom of `texture`, computed once
    from `texture.get_image()` and cached.
  - `class_name ForestProp extends StaticBody2D` with:
    - `setup(def: ForestPropDef, prop_id: String) -> void`
    - `take_dig_hit(impact_pos: Vector2, hit_dir: Vector2, dig_power: float) -> void`
    - `on_hit_impact(impact_pos: Vector2, hit_dir: Vector2) -> void`, which equals `take_dig_hit(..., 0.0)`
    - `var hp: float`
    - `static func is_destroyed(prop_id: String) -> bool`
    - `static func make_id(world_seed: int, coord: Vector2i, index: int) -> String`, returning `"%d:%d:%d:%d"`
  - `const DIG_WEIGHT := 0.5`, `const DIG_CAP := 6.0`, `const DUST_COOLDOWN := 0.1`
  - Damage per hit is `1.0 + minf(maxf(dig_power, 0.0), DIG_CAP) * DIG_WEIGHT`.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_forest_prop.gd`. Use a 16×32 opaque `ImageTexture` whose
  bottom 3 rows are transparent.
  - `test_setup_layers_and_groups`:
    - `collision_layer == 132`, `collision_mask == 0`
    - `is_in_group("destructible")` is true and `is_in_group("attackable")` is false
    - `z_index == 2`, `z_as_relative == false`
    - It has a `CollisionShape2D` with a `CircleShape2D` of radius `def.trunk_radius`
  - `test_sprite_bottom_at_origin`: the sprite's drawn bottom edge, after removing `base_inset()` (3), sits at local y = 0.
  - `test_dig_scales_damage`: `hp=10`; `take_dig_hit(.., 3.0)` leaves `hp == 7.5`; `on_hit_impact` leaves `hp == 6.5`.
  - `test_free_carve_dig_is_capped`: `take_dig_hit(.., 1.0e9)` deals exactly `4.0`.
  - `test_destroyed_when_hp_depleted`: `hp=2`, one `take_dig_hit(.., 6.0)`. Then `is_queued_for_deletion()` is true and
    `ForestProp.is_destroyed(id)` is true.
  - `test_destroyed_registry_is_per_seed`: destroy `make_id(1, Vector2i(0,0), 0)`. Then
    `is_destroyed(make_id(2, Vector2i(0,0), 0))` is false.
  - `test_dust_rate_limited`:
    - Inject a dust counter by making the dust call go through an overridable method `_emit_dust(pos, dir)`; the test
      subclass counts calls.
    - Two hits in the same frame give 1 call. After `DUST_COOLDOWN` has elapsed (advance the internal clock through an
      overridable `_now() -> float`), a hit gives 2.
  - `test_free_releases_nav_blocker`: with a stub world manager in group `world_manager` exposing `nav_field.grid` as a
    real `PassabilityGrid`. After `setup` and `add_child`, the trunk cell is solid. After `free()`, it is not.
  - `test_resolve_hit_passes_dig_power` (weapon side): a `Weapon` with `dig_power = 3.0` and a stub target that records
    `take_dig_hit` args. `resolve_hit(user, stub)` records `dig_power == 3.0`, and the stub's `on_hit_impact` is not
    called.

- [ ] **Step 2: Run the tests and confirm they fail.** `-a res://tests/unit/test_forest_prop.gd`. Expected: FAIL.

- [ ] **Step 3: Implement `ForestPropDef` and `ForestProp`.**
  - `setup` builds these children in code (no scene):
    - `Sprite2D`, `centered = true`, `offset.y = -tex_h / 2 + base_inset()`, `modulate = def.tint`
    - `CollisionShape2D(CircleShape2D)`
  - It sets the layers above and joins `destructible`.
  - Draw order: `z_as_relative = false`, `z_index = 2`. That is above the wall quad (`chunk_manager.gd:101`, z 1) and
    actors (z 0), so canopies overhang walls. Mark it with
    `# ponytail: fixed z above walls/actors instead of y-sort; actors within ~6px south of a trunk draw under roots. Split trunk/canopy sprites if that shows.`
  - `_enter_tree` adds the nav blocker at `global_position` with radius `trunk_radius`, and `_exit_tree` removes it.
  - Each hit:
    - flashes `modulate` to white, then tweens back to `def.tint` over 0.15s
    - calls `TerrainImpact.play_impact(impact_pos, def.impact_material(), 1.0, get_parent())`
    - calls `_emit_dust(impact_pos, -hit_dir)`, at most once per `DUST_COOLDOWN`; it calls
      `TerrainSurface.place_dust_splash(pos, 4.0, 120.0, def.impact_material(), dir)`
  - Death:
    - three `play_impact` calls at intensity 2.0: one at the trunk base and two at random points inside the sprite's
      upper half
    - one `place_dust_splash(global_position, 10.0, 160.0, mat)`, which ignores the cooldown
    - registers the id in `static var _destroyed: Dictionary`, then calls `queue_free()`
  - Use `impact_pos = global_position` when the caller passes `Vector2.ZERO`.
  - Mark the registry with `# ponytail: never cleared; keyed by seed so floors don't collide. Clear on floor_changed if it ever matters.`

- [ ] **Step 4: Implement the dig hook.**
  - `Weapon.resolve_hit`: when `target.has_method("take_dig_hit")`, call `target.take_dig_hit(pos, hit_dir, dig_power)`
    instead of `on_hit_impact`.
  - `projectile.gd`, both `destructible` branches: the same check, passing `global_position, direction, dig_power`.

- [ ] **Step 5: Run the tests and confirm they pass.** Run `test_forest_prop.gd`, then the full `res://tests/unit`
  suite. Expected: PASS, with no new failures against the baseline.

- [ ] **Step 6: Commit.** `git commit -m "feat(props): breakable ForestProp with dig-scaled hits and dust"`

---

### Task 4: ForestDef and ForestPlanner (pure placement)

**Files:**
- Create: `src/core/forest_def.gd`
- Create: `src/terrain/forest_planner.gd`
- Test: `tests/unit/test_forest_planner.gd` (new)

**Interfaces:**
- Consumes: `ForestPropDef` (Task 3), `DecorDef` (existing), `SectorGrid` (existing).
- Produces:
  - `class_name ForestDef extends Resource` with these exports:
    - `tree_defs: Array[ForestPropDef]`, `rock_defs: Array[ForestPropDef]`
    - `root_flora: Array[DecorDef]` (glowing), `edge_rocks: Array[DecorDef]` (small non-glowing rocks),
      `sprinkle_flora: Array[DecorDef]`
    - `patch_frequency: float = 0.003`, `patch_threshold: float = 0.2`
    - `secondary_groups: int = 2`, `rock_attempts: int = 3`, `edge_rock_count: int = 4`
    - `flora_per_tree: int = 4`, `sprinkle_chance: float = 0.012`
  - `class_name ForestPlanner extends RefCounted` with
    `static func plan(coord: Vector2i, forest: ForestDef, world_seed: int, material_bytes: PackedByteArray, keep_out: Callable = Callable()) -> Array`.
    - It returns an Array of Dictionaries:
      `{"kind": "prop"|"flora", "def": ForestPropDef|DecorDef, "pos": Vector2 (chunk-local; trunk base for props), "index": int}`.
    - `index` is the position in the returned array, which is stable for identical inputs.
    - `keep_out.call(world_pos: Vector2) -> bool` vetoes props only.
  - `static func sector_keep_out(grid: SectorGrid, world_pos: Vector2) -> bool`.
  - Constants:
    - `CELL := 8`, `EDGE_MARGIN := 16.0`, `PASS_GAP := 16.0`, `HUG_MAX := 56.0`
    - `MAIN_NEAR := Vector2(24, 40)`, `MAIN_FAR := Vector2(64, 112)`, `SECONDARY_MIN_DIST := 96.0`
    - `ROOT_RING := Vector2(6, 28)`, `KEEP_OUT_MARGIN := 32.0`

**Placement algorithm** (the tests pin the invariants; this ordering is the design):
1. **Coarse grid.** Build 32×32 cells: a cell is open only if all its 64 pixels are `MAT_AIR`. Compute `wall_dist[cell]`
   in pixels with an 8-connected BFS from closed cells, multiplied by `CELL`. Cells outside the chunk count as open.
2. **Patch mask.** `FastNoiseLite` (simplex, `seed = world_seed`, `frequency = patch_frequency`) sampled at the world
   position. The position is in-patch when the noise is greater than `patch_threshold`.
3. **Prop candidates** are cells whose centre meets all of these:
   - in-patch
   - `wall_dist >= trunk_radius + PASS_GAP`, so the trunk never seals a gap narrower than `2*(r+PASS_GAP)`
   - `wall_dist <= HUG_MAX`, so trees hug walls and room centres stay clear
   - at least `EDGE_MARGIN` from the chunk border
   - `not keep_out`
   - every accepted prop also keeps centre spacing `>= r_a + r_b + PASS_GAP` from earlier props
4. **Main group.** Seed the RNG with `FloorChunk._hash_seed(world_seed, coord)`. Pick an anchor candidate and place
   the trees in this order:
   - a `bright` tree at the anchor
   - a `dark` tree at a candidate between `MAIN_NEAR.x` and `MAIN_NEAR.y` from the anchor
   - an `odd` tree between `MAIN_FAR.x` and `MAIN_FAR.y` from the anchor

   If no def has the role, fall back to `any`. A slot with no candidate is skipped.
5. **Secondary groups.** `secondary_groups` times: pick a candidate at least `SECONDARY_MIN_DIST` from the main anchor
   and choose one `family` different from the anchor tree's family. Place 1–2 trees of that family, 20–36px apart.
6. **Rocks.** `rock_attempts` times, place a rock def at the candidate closest to a wall.
   Then place `edge_rock_count` `edge_rocks` flora at open in-patch cells with `wall_dist == CELL` (touching a wall).
7. **Root flora.** For each prop, place `flora_per_tree` `root_flora` at random angles, with radius inside
   `ROOT_RING`, on exact `MAT_AIR` pixels. Then place one lone accent from `root_flora` at the in-patch open cell
   with the largest `wall_dist` (the clearing).
8. **Sprinkle.** For each 16px cell outside patches whose centre pixel is air, place one `sprinkle_flora` with
   probability `sprinkle_chance`.

Weighted picks use each def's `weight`.

`sector_keep_out(grid, world_pos)`:
- Resolve the slot at `grid.world_to_sector(world_pos)`.
- It returns true if any of these hold: `slot.is_boss`, `slot.is_claimed`, `slot.composition != null`,
  `slot.template_override != null`.
- It also returns true for a template room (`grid.get_template_for_slot(slot) != null`) when `world_pos` lies within
  `size_class / 2 + KEEP_OUT_MARGIN` (Chebyshev distance) of `grid.sector_to_world_center(sector)`. This covers shops,
  chests in rooms and the guidance anchor.
- Otherwise false.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_forest_planner.gd`.
  - Fixtures:
    - `_room_bytes()`: solid everywhere except an air disc of radius 110 centred at (128,128)
    - `_corridor_bytes()`: solid except a horizontal 24px-tall air band
    - `_forest(threshold)`: 6 tree defs (bright, dark, odd; two `pine`, one `dead`, radius 6) and one rock def
      (radius 10), plus 16px flora defs
  - `test_props_never_touch_solid`: `_room_bytes()`, threshold `-1.0` (always in-patch). For every prop, every pixel
    within `trunk_radius + PASS_GAP` of `pos` is `MAT_AIR`.
  - `test_props_respect_spacing`: every pair of props is at least `r_a + r_b + PASS_GAP` apart.
  - `test_narrow_corridor_gets_no_props`: `_corridor_bytes()`, threshold `-1.0`, gives zero props.
  - `test_all_solid_gets_nothing`: zero entries.
  - `test_main_group_roles_and_distances`:
    - `_room_bytes()`, threshold `-1.0`.
    - The first three props have roles `bright`, `dark`, `odd`.
    - dist(0,1) is in `MAIN_NEAR` and dist(0,2) is in `MAIN_FAR`.
  - `test_props_keep_edge_margin`: every prop is at least `EDGE_MARGIN` from each chunk border.
  - `test_keep_out_blocks_props_not_flora`: `keep_out` always true gives zero props and more than zero flora.
  - `test_outside_patch_only_sprinkle`:
    - threshold `1.0`, `sprinkle_chance = 1.0`
    - zero props, and every flora def is from `sprinkle_flora`
  - `test_deterministic`: the same inputs twice produce equal `kind`/`pos`/`index` lists. A different seed produces a
    different list.
  - `test_sector_keep_out_guidance_anchor`: `SectorGrid.new(123, load("res://assets/biomes/caves.tres"))`.
    `sector_keep_out(grid, Vector2(sector_to_world_center(Vector2i.ZERO)))` is true.

- [ ] **Step 2: Run the tests and confirm they fail.** `-a res://tests/unit/test_forest_planner.gd`. Expected: FAIL.

- [ ] **Step 3: Implement `ForestDef`, then `ForestPlanner.plan` and `sector_keep_out`** following the algorithm
  above. Expose `_hash_seed` usage by calling `FloorChunk._hash_seed` (it is already `static`).

- [ ] **Step 4: Run the tests and confirm they pass.** Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "feat(terrain): ForestPlanner composes deterministic forest patches"`

---

### Task 5: Wire the planner into FloorChunk and replace the old scatter

**Files:**
- Modify: `src/core/biome_def.gd:18-19`. Replace `decor_defs` and `decor_chance` with `@export var forest: ForestDef = null`.
- Modify: `src/terrain/floor_chunk.gd:20-98`. Rewrite `populate` and `_add_decorations`; keep `_bake_decor_lights` and `_hash_seed`.
- Modify: `src/terrain/floor_container.gd:18-29`. Pass `keep_out`.
- Modify: `assets/biomes/caves.tres`. Temporarily move the three existing flora into a minimal `ForestDef` as
  `root_flora` and `sprinkle_flora` so the biome still loads. Task 6 fills in the real content.
- Test: rewrite `tests/unit/test_floor_chunk.gd` and `tests/unit/test_floor_chunk_decor_lights.gd`. Update
  `tests/unit/test_biome_def.gd` and `tests/unit/test_caves_biome_decor.gd`.

**Interfaces:**
- Consumes: `ForestPlanner.plan`, `ForestPlanner.sector_keep_out` (Task 4), and `ForestProp`, `ForestProp.make_id`,
  `ForestProp.is_destroyed` (Task 3).
- Produces: `FloorChunk.populate(coord: Vector2i, biome: BiomeDef, world_seed: int, material_bytes: PackedByteArray = PackedByteArray(), keep_out: Callable = Callable()) -> void`.
  - Flora children are named `"Decor%d"` (the same as today).
  - Prop children are `ForestProp` nodes named `"Prop%d"`.

- [ ] **Step 1: Rewrite the tests.**
  - Port the existing floor-sprite, light-baking and determinism tests from `decor_defs`/`decor_chance` to a test
    `ForestDef` with threshold `-1.0`.
  - Add these:
    - `test_populate_spawns_forest_props`: `_all_air_bytes()` gives at least one `ForestProp` child, each at
      chunk-local `pos`.
    - `test_destroyed_prop_not_respawned`:
      - Populate, then pick the first prop's id.
      - Mark it destroyed via `take_dig_hit` with lethal damage.
      - Populate a fresh `FloorChunk` with the same args.
      - The new chunk has one fewer `ForestProp`, and no prop has that id.
    - `test_flora_feeds_baked_light`: glowing `root_flora` gives exactly one `DecorLights` child.
  - In `test_caves_biome_decor.gd`, assert that `biome.forest != null` and that `root_flora` is non-empty and glowing.
  - In `test_biome_def.gd`, the default `forest` is null.

- [ ] **Step 2: Run the tests and confirm they fail.** Run the four files. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - `populate` calls `ForestPlanner.plan(coord, biome.forest, world_seed, material_bytes, keep_out)` when
    `biome.forest != null` and the bytes are a full chunk.
  - Flora: spawn a sprite (bottom-centred at `pos`) and add a light splat when `emits_light`.
  - Props: build `id := ForestProp.make_id(world_seed, coord, index)` and skip it if destroyed. Otherwise create a
    `ForestProp`, call `setup(def, id)`, set `position = pos` and `add_child` it.
  - Then call `_bake_decor_lights(splats)`.
  - `FloorContainer` builds `keep_out` as `func(p): return ForestPlanner.sector_keep_out(grid, p)` when
    `LevelManager.get_grid()` is non-null, and an empty `Callable()` otherwise. The planner treats an empty callable
    as "never keep out".
  - `grep -rn "decor_defs\|decor_chance" src tests assets` must return nothing afterwards.

- [ ] **Step 4: Run the tests and confirm they pass.** Run the four files, then the full `res://tests/unit`.
  Expected: PASS, with no new failures against the baseline.

- [ ] **Step 5: Commit.** `git commit -m "feat(terrain): floor chunks place forest patches; drop uniform scatter"`

---

### Task 6: Caves forest content and in-game tuning

**Files:**
- Modify: `assets/biomes/caves.tres` (the `ForestDef` sub-resource)
- Modify: `tests/unit/test_caves_biome_decor.gd`

**Content.** Paths are relative to `res://textures/Assets/NaturalDecorsTreesAndRocksv1/`:

| Group | Defs | Settings |
|---|---|---|
| `bright` | `Trees/Colour1/160x160Trees_2.png`, `Trees/Colour1/96x128Tree_3.png` | family `round` |
| `dark` | `Trees/Colour2/160x160Trees2_4.png`, `Trees/Colour5/160x160Trees5_3.png` | family `round` |
| `odd` | `Trees/Colour4/160x160Trees4_2.png` (teal), `Trees/Colour3/160x160Trees3_1.png` (autumn) | family `round` |
| `any` | `Trees/Colour4/96x128Tree4_10.png`, `Trees/Colour2/96x128Tree2_11.png`, `Trees/Colour5/96x128Tree5_10.png` | family `pine` |
| `any` | `Trees/Colour1/160x160Trees_6.png`, `Trees/Colour1/96x128Tree_8.png` | family `dead` |
| Rocks | `Rocks/Colour1/64x64pxRocks_1.png`, `Rocks/Colour1/64x64pxRocks_4.png` | hp 16, radius 10 |
| Rocks | `Rocks/Colour1/96x96pxRocks_3.png` | hp 24, radius 14 |
| Edge rocks (`DecorDef`, `emits_light = false`) | `Rocks/Colour1/32x32pxRocks_3.png`, `_7`, `_9` | |
| Root flora | the existing `grass1`, `grass2` and `small_tree`; `res://textures/Assets/db32/blocks/plants/mushroom_red.png`, `mushroom_brown.png` | teal/cyan light, radius 40–52 |
| Root flora | `amethyst_crystal.png` | violet `Color(0.75, 0.5, 1.0)`, weight 0.5 |
| Sprinkle flora | the same glowing defs as root flora | |

Trees: hp 8 for 96×128 and 12 for 160×160, trunk radius 6.

- [ ] **Step 1: Update the test.** `test_caves_forest_content`:
  - `tree_defs` contains at least one each of `bright`, `dark` and `odd`, and at least two distinct `family` values.
  - Every texture is non-null, `rock_defs` is non-empty, and every `root_flora` emits light.

- [ ] **Step 2: Fill in `caves.tres`** per the table, then run `test_caves_biome_decor.gd`. Expected: PASS.

- [ ] **Step 3: Verify in game.**
  - Run the game (`godot --path .`), walk at least 6 chunks from spawn and take screenshots.
  - Check against mockup B and the spec's anti-goals:
    - patches with bare rock between them, not an even scatter
    - trees dark, with light in pools at the roots
    - no sealed corridors
    - no trees in the shop, guidance room or arenas
    - no seams at chunk borders
    - canopies drawn over the walls behind them
  - Hit a tree with a sword and with a gun: you should see wood particles and dust, and it falls in a handful of hits.
    A rock gives stone particles.
  - Let a ranged enemy shoot into a grove. Frame rate should stay steady and enemies should path around trunks.
  - Tune `patch_frequency`, `patch_threshold`, `tint` and the counts in `caves.tres` only.

- [ ] **Step 4: Run the full suite.** `-a res://tests/unit`. Expected: no new failures against the baseline.

- [ ] **Step 5: Commit.** `git commit -m "feat(caves): forest content and tuning"`
