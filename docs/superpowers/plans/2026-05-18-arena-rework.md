# Elite + Boss Arena Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink elite (r=224→140) and boss (r=960→300) arenas, pack each variant with terrain features (pillars + pools + barrels + vents) for a "crammed together" feel, and give each variant a distinct identity.

**Architecture:** All changes are in the composition generator (`tools/generate_arena_compositions.gd`) plus two new stub prop scenes. After edits, re-run the generator headless to overwrite all `.tres` files under `assets/arenas/{elite,boss}/`. No changes to feature classes, dispatcher, or composition resource format.

**Tech Stack:** Godot 4 (GDScript), `ResourceSaver`, existing `ArenaFeature` subclasses.

**Spec:** `docs/superpowers/specs/2026-05-18-arena-rework-design.md`

---

## File Structure

- **Create:** `scenes/props/barrel.tscn` — stub barrel prop (Node2D + Sprite2D, placeholder texture)
- **Create:** `scenes/props/vent.tscn` — stub vent prop (Node2D + Sprite2D, placeholder texture)
- **Modify:** `tools/generate_arena_compositions.gd` — dimensions, new helpers, all variant builders
- **Regenerate (output):** `assets/arenas/elite/{caves,mines,magma,frozen,vault}_{a,b,c}.tres` (15 files)
- **Regenerate (output):** `assets/arenas/boss/{caves,mines,magma,frozen,vault}_{a,b,c,d}.tres` (20 files)

---

## Task 1: Create stub barrel + vent prop scenes

**Files:**
- Create: `scenes/props/barrel.tscn`
- Create: `scenes/props/vent.tscn`

Both scenes are Node2D + Sprite2D with `PlaceholderTexture2D` for now (clearly visible placeholder; will be replaced when real props are designed). No collision, no script — purely visual stubs so `spawn_prop()` has something to instantiate.

- [ ] **Step 1: Create scenes/props directory**

Run: `mkdir -p /mnt/windows/Godot/top-down-rogue/scenes/props`
Expected: directory created (or already exists)

- [ ] **Step 2: Write barrel.tscn**

Create `scenes/props/barrel.tscn` with this exact content:

```
[gd_scene format=3 uid="uid://barrel_stub_0001"]

[sub_resource type="PlaceholderTexture2D" id="PlaceholderTexture2D_barrel"]
size = Vector2(16, 20)

[node name="Barrel" type="Node2D"]

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.6, 0.35, 0.15, 1)
texture = SubResource("PlaceholderTexture2D_barrel")
```

- [ ] **Step 3: Write vent.tscn**

Create `scenes/props/vent.tscn` with this exact content:

```
[gd_scene format=3 uid="uid://vent_stub_0001"]

[sub_resource type="PlaceholderTexture2D" id="PlaceholderTexture2D_vent"]
size = Vector2(20, 20)

[node name="Vent" type="Node2D"]

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.4, 0.4, 0.5, 1)
texture = SubResource("PlaceholderTexture2D_vent")
```

- [ ] **Step 4: Verify Godot accepts the scenes**

Run: `cd /mnt/windows/Godot/top-down-rogue && godot --headless --quit 2>&1 | tail -20`
Expected: no errors mentioning `scenes/props/barrel.tscn` or `scenes/props/vent.tscn`. If `.import` files are missing, Godot will create them on first open.

- [ ] **Step 5: Commit**

```bash
cd /mnt/windows/Godot/top-down-rogue
git add scenes/props/barrel.tscn scenes/props/vent.tscn scenes/props/barrel.tscn.uid scenes/props/vent.tscn.uid 2>/dev/null || git add scenes/props/
git commit -m "feat: stub barrel and vent prop scenes for arena composition"
```

---

## Task 2: Update generator helpers and dimensions

**Files:**
- Modify: `tools/generate_arena_compositions.gd`

Add new helpers `_barrels`, `_vent`. Extend `_pool` to accept blob-size args. Define dimension constants for elite and boss.

- [ ] **Step 1: Add scene preload constants at top of file**

