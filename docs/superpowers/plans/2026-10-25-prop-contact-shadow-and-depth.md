# Prop Contact Shadow and Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trees and rocks get a soft ground shadow, and the trunk part of each prop depth-sorts with actors and the flora in front of it.

**Architecture:** A new y-sorted `Entities` node under `WorldManager` holds the player and everything the spawners add today. Each `ForestProp` splits its sprite: the canopy stays in the prop at z 2, and a `TrunkBand` sprite (bottom 32 px) lives in `Entities` so it sorts with actors. Each prop also gets a `Shadow` sprite (a shared radial-gradient oval) at z −9, which sits above the floor and its flora and below actors. `FloorChunk` moves flora that stands in front of a trunk into `Entities` and darkens it by the shadow amount at its position.

**Tech Stack:** Godot 4 GDScript, gdUnit4.

**Spec:** `docs/superpowers/specs/2026-10-25-prop-contact-shadow-and-depth-design.md`

## Global Constraints

- Canopies keep drawing over walls (prop `z_index = 2`, absolute); walls stay at z 1 above actors at z 0.
- Shadow strength `0.6` matches the walls' `ao_strength = 0.6`.
- Placement stays deterministic per seed; the planner (`forest_planner.gd`) is not changed.
- Run tests per `AGENTS.md`: `godot --headless --path . --import` once, then
  `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <test path>`.
- Plan deviation from spec (allowed there): rocks split exactly like trees instead of sorting whole. A 96 px rock standing in front of a wall would otherwise lose its top under the wall layer. That's one code path for both kinds.

## Review Focus

1. Level reset (`WorldManager.reset()`) must free spawned actors in `Entities` but **not the Player**, which now lives there too. Test in Task 1.
2. Chunk unload must free every node a chunk put into `Entities` (trunk bands, raised flora), or `Entities` leaks sprites forever. Tests in Tasks 2 and 3.
3. Destroying a prop must take its trunk band and shadow with it, and the death pop must animate the band too. Test in Task 2.
4. Without a world manager (unit tests, editor), props and floor chunks must still build; the band then stays a child of the prop. Test in Task 2.
5. Sort key is each node's origin. The player's feet sit 6 px below its origin (`scenes/player.tscn` Sprite position `(0, 6)`); tall enemies standing just south of a trunk can reach into the canopy and get covered. Manual check in Task 4. Fix only if visible.

---

### Task 1: Y-sorted `Entities` layer

**Files:**
- Modify: `scenes/game.tscn` (add `Entities` under `WorldManager` after `ChunkContainer`; move `Player` under it)
- Modify: `src/core/world_manager.gd` (`entity_layer`, `get_chunk_container()`, `reset()`)
- Modify: `src/debug/debug_manager.gd:13` (player path)
- Test: `tests/unit/test_entity_layer.gd`

**Interfaces:**
- Produces: `WorldManager.entity_layer: Node2D` (y_sort_enabled). `get_chunk_container()` now returns `entity_layer`; the name is kept so its 8 callers (spawners, projectiles, console) need no change. Add a comment saying so.

- [ ] **Step 1: Write the failing tests**

