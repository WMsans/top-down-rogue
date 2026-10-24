# Spawn Room Shrink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the guidance room an 80px-radius circle with no signs and lanterns pulled in, and have the player/camera start inside it on frame one.

**Architecture:** Room shape is pure data in `guidance_room_composition.tres`. Spawn fix pre-places the player at the guidance center before the chunk-load await, then snaps the camera.

**Tech Stack:** Godot 4 / GDScript, gdUnit4.

**Spec:** `docs/superpowers/specs/2026-10-24-spawn-room-shrink-design.md`

## Global Constraints

- Room radius 80px: `nominal_radius`, `inner_disc_radius`, floor `radius` = 80; wood wall 72 / 80.
- Lantern offsets ±40; `light_radius` stays 200.
- Sign textures stay on disk; only references removed.

## Review Focus

- Composition loads with no broken ext_resource after plaque removal → pinned by Task 1 test (load + feature check).
- Player placed at the room on the very first frame (before chunks load) → manual check in Task 2 (minimap shows no reveal at (0,0)).
- Camera doesn't pan from (0,0) on start → manual check in Task 2.
- Lanterns don't overlap the wall (diagonal 40√2 ≈ 57 < 72) → pinned by Task 1 test.
- Spawn pocket search still lands inside the 72px wall → manual check in Task 2.

---

### Task 1: Shrink guidance composition

**Files:**
- Modify: `assets/arenas/guidance/guidance_room_composition.tres`
- Test: `tests/unit/test_guidance_room_composition.gd` (create)

- [ ] **Step 1: Write the failing test** `test_guidance_room_is_small_and_signless`:
  load the tres; assert `nominal_radius == 80`, `inner_disc_radius == 80`; no feature `is FeaturePlaqueSet`; the `FeatureFloorOverlay` has `radius == 80`; the `FeatureWoodWall` has `inner_radius == 72`, `outer_radius == 80`; every `LanternSpec` in the cluster has `offset.length() < 72`.
- [ ] **Step 2: Run it, expect FAIL**
  `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/unit/test_guidance_room_composition.gd`
- [ ] **Step 3: Edit the tres** per Global Constraints; delete the plaque set and the three plaque sub-resources, the ext_resources `4_plaque`, `6_pspec`, `9_goal`, `10_move`, `11_attack`, and the plaque entry in `features`.
- [ ] **Step 4: Run the test, expect PASS**
- [ ] **Step 5: Commit** `feat(guidance): shrink spawn room to 80px, drop signs`

### Task 2: Spawn player directly in the room

**Files:**
- Modify: `src/player/player_controller.gd:76-85`

- [ ] **Step 1:** Set `position = Vector2(guidance_center)` right after `_find_guidance_room_center()` (before the chunk await).
- [ ] **Step 2:** After the final `position = …` from `find_spawn_position`, call `reset_smoothing()` on the `Camera2D` child (`get_node_or_null("Camera2D")`).
- [ ] **Step 3: Verify** — run the full test suite (`-a res://tests`), expect no new failures. Then launch the game: player and camera start in the small room, no camera pan, minimap shows no revealed patch away from the room.
- [ ] **Step 4: Commit** `fix(player): spawn directly in guidance room`