In `tools/generate_arena_compositions.gd`, add the following preloads after the existing `ArenaRegion` preload (around line 5):

```gdscript
const BARREL_SCENE = preload("res://scenes/props/barrel.tscn")
const VENT_SCENE = preload("res://scenes/props/vent.tscn")
const MELEE_ENEMY_SCENE = preload("res://scenes/enemies/melee_enemy.tscn")
const BOSS_ENEMY_SCENE = preload("res://scenes/enemies/boss_enemy.tscn")

# Arena-kind dimensions
const ELITE_NOMINAL_R := 140
const ELITE_LOBING := 30
const ELITE_INNER_DISC := 30
const BOSS_NOMINAL_R := 300
const BOSS_LOBING := 50
const BOSS_INNER_DISC := 80

# Pool blob sizes (cells)
const ELITE_POOL_MIN := 3
const ELITE_POOL_MAX := 6
const BOSS_POOL_MIN := 5
const BOSS_POOL_MAX := 10
```

- [ ] **Step 2: Replace the `_pool` helper to accept size range**

Replace the existing `_pool` function (around lines 63-70) with:

```gdscript
static func _pool(center: Vector2, radius: float, mat: int, count: int, size_min: int, size_max: int) -> ArenaFeature.FeaturePoolPatch:
	var f := ArenaFeature.FeaturePoolPatch.new()
	f.region = _disc(center, radius)
	f.material_id = mat
	f.count = count
	f.size_min_cells = size_min
	f.size_max_cells = size_max
	return f

static func _pool_ring(r_min: float, r_max: float, mat: int, count: int, size_min: int, size_max: int) -> ArenaFeature.FeaturePoolPatch:
	var f := ArenaFeature.FeaturePoolPatch.new()
	f.region = _ring(r_min, r_max)
	f.material_id = mat
	f.count = count
	f.size_min_cells = size_min
	f.size_max_cells = size_max
	return f
```

Note: existing callers in old variant builders are about to be rewritten in Tasks 3-4, so don't worry about stale call sites.

- [ ] **Step 3: Add `_barrels` and `_vent` helpers**

After the `_pool_ring` function added in Step 2, add:

```gdscript
static func _barrels_ring(count: int, r_min: float, r_max: float) -> ArenaFeature.FeatureBarrelCluster:
	var f := ArenaFeature.FeatureBarrelCluster.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.barrel_scene = BARREL_SCENE
	return f

static func _barrels_disc(center: Vector2, radius: float, count: int) -> ArenaFeature.FeatureBarrelCluster:
	var f := ArenaFeature.FeatureBarrelCluster.new()
	f.region = _disc(center, radius)
	f.count = count
	f.barrel_scene = BARREL_SCENE
	return f

static func _vent(center: Vector2, radius: float, count: int = 1) -> ArenaFeature.FeatureVent:
	var f := ArenaFeature.FeatureVent.new()
	f.region = _disc(center, radius)
	f.count = count
	f.vent_scene = VENT_SCENE
	return f
```

Note: `ArenaFeature.FeatureBarrelCluster` and `ArenaFeature.FeatureVent` are inner-class references — if those don't resolve (because the feature classes are top-level `class_name`s, not inner classes), use bare `FeatureBarrelCluster.new()` / `FeatureVent.new()` instead. Check the existing `_pillars` helper for the pattern in use: if it says `ArenaFeature.FeaturePillarCluster`, keep the prefix; if it says `FeaturePillarCluster`, drop the prefix consistently.

- [ ] **Step 4: Update `_enemies` to use the preloaded scene constant**

Replace the body of the existing `_enemies` helper (around lines 55-62) so `f.enemy_scene` uses the constant:

```gdscript
static func _enemies(count: int, r_min: float, r_max: float, is_elite: bool) -> ArenaFeature.FeatureEnemyPack:
	var f := ArenaFeature.FeatureEnemyPack.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.is_elite = is_elite
	f.enemy_scene = MELEE_ENEMY_SCENE
	return f
```

And update `_boss` similarly:

