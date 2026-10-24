# Cave Forest Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Calmer, solid cave forest: 5 Colour1 trees + 2 rocks recoloured to DB32, lower density, props collide with the player, trees fade over actors.

**Architecture:** Content and density are data in `assets/biomes/caves.tres`. Collision is a new physics layer on `ForestProp` plus the player's mask. Fade is an `Area2D` built in `ForestProp.setup()` for trees, driving the sprite's `self_modulate.a` (the hit flash uses `modulate`, so the two don't fight).

**Tech Stack:** Godot 4 / GDScript, gdUnit4, ImageMagick (`magick`) for the one-off recolour.

**Spec:** `docs/superpowers/specs/2026-10-24-cave-forest-cleanup-design.md`

## Global Constraints

- Test command (from the repo root): `godot --headless --path . --import && godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a <test path>`
- Art root: `textures/Assets/NaturalDecorsTreesAndRocksv1/`; only the 7 kept PNGs get recoloured.
- Physics: layer 5 `prop_body` = 16; `attackable_hit` = 128; `enemy_body` = 4. The player's mask must never include 4.
- DB32 hex set: `000000 222034 45283c 663931 8f563b df7126 d9a066 eec39a fbf236 99e550 6abe30 37946e 4b692f 524b24 323c39 3f3f74 306082 5b6ee1 639bff 5fcde4 cbdbfc ffffff 9badb7 847e87 696a6a 595652 76428a ac3232 d95763 d77bba 8f974a 8a6f30`

## Review Focus

- Player vs enemy contact: after the mask change, the player must still pass through enemies (mask 19 & 132 == 0). Checked in Task 4.
- Hit flash on a faded tree: digging a tree while the player is behind it must keep it faded. Covered by `test_hit_flash_keeps_fade` (Task 3).
- Several occluders: two enemies behind one tree, one leaves, so the tree stays faded. Covered by `test_fade_counts_occluders` (Task 3).
- Other props in the canopy area: neighbouring `ForestProp`s are on layer 128 too and must not trigger fade. Covered by `test_fade_ignores_props` (Task 3).
- Enemies vs props: enemies use nav blockers, not physics; they must still route around and stop at trunks and rocks. Checked in Task 4.

---

### Task 1: Trim forest content, recolour to DB32, lower density

**Files:**
- Modify: 7 PNGs under the art root (in place)
- Modify: `assets/biomes/caves.tres` (ext_resources 30–43, prop sub_resources, `Resource_forest`)
- Test: `tests/unit/test_caves_biome_decor.gd`

**Interfaces:**
- Produces: caves `tree_defs` = 5 defs, families `round`/`pine`; `rock_defs` = 2 defs (`trunk_radius` 12, 24); `secondary_groups = 1`, `rock_attempts = 1`.

- [ ] **Step 1: Write the failing test** `test_caves_forest_trimmed_and_db32` in `test_caves_biome_decor.gd`. Keep the existing test, but replace its `roles.has(...)` checks only if they break. They shouldn't, because roles stay bright/dark/odd.

```gdscript
const DB32 := ["000000","222034","45283c","663931","8f563b","df7126","d9a066","eec39a","fbf236","99e550","6abe30","37946e","4b692f","524b24","323c39","3f3f74","306082","5b6ee1","639bff","5fcde4","cbdbfc","ffffff","9badb7","847e87","696a6a","595652","76428a","ac3232","d95763","d77bba","8f974a","8a6f30"]

func test_caves_forest_trimmed_and_db32() -> void:
	var forest: ForestDef = (load("res://assets/biomes/caves.tres") as BiomeDef).forest
	assert_int(forest.tree_defs.size()).is_equal(5)
	assert_int(forest.rock_defs.size()).is_equal(2)
	assert_int(forest.secondary_groups).is_equal(1)
	assert_int(forest.rock_attempts).is_equal(1)
	var families := {}
	for def in forest.tree_defs:
		assert_str(def.texture.resource_path).contains("/Trees/Colour1/")
		families[def.family] = true
	assert_array(families.keys()).contains_exactly_in_any_order(["round", "pine"])
	for def in forest.tree_defs + forest.rock_defs:
		var img: Image = def.texture.get_image()
		img.decompress()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0:
					assert_bool(DB32.has(c.to_html(false))).override_failure_message(
						"%s (%d,%d) %s" % [def.texture.resource_path, x, y, c.to_html(false)]).is_true()
```

(`tree_defs + rock_defs` concatenates two typed arrays; if GDScript rejects it, loop over each array.) If the pixel loop floods failures, stop at the first failure per texture.

- [ ] **Step 2: Run it and expect FAIL** (there are currently 11 trees, `secondary_groups` is 2, and the colours aren't DB32).

- [ ] **Step 3: Recolour the 7 PNGs in place** (run from the art root):

```bash
MAP="150E13:000000 211B2B:222034 3F1A28:45283c 5E3B30:663931 8D6A2B:8a6f30 2D440E:323c39 4C7615:4b692f 79A40F:6abe30 504057:595652 757A8B:847e87 A0ACB8:9badb7"
args=(); for m in $MAP; do args+=(-fill "#${m#*:}" -opaque "#${m%:*}"); done
for f in Trees/Colour1/160x160Trees_{3,4,8}.png Trees/Colour1/96x128Tree_{6,10}.png Rocks/Colour1/64x64pxRocks_2.png Rocks/Colour1/96x96pxRocks_3.png; do
  magick "$f" -fuzz 0 "${args[@]}" "PNG32:$f"
done
```

- [ ] **Step 4: Rewrite the prop content in `caves.tres`.** Remove ext_resources 30–43 and their sub_resources, then add:

| sub_resource id | texture | role | family | other |
|---|---|---|---|---|
| `Resource_tree_round_a` | `Trees/Colour1/160x160Trees_4.png` | bright | round | hp 12 |
| `Resource_tree_round_b` | `Trees/Colour1/160x160Trees_3.png` | dark | round | |
| `Resource_tree_round_c` | `Trees/Colour1/96x128Tree_6.png` | odd | round | hp 8 |
| `Resource_tree_pine_a` | `Trees/Colour1/160x160Trees_8.png` | any | pine | |
| `Resource_tree_pine_b` | `Trees/Colour1/96x128Tree_10.png` | any | pine | hp 8 |
| `Resource_rock_small` | `Rocks/Colour1/64x64pxRocks_2.png` | | | kind rock, hp 16, trunk_radius 12 |
| `Resource_rock_large` | `Rocks/Colour1/96x96pxRocks_3.png` | | | kind rock, hp 24, trunk_radius 24 |

Copy the uid of each texture from its `.png.import` file. Keep any `tint` the old defs set. In `Resource_forest`, set `secondary_groups = 1` and `rock_attempts = 1`, and point the two arrays at the new sub_resources. Don't touch the edge-rock ext_resources 44–46.

- [ ] **Step 5: Run `test_caves_biome_decor.gd`, `test_forest_planner.gd`, `test_floor_chunk.gd` and `test_floor_chunk_decor_lights.gd`. Expect PASS.** If a planner or floor-chunk test reads caves content and breaks because there are now fewer defs, update its expected value; don't change planner code.

- [ ] **Step 6: Commit**

```bash
git add textures/Assets/NaturalDecorsTreesAndRocksv1 assets/biomes/caves.tres tests/unit/test_caves_biome_decor.gd
git commit -m "feat(caves): trim forest to Colour1 round+pine, DB32 recolour, lower density"
```

### Task 2: Props collide with the player via a `prop_body` layer

**Files:**
- Modify: `project.godot` (`[layer_names]`), `src/props/forest_prop.gd:44`, `src/player/player_controller.gd:64`, `scenes/player.tscn:23`
- Test: `tests/unit/test_forest_prop.gd:55-60`

**Interfaces:**
- Produces: `ForestProp.collision_layer == 144`. The player's mask is 19.

- [ ] **Step 1: Update `test_setup_layers_and_groups`** to `assert_int(prop.collision_layer).is_equal(144)`, and add:

```gdscript
func test_player_mask_hits_props_not_enemies() -> void:
	var player = auto_free(load("res://scenes/player.tscn").instantiate())
	add_child(player)  # _ready sets the mask
	assert_int(player.collision_mask & 16).is_equal(16)
	assert_int(player.collision_mask & 4).is_equal(0)
```

If instancing the player in a test drags in autoloads that break headless runs, drop this test and rely on the Task 4 check.

- [ ] **Step 2: Run `test_forest_prop.gd`. Expect FAIL** (the layer is 132 and the mask is 3).

- [ ] **Step 3: Implement.** Add `2d_physics/layer_5="prop_body"` to `project.godot`. Set the `ForestProp` layer to `144  # prop_body | attackable_hit`, update the class comment to match, and drop `enemy_body`. Set the player's `collision_mask = 19  # terrain | pickups | prop_body` in `player_controller.gd`, and `collision_mask = 19` in `player.tscn`.

- [ ] **Step 4: Run `test_forest_prop.gd`. Expect PASS.**

- [ ] **Step 5: Commit** with the message `fix(props): forest props block the player via prop_body layer`.

### Task 3: Trees fade when an actor is behind the canopy

**Files:**
- Modify: `src/props/forest_prop.gd`
- Test: `tests/unit/test_forest_prop.gd`

**Interfaces:**
- Produces, on `ForestProp`:
  - `const FADE_ALPHA := 0.4`
  - `func is_faded() -> bool`
  - `func _on_canopy_body_entered(body: Node2D) -> void`
  - `func _on_canopy_body_exited(body: Node2D) -> void`
  - a child `Area2D` named `"CanopyArea"`, trees only

- [ ] **Step 1: Write the failing tests.** `_make_def()` builds a tree. Use a `CharacterBody2D.new()` as the actor and a second `ForestProp` as the prop.

```gdscript
func test_canopy_area_only_on_trees() -> void:
	var tree := auto_free(ForestProp.new()); tree.setup(_make_def(), "1:0:0:10")
	var area: Area2D = tree.get_node("CanopyArea")
	assert_int(area.collision_mask).is_equal(128)
	assert_bool(area.monitorable).is_false()
	var rock_def := _make_def(); rock_def.kind = "rock"
	var rock := auto_free(ForestProp.new()); rock.setup(rock_def, "1:0:0:11")
	assert_object(rock.get_node_or_null("CanopyArea")).is_null()

func test_fade_counts_occluders() -> void:
	# setup tree, actors a and b
	tree._on_canopy_body_entered(a); tree._on_canopy_body_entered(b)
	assert_bool(tree.is_faded()).is_true()
	tree._on_canopy_body_exited(a)
	assert_bool(tree.is_faded()).is_true()
	tree._on_canopy_body_exited(b)
	assert_bool(tree.is_faded()).is_false()

func test_fade_ignores_props() -> void:
	tree._on_canopy_body_entered(other_forest_prop)
	assert_bool(tree.is_faded()).is_false()

func test_hit_flash_keeps_fade() -> void:
	# tree in a scene tree, actor entered
	tree.take_dig_hit(Vector2.ONE, Vector2.RIGHT, 0.0)
	assert_float(tree.get_node("Sprite2D").self_modulate.a).is_less(1.0)  # after the fade tween target applies
```

For `test_hit_flash_keeps_fade`, set `self_modulate.a` instantly when the tree is not inside the tree (same pattern as the existing `is_inside_tree()` guard on tweens), so the assertion is deterministic.

- [ ] **Step 2: Run `test_forest_prop.gd`. Expect FAIL.**

- [ ] **Step 3: Implement in `ForestProp`.**
  - In `setup()`, for trees, build `CanopyArea` with `collision_layer = 0`, `collision_mask = 128`, `monitorable = false`, and a `RectangleShape2D` sized to the opaque sprite above the trunk: width `tex_w * 0.6`, from the sprite top down to `y = -trunk_radius`.
  - Connect `body_entered`/`body_exited` to the handlers.
  - The handlers ignore bodies that are `ForestProp` and keep a count of occluders. When the count crosses 0↔1, tween `_sprite.self_modulate.a` to `FADE_ALPHA`/`1.0` over 0.15s, or set it directly when not inside the tree.
  - `is_faded()` returns `count > 0`.
  - The hit flash stays on `modulate` and doesn't change.

- [ ] **Step 4: Run `test_forest_prop.gd`. Expect PASS.**

- [ ] **Step 5: Commit** with the message `feat(props): trees fade while an actor is behind the canopy`.

### Task 4: In-game verification

- [ ] **Step 1: Run the full suite** (`-a res://tests`) and expect it to pass apart from failures that already existed. Compare against `master` if anything fails.
- [ ] **Step 2: Launch the game** (use the `run` skill), go into the caves, and confirm each of these, with a screenshot of each:
  - (a) Forests are visibly sparser, and only round trees and pines appear.
  - (b) The player stops at a tree trunk and at both rock sizes.
  - (c) The player still passes through enemies.
  - (d) Enemies stop at and route around trunks and rocks.
  - (e) A tree fades while the player or an enemy is behind it and restores once they leave.
  - (f) Digging a faded tree keeps it faded.
- [ ] **Step 3: If (d) fails,** debug the nav blocker path (`ForestProp._enter_tree` → `PassabilityGrid.add_blocker`) using superpowers:systematic-debugging. Don't put enemies on the physics layer.