`test_game_scene_has_y_sorted_entities_with_player`: `load("res://scenes/game.tscn").instantiate()` (don't add it to the tree), then
`var e = root.get_node("GameViewport/SubViewport/WorldManager/Entities")`.
Assert `e != null`, `e.y_sort_enabled == true`, `e.get_node_or_null("Player") != null`, and that `Entities` comes after `ChunkContainer` in `WorldManager`'s children (`get_index()` larger). Free `root`.

`test_reset_keeps_player`: tests `static func clear_entities(layer: Node) -> void` on `world_manager.gd` (it frees every child not in group `"player"`). Fill a plain `Node2D` layer with one `Node2D` in group `"player"` and two plain `Node2D`s, call it, `await await_idle_frame()`, and assert one child remains and it is the player.

- [ ] **Step 2: Run to verify fail**

Run: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_entity_layer.gd`
Expected: FAIL (`Entities` not found / `clear_entities` missing)

- [ ] **Step 3: Implement**

- `game.tscn`: add `[node name="Entities" type="Node2D" parent="GameViewport/SubViewport/WorldManager"]` with `y_sort_enabled = true`, placed directly after `ChunkContainer`. Re-parent the `Player` node to `GameViewport/SubViewport/WorldManager/Entities`.
- `world_manager.gd`: `@onready var entity_layer: Node2D = $Entities`; `get_chunk_container()` returns `entity_layer`; add `static func clear_entities(layer: Node) -> void` and call it from `reset()` next to the existing `chunk_container` clear (keep that clear: the chunk meshes still live there).
- `debug_manager.gd:13`: use `get_tree().get_first_node_in_group("player")` instead of `../Player`.

- [ ] **Step 4: Run to verify pass**, then run the full suite (`-a res://tests`). Expected: all PASS.

- [ ] **Step 5: Commit** `feat(world): y-sorted entity layer holds player and spawns`

---

### Task 2: ForestProp shadow and trunk band

**Files:**
- Modify: `src/props/forest_prop.gd`
- Test: `tests/unit/test_forest_prop.gd`

**Interfaces:**
- Consumes: `WorldManager.entity_layer` (Task 1), read via `get("entity_layer")` on the `"world_manager"` group node so stubs without it still work.
- Produces (used by Task 3):
  - `const TRUNK_BAND := 32` (px above the base that sort with actors; about the player's height)
  - `const SHADOW_STRENGTH := 0.6`
  - `static func find_entity_layer(tree: SceneTree) -> Node2D` (null when there's no world manager or it has no `entity_layer`)
  - `static func shadow_size(def: ForestPropDef) -> Vector2`: `w = def.trunk_radius * 4.0`, returns `Vector2(w, w * 0.5)`
  - `static func shadow_darkness(def: ForestPropDef, offset: Vector2) -> float`: with `r = shadow_size(def) / 2`, `e = (offset / r).length()`, returns `SHADOW_STRENGTH * (1.0 - clampf(e, 0.0, 1.0))`
  - `static func is_in_front(def: ForestPropDef, offset: Vector2, flora_height: float) -> bool`: true when `offset.y > 0`, `offset.y - flora_height < 0`, and `absf(offset.x) < def.texture.get_width() / 2.0`

- [ ] **Step 1: Write / update the failing tests**

- Replace `test_sprite_bottom_at_origin` with `test_canopy_and_band_split_at_trunk_band`. Give `_make_def()` a height parameter and use a 16×64 fixture (inset 3, so 61 opaque rows), with the prop not in a tree. The `"Sprite2D"` canopy region is `Rect2(0, 0, 16, 29)` and its bottom sits at y = −32. The `"TrunkBand"` region is `Rect2(0, 29, 16, 32)` and its bottom sits at y = 0.
- `test_short_prop_has_band_only`: the existing 16×32 fixture (29 opaque rows, under `TRUNK_BAND`) has a `"TrunkBand"` with region `Rect2(0, 0, 16, 29)` and no `"Sprite2D"` child.
- `test_shadow_child`: `"Shadow"` exists, `z_as_relative == false`, `z_index == -9`, and its drawn size equals `shadow_size(def)` (`texture size * scale`).
- `test_shadow_darkness`: for def radius 6 (size 24×12), `shadow_darkness(def, Vector2.ZERO) == 0.6`, `shadow_darkness(def, Vector2(12, 0)) == 0.0`, `shadow_darkness(def, Vector2(6, 0)) ≈ 0.3`.
- `test_is_in_front`: fixture width 16. `(0, 4)` with height 8 → true; `(0, -2)` → false (north); `(0, 12)` with height 8 → false (doesn't reach the base); `(9, 4)` → false (outside the width).
- `test_band_in_entity_layer_and_freed_with_prop`: give `StubWM` a `var entity_layer: Node2D` (y-sorted `Node2D` added under the stub). Add the prop at `(100, 100)`. Assert the band's parent is `entity_layer` and `band.global_position == Vector2(100, 100)`. Then `prop.free()`, `await await_idle_frame()`, and assert `entity_layer.get_child_count() == 0`.
- `test_band_freed_on_destroy`: same setup, `on_hit_impact(...)`, wait for the pop (`await await_millis(int(POP_TIME * 1000) + 100)`), and assert `entity_layer` is empty.
- `test_hit_flash_keeps_fade` / the fade tests keep their `"Sprite2D"` paths (the canopy keeps that name), plus assert the band's `self_modulate.a` matches the canopy's.
- `test_setup_layers_and_groups`: unchanged (prop z stays 2).

- [ ] **Step 2: Run to verify fail**: `-a res://tests/unit/test_forest_prop.gd`. Expected: FAIL on the new tests.

- [ ] **Step 3: Implement in `forest_prop.gd`**

- Delete the `ponytail:` fixed-z comment (`forest_prop.gd:50`); keep `z_index = 2` for the canopy.
- `setup()`: `band_h = mini(TRUNK_BAND, h - inset)`. The canopy `_sprite` (name `"Sprite2D"`, `centered = false`, `region_enabled`) gets region `Rect2(0, 0, w, h - inset - band_h)` and offset `(-w/2, -(h - inset))`; skip adding it when the height is 0 (keep `_sprite` pointing at the band in that case so fade/flash code has a target). `_band` (name `"TrunkBand"`, same settings, `z_as_relative = false`, `z_index = 0`) gets region `Rect2(0, h - inset - band_h, w, band_h)` and offset `(-w/2, -band_h)`. Both are tinted `def.tint`. The band starts as the prop's child.
- Shadow: `Sprite2D` `"Shadow"`, `z_as_relative = false`, `z_index = -9`, texture = a lazily built static `GradientTexture2D` (32×32, `FILL_RADIAL`, `fill_from (0.5, 0.5)`, `fill_to (1, 0.5)`, gradient black α `SHADOW_STRENGTH` → black α 0), `scale = shadow_size(def) / 32`.
- `_enter_tree()`: if `find_entity_layer(get_tree())` is non-null and the band is still our child, reparent it there (`remove_child` + `layer.add_child`) and set `_band.global_position = global_position`. Keep the existing rock nav-blocker logic, restructured so the band move runs for trees too.
- `_exit_tree()`: if `_band` is valid and its parent isn't `self`, `_band.queue_free()`. Then do the existing blocker removal.
- `_fade_to`, `_pop`, the white flash and the `_burst` z: apply to both `_sprite` and `_band` (same tween, parallel). The squash scales each sprite around its own origin, which is the trunk base for both.

- [ ] **Step 4: Run to verify pass**: `-a res://tests/unit/test_forest_prop.gd`, then `-a res://tests/unit/test_floor_chunk.gd`. Expected: all PASS.

- [ ] **Step 5: Commit** `feat(props): ground shadow and y-sorted trunk band`

---

### Task 3: Flora in front of trunks joins the sort, darkened

**Files:**
- Modify: `src/terrain/floor_chunk.gd` (`_add_decorations`, `populate`, add `_exit_tree`)
- Test: `tests/unit/test_floor_chunk.gd`

**Interfaces:**
- Consumes: `ForestProp.find_entity_layer`, `is_in_front`, `shadow_darkness` (Task 2).

- [ ] **Step 1: Write the failing tests** (add a stub WM with `entity_layer`, as in Task 2, to the test-suite setup for these two)

- `test_front_flora_moves_to_entity_layer_darkened`: populate with `_room_bytes()`, seed 4646, flora textures 16×16, and the stub WM in the tree. Recompute from `ForestPlanner.plan(...)` which flora entries are `is_in_front` of some prop (offset = flora pos − prop pos, height 16). Assert `entity_layer` holds exactly that many `Sprite2D`s whose names start with `"Decor"`. For each one, `modulate.r ≈ 1.0 - max shadow_darkness over the props it's in front of`. Every other decor stays a child of the chunk with `modulate == Color.WHITE`. The planner's ring band `ROOT_RING = (6, 28)` guarantees at least one hit at this seed; if it doesn't, pick a seed where it does and say so in a comment.
- `test_chunk_free_clears_raised_flora`: same setup, `chunk.free()`, `await await_idle_frame()`, and assert `entity_layer` has no `"Decor"` children (bands are already covered in Task 2).

- [ ] **Step 2: Run to verify fail**: `-a res://tests/unit/test_floor_chunk.gd`. Expected: FAIL.

- [ ] **Step 3: Implement in `floor_chunk.gd`**

- Collect prop entries (`pos`, `def`) from `entries` before the node loop, skipping `ForestProp.is_destroyed(id)` ones so grass in front of a felled tree stays on the floor.
- For each flora sprite: take the props it `is_in_front` of. If there are any and `find_entity_layer(get_tree())` is non-null, set `modulate` to `Color(1 - d, 1 - d, 1 - d)` with `d` = max `shadow_darkness`, add the sprite to the entity layer at `global_position = to_global(pos)`, and append it to `var _raised: Array[Node2D]`. Otherwise add it to the chunk as today. The baked light splat is unchanged either way.
- `populate()` and a new `_exit_tree()` both `queue_free()` every valid node in `_raised` and clear the array.

- [ ] **Step 4: Run to verify pass**: `-a res://tests/unit/test_floor_chunk.gd`, then the full suite `-a res://tests`. Expected: all PASS.

- [ ] **Step 5: Commit** `feat(forest): flora in front of trunks sorts with actors`

---

### Task 4: Visual check in the running game

- [ ] **Step 1:** Run the game (`run` skill or `godot --path .`) and walk into a forest patch. Check each of these, with screenshots for the user:
  - every tree and rock has a soft dark oval at its base, and glowing flora inside it reads dimmer while its light pool remains
  - grass south of a trunk draws over the trunk
  - the player walking south of a trunk draws in front of it and walking north draws behind it, with the canopy covering them
  - canopies still overhang walls, walls still cover actors, and nothing flickers at chunk borders
  - Review Focus item 5 (feet offset, tall enemies)
- [ ] **Step 2:** Report anything off to the user before tuning `TRUNK_BAND`, the shadow size factor (`4.0`/`0.5`) or the strength.