```gdscript
static func _boss() -> ArenaFeature.FeatureBossSpawn:
	var b := ArenaFeature.FeatureBossSpawn.new()
	b.region = _point()
	b.boss_scene = BOSS_ENEMY_SCENE
	return b
```

- [ ] **Step 5: Verify generator still parses (don't run it yet)**

Run: `cd /mnt/windows/Godot/top-down-rogue && godot --headless --check-only --script tools/generate_arena_compositions.gd 2>&1 | tail -10`

Expected: no parse errors. If `--check-only` is unsupported on your Godot version, skip this — Tasks 3-5 will exercise the code.

- [ ] **Step 6: Commit**

```bash
cd /mnt/windows/Godot/top-down-rogue
git add tools/generate_arena_compositions.gd
git commit -m "refactor: add barrel/vent helpers and dimension constants to arena generator"
```

---

## Task 3: Rewrite elite variant builders

**Files:**
- Modify: `tools/generate_arena_compositions.gd`

Replace `_build_elite_a`, `_build_elite_b`, `_build_elite_c` with new bodies. Each variant: chest + 1-2 elites + 5-6 pillars + 2 pools (or vault substitution) + 4-5 barrel clusters.

- [ ] **Step 1: Replace `_build_elite_a` ("Hazard heart")**

Replace the existing `_build_elite_a` function with:

```gdscript
static func _build_elite_a(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"
	c.biome = biome
	c.variant_id = &"a"
	c.nominal_radius = ELITE_NOMINAL_R
	c.lobing_amplitude = ELITE_LOBING
	c.inner_disc_radius = ELITE_INNER_DISC
	var chest_feature := ArenaFeature.FeatureChestSpawn.new()
	chest_feature.rare = false
	c.features = [
		chest_feature,
		_enemies(2, 80, 130, true),
		_pillars(5, 70, 130, p["pillar_mat"]),
		_barrels_ring(2, 40, 90),
		_barrels_disc(Vector2(0, 60), 30, 1),
		_barrels_disc(Vector2(0, -60), 30, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(0, 0), 40, p["pool_mat"], 2, ELITE_POOL_MIN, ELITE_POOL_MAX))
	else:
		# vault: extra pillars instead of pools
		c.features.append(_pillars(2, 50, 100, p["pillar_mat"]))
	return c
```

- [ ] **Step 2: Replace `_build_elite_b` ("Pillar grove")**

Replace the existing `_build_elite_b` function with:

```gdscript
static func _build_elite_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = ELITE_NOMINAL_R
	c.lobing_amplitude = ELITE_LOBING
	c.inner_disc_radius = ELITE_INNER_DISC
	var chest_feature := ArenaFeature.FeatureChestSpawn.new()
	chest_feature.rare = false
	c.features = [
		chest_feature,
		_enemies(2, 60, 120, true),
		_pillars(7, 30, 130, p["pillar_mat"]),
		_barrels_ring(2, 50, 110),
		_barrels_disc(Vector2(-50, 0), 30, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(60, -40), 40, p["pool_mat"], 2, ELITE_POOL_MIN, ELITE_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(60, -40), 30, 2))
	return c
```

- [ ] **Step 3: Replace `_build_elite_c` ("Barrel field")**

Replace the existing `_build_elite_c` function with:

```gdscript
static func _build_elite_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = ELITE_NOMINAL_R
	c.lobing_amplitude = ELITE_LOBING
	c.inner_disc_radius = ELITE_INNER_DISC
	var chest_feature := ArenaFeature.FeatureChestSpawn.new()
	chest_feature.rare = false
	c.features = [
		chest_feature,
		_enemies(2, 70, 130, true),
		_pillars(5, 90, 130, p["pillar_mat"]),
		_barrels_ring(2, 30, 70),
		_barrels_ring(2, 70, 110),
		_barrels_disc(Vector2(0, 0), 25, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(-50, 0), 35, p["pool_mat"], 1, ELITE_POOL_MIN, ELITE_POOL_MAX))
		c.features.append(_pool(Vector2(50, 0), 35, p["pool_mat"], 1, ELITE_POOL_MIN, ELITE_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(-50, 0), 30, 1))
		c.features.append(_vent(Vector2(50, 0), 20, 1))
	return c
```

- [ ] **Step 4: Commit**

```bash
cd /mnt/windows/Godot/top-down-rogue
git add tools/generate_arena_compositions.gd
git commit -m "feat: rewrite elite arena variants with dense feature packs"
```

---

## Task 4: Rewrite boss variant builders

**Files:**
- Modify: `tools/generate_arena_compositions.gd`

Replace `_build_variant_a..d` with new boss variants. Each: boss + 6-8 pillars + 2 pools + 3-4 barrel clusters + 4-5 enemy packs.

- [ ] **Step 1: Replace `_build_variant_a` ("Hazard ring")**

Replace the existing `_build_variant_a` function with:

```gdscript
static func _build_variant_a(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"
	c.biome = biome
	c.variant_id = &"a"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		_pillars(7, 180, 280, p["pillar_mat"]),
		_enemies(3, 100, 200, false),
		_enemies(1, 150, 250, true),
		_enemies(1, 220, 280, false),
		_barrels_disc(Vector2(-180, -120), 50, 3),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool_ring(80, 160, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_barrels_ring(3, 80, 160))
		c.features.append(_pillars(2, 100, 160, p["pillar_mat"]))
	return c
```

- [ ] **Step 2: Replace `_build_variant_b` ("Pillar maze")**

Replace the existing `_build_variant_b` function with:

```gdscript
static func _build_variant_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		_pillars(4, 150, 280, p["pillar_mat"]),
		# pillar grove pocket
		ArenaFeature.FeaturePillarCluster.new(),
		_enemies(3, 120, 220, false),
		_enemies(2, 180, 280, true),
		_barrels_ring(2, 100, 180),
		_barrels_disc(Vector2(150, 100), 40, 2),
	]
	# fill the pillar grove pocket (index 2)
	var grove: ArenaFeature.FeaturePillarCluster = c.features[2]
	grove.region = _disc(Vector2(-120, 80), 60)
	grove.count = 4
	grove.pillar_radius_cells = 10
	grove.spacing_min = 64.0
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(220, -180), 60, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(220, -180), 50, 2))
		c.features.append(_pillars(2, 200, 260, p["pillar_mat"]))
	return c
```

- [ ] **Step 3: Replace `_build_variant_c` ("Explosive yard")**

Replace the existing `_build_variant_c` function with:

```gdscript
static func _build_variant_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		_pillars(6, 200, 280, p["pillar_mat"]),
		_enemies(3, 120, 220, false),
		_enemies(1, 180, 260, true),
		_barrels_ring(3, 80, 180),
		_barrels_ring(2, 180, 280),
		_vent(Vector2(0, 0), 50, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(-150, 150), 50, p["pool_mat"], 1, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(150, -150), 50, p["pool_mat"], 1, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(-150, 150), 50, 2))
		c.features.append(_barrels_disc(Vector2(150, -150), 50, 2))
	return c
```

- [ ] **Step 4: Replace `_build_variant_d` ("Vent crucible")**

Replace the existing `_build_variant_d` function with:

```gdscript
static func _build_variant_d(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"d"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		_pillars(6, 180, 280, p["pillar_mat"]),
		_enemies(3, 100, 200, false),
		_enemies(1, 180, 260, true),
		_vent(Vector2(100, -80), 30, 1),
		_vent(Vector2(-100, 80), 30, 1),
		_barrels_ring(3, 100, 200),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool_ring(60, 150, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_pillars(2, 60, 150, p["pillar_mat"]))
		c.features.append(_barrels_ring(2, 60, 150))
	return c
```

- [ ] **Step 5: Commit**

```bash
cd /mnt/windows/Godot/top-down-rogue
git add tools/generate_arena_compositions.gd
git commit -m "feat: rewrite boss arena variants with dense pockets and ring fill"
```

---

## Task 5: Regenerate compositions and verify

**Files:**
- Regenerate: `assets/arenas/elite/*.tres` (15 files)
- Regenerate: `assets/arenas/boss/*.tres` (20 files)

- [ ] **Step 1: Run the generator headless**

Run:
```bash
cd /mnt/windows/Godot/top-down-rogue
godot --headless -s tools/generate_arena_compositions.gd 2>&1 | tail -50
```

Expected: 35 `Wrote ... — OK` lines and `Done generating compositions.` at the end. No errors. If you see errors about feature class names (e.g. `ArenaFeature.FeatureBarrelCluster` not found), recheck Task 2 Step 3's note about top-level vs inner-class names and adjust.

- [ ] **Step 2: Verify file count**

Run:
```bash
ls /mnt/windows/Godot/top-down-rogue/assets/arenas/elite/*.tres | wc -l
ls /mnt/windows/Godot/top-down-rogue/assets/arenas/boss/*.tres | wc -l
```

Expected: `15` and `20`.

- [ ] **Step 3: Verify every variant has the new dimensions**

Run:
```bash
grep -L "nominal_radius = 140" /mnt/windows/Godot/top-down-rogue/assets/arenas/elite/*.tres
grep -L "nominal_radius = 300" /mnt/windows/Godot/top-down-rogue/assets/arenas/boss/*.tres
```

Expected: both commands print nothing (every elite file has r=140, every boss file has r=300).

- [ ] **Step 4: Verify every variant references barrels**

Run:
```bash
grep -L "feature_barrel_cluster" /mnt/windows/Godot/top-down-rogue/assets/arenas/elite/*.tres
grep -L "feature_barrel_cluster" /mnt/windows/Godot/top-down-rogue/assets/arenas/boss/*.tres
```

Expected: both commands print nothing — every composition now contains at least one barrel cluster feature.

- [ ] **Step 5: Verify non-vault variants reference pools**

Run:
```bash
for biome in caves mines magma frozen; do
  for f in /mnt/windows/Godot/top-down-rogue/assets/arenas/elite/${biome}_*.tres /mnt/windows/Godot/top-down-rogue/assets/arenas/boss/${biome}_*.tres; do
    grep -q "feature_pool_patch" "$f" || echo "MISSING POOL: $f"
  done
done
```

Expected: no `MISSING POOL` lines. All caves/mines/magma/frozen variants reference pool patches.

- [ ] **Step 6: Verify vault variants do NOT reference pools**

Run:
```bash
grep -l "feature_pool_patch" /mnt/windows/Godot/top-down-rogue/assets/arenas/elite/vault_*.tres /mnt/windows/Godot/top-down-rogue/assets/arenas/boss/vault_*.tres
```

Expected: prints nothing — vault uses substitutions, never pools.

- [ ] **Step 7: Smoke-test in game**

Launch the game and travel to an elite room and a boss room (use cheat commands if available, e.g. via the cheat system added in `2026-04-26-cheat-command-system-design.md`).

Expected observations:
- Elite arena is visibly smaller than before (r=140 vs old 224).
- Boss arena is visibly smaller (r=300 vs old 960), still notably bigger than elite.
- Each arena has multiple pillars, at least one pool of biome-appropriate material (lava in caves/mines/magma, water in frozen — except vault), and visible barrel clusters (placeholder colored rectangles).
- Variants across the same biome look different (e.g., loading `caves_a` elite three times in a row will look the same; but `caves_a` vs `caves_b` vs `caves_c` should differ in arrangement).

If you can't easily revisit a specific variant, just confirm: most elite/boss rooms now look noticeably busier than before.

- [ ] **Step 8: Commit regenerated assets**

```bash
cd /mnt/windows/Godot/top-down-rogue
git add assets/arenas/elite/*.tres assets/arenas/boss/*.tres
git commit -m "chore: regenerate arena compositions with new dense variants"
```

---

## Out of scope (not in this plan)

- Replacing placeholder barrel/vent sprites with real art (separate plan).
- Adding barrel/vent gameplay behavior (destructible, exploding, damaging). Stubs are visual-only.
- Per-biome variant differences beyond pool material / pillar material rules.
- Automated unit tests for composition content (current `test_arena_composition.gd` already covers the resource format; adding per-variant snapshot tests is overkill for static generated assets).
