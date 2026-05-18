extends SceneTree

const ArenaComposition = preload("res://src/core/arena_composition.gd")
const ArenaFeature = preload("res://src/core/arena_feature.gd")
const ArenaRegion = preload("res://src/core/arena_region.gd")

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

# NOTE: must match the order in src/autoload/material_registry.gd::_init_materials
const MAT_AIR := 0
const MAT_WOOD := 1
const MAT_STONE := 2
const MAT_GAS := 3
const MAT_LAVA := 4
const MAT_DIRT := 5
const MAT_COAL := 6
const MAT_ICE := 7
const MAT_WATER := 8

static func _biome_params(biome: StringName) -> Dictionary:
	match biome:
		&"caves":  return {"pillar_mat": MAT_STONE, "pool_mat": MAT_LAVA}
		&"mines":  return {"pillar_mat": MAT_WOOD,  "pool_mat": MAT_LAVA}
		&"magma":  return {"pillar_mat": MAT_STONE, "pool_mat": MAT_LAVA}
		&"frozen": return {"pillar_mat": MAT_ICE,   "pool_mat": MAT_WATER}
		&"vault":  return {"pillar_mat": MAT_STONE, "pool_mat": -1}
	return {}

static func _ring(r_min: float, r_max: float) -> RegionRing:
	var r := RegionRing.new()
	r.center = Vector2.ZERO
	r.r_min = r_min
	r.r_max = r_max
	return r

static func _disc(center: Vector2, radius: float) -> RegionDisc:
	var d := RegionDisc.new()
	d.center = center
	d.radius = radius
	return d

static func _point(pos: Vector2 = Vector2.ZERO) -> RegionPoint:
	var p := RegionPoint.new()
	p.offset = pos
	return p

static func _boss() -> FeatureBossSpawn:
	var b := FeatureBossSpawn.new()
	b.region = _point()
	b.boss_scene = BOSS_ENEMY_SCENE
	return b

# Default boss-pillar radii: ~3x the old 10-cell pillars, with wide variation
# and a bias toward the larger end.
const PILLAR_R_MIN := 18
const PILLAR_R_MAX := 42
const PILLAR_LARGE_BIAS := 0.7
# Pillar centers may be as close as 0.6 * max_radius — produces heavy overlap so
# clusters merge into irregular blob shapes instead of looking like a grid of discs.
const PILLAR_OVERLAP_FACTOR := 0.6

# Grove pillars are slightly smaller so dense pockets still pack, and overlap even more.
const GROVE_R_MIN := 14
const GROVE_R_MAX := 32
const GROVE_OVERLAP_FACTOR := 0.45

static func _pillars(count: int, r_min: float, r_max: float, _pillar_mat: int) -> FeaturePillarCluster:
	var f := FeaturePillarCluster.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.radius_min = PILLAR_R_MIN
	f.radius_max = PILLAR_R_MAX
	f.large_bias = PILLAR_LARGE_BIAS
	f.center_distance_factor = PILLAR_OVERLAP_FACTOR
	return f

static func _pillars_small(count: int, r_min: float, r_max: float) -> FeaturePillarCluster:
	var f := FeaturePillarCluster.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.radius_min = 8
	f.radius_max = 16
	f.large_bias = 0.5
	f.center_distance_factor = 0.8
	return f

static func _pillars_disc(center: Vector2, radius: float, count: int) -> FeaturePillarCluster:
	var f := FeaturePillarCluster.new()
	f.region = _disc(center, radius)
	f.count = count
	f.radius_min = GROVE_R_MIN
	f.radius_max = GROVE_R_MAX
	f.large_bias = 0.5
	f.center_distance_factor = GROVE_OVERLAP_FACTOR
	return f

static func _enemies(count: int, r_min: float, r_max: float, is_elite: bool) -> FeatureEnemyPack:
	var f := FeatureEnemyPack.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.is_elite = is_elite
	f.enemy_scene = MELEE_ENEMY_SCENE
	return f

static func _pool(center: Vector2, radius: float, mat: int, count: int, size_min: int, size_max: int) -> FeaturePoolPatch:
	var f := FeaturePoolPatch.new()
	f.region = _disc(center, radius)
	f.material_id = mat
	f.count = count
	f.size_min_cells = size_min
	f.size_max_cells = size_max
	return f

static func _pool_ring(r_min: float, r_max: float, mat: int, count: int, size_min: int, size_max: int) -> FeaturePoolPatch:
	var f := FeaturePoolPatch.new()
	f.region = _ring(r_min, r_max)
	f.material_id = mat
	f.count = count
	f.size_min_cells = size_min
	f.size_max_cells = size_max
	return f

static func _barrels_ring(count: int, r_min: float, r_max: float) -> FeatureBarrelCluster:
	var f := FeatureBarrelCluster.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.barrel_scene = BARREL_SCENE
	return f

static func _barrels_disc(center: Vector2, radius: float, count: int) -> FeatureBarrelCluster:
	var f := FeatureBarrelCluster.new()
	f.region = _disc(center, radius)
	f.count = count
	f.barrel_scene = BARREL_SCENE
	return f

static func _vent(center: Vector2, radius: float, count: int = 1) -> FeatureVent:
	var f := FeatureVent.new()
	f.region = _disc(center, radius)
	f.count = count
	f.vent_scene = VENT_SCENE
	return f

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
		# Pillar bands covering full annular area (r=80..300)
		_pillars(10, 90, 150, p["pillar_mat"]),
		_pillars(12, 150, 220, p["pillar_mat"]),
		_pillars(14, 220, 290, p["pillar_mat"]),
		# Enemies
		_enemies(4, 100, 200, false),
		_enemies(2, 150, 250, true),
		_enemies(2, 220, 290, false),
		# Barrel pockets all around the arena
		_barrels_disc(Vector2(-180, -120), 60, 5),
		_barrels_disc(Vector2(180, 120), 60, 5),
		_barrels_disc(Vector2(-200, 180), 50, 3),
		_barrels_disc(Vector2(200, -180), 50, 3),
		_barrels_ring(6, 90, 160),
		_barrels_ring(6, 220, 290),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool_ring(90, 160, p["pool_mat"], 4, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool_ring(170, 230, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(200, 180), 60, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(-200, -180), 60, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_barrels_ring(6, 90, 160))
		c.features.append(_pillars(8, 100, 160, p["pillar_mat"]))
	return c

static func _build_variant_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		# Sparse-ish outer ring + dense grove pockets
		_pillars(10, 150, 220, p["pillar_mat"]),
		_pillars(12, 220, 290, p["pillar_mat"]),
		_pillars_disc(Vector2(-130, 90), 80, 8),
		_pillars_disc(Vector2(160, -130), 70, 6),
		_pillars_disc(Vector2(100, 180), 60, 5),
		# Enemies
		_enemies(4, 120, 220, false),
		_enemies(2, 180, 280, true),
		_enemies(2, 100, 200, false),
		# Barrel clusters scattered
		_barrels_ring(6, 100, 180),
		_barrels_ring(5, 200, 280),
		_barrels_disc(Vector2(150, 100), 50, 4),
		_barrels_disc(Vector2(-200, -180), 60, 4),
		_barrels_disc(Vector2(-180, 200), 50, 3),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(220, -180), 80, p["pool_mat"], 4, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(-220, 180), 70, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool_ring(90, 160, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(220, -180), 60, 4))
		c.features.append(_pillars(6, 200, 280, p["pillar_mat"]))
	return c

static func _build_variant_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		# Concentric pillar rings
		_pillars(8, 90, 150, p["pillar_mat"]),
		_pillars(12, 150, 220, p["pillar_mat"]),
		_pillars(14, 220, 290, p["pillar_mat"]),
		# Enemies
		_enemies(4, 120, 220, false),
		_enemies(2, 180, 260, true),
		_enemies(2, 220, 290, false),
		# Barrel rings packing both bands
		_barrels_ring(8, 90, 180),
		_barrels_ring(6, 180, 290),
		# Vents at cardinal positions
		_vent(Vector2(0, 0), 50, 1),
		_vent(Vector2(0, 220), 40, 1),
		_vent(Vector2(0, -220), 40, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(-160, 160), 70, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(160, -160), 70, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(-160, -160), 60, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool(Vector2(160, 160), 60, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(-150, 150), 60, 3))
		c.features.append(_barrels_disc(Vector2(150, -150), 60, 3))
		c.features.append(_pillars(6, 130, 200, p["pillar_mat"]))
	return c

static func _build_variant_d(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"d"
	c.nominal_radius = BOSS_NOMINAL_R
	c.lobing_amplitude = BOSS_LOBING
	c.inner_disc_radius = BOSS_INNER_DISC
	c.features = [
		_boss(),
		_pillars(10, 90, 170, p["pillar_mat"]),
		_pillars(12, 170, 240, p["pillar_mat"]),
		_pillars(12, 240, 290, p["pillar_mat"]),
		_enemies(4, 100, 200, false),
		_enemies(2, 180, 260, true),
		_enemies(2, 220, 290, false),
		_vent(Vector2(100, -80), 30, 1),
		_vent(Vector2(-100, 80), 30, 1),
		_vent(Vector2(200, 200), 40, 1),
		_vent(Vector2(-200, -200), 40, 1),
		_barrels_ring(8, 100, 200),
		_barrels_ring(6, 200, 290),
		_barrels_disc(Vector2(220, -150), 50, 3),
		_barrels_disc(Vector2(-220, 150), 50, 3),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool_ring(90, 160, p["pool_mat"], 4, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool_ring(170, 230, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
		c.features.append(_pool_ring(230, 290, p["pool_mat"], 2, BOSS_POOL_MIN, BOSS_POOL_MAX))
	else:
		c.features.append(_pillars(6, 90, 160, p["pillar_mat"]))
		c.features.append(_barrels_ring(6, 90, 160))
	return c

static func _build_elite_a(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"
	c.biome = biome
	c.variant_id = &"a"
	c.nominal_radius = ELITE_NOMINAL_R
	c.lobing_amplitude = ELITE_LOBING
	c.inner_disc_radius = ELITE_INNER_DISC
	var chest_feature := FeatureChestSpawn.new()
	chest_feature.rare = false
	c.features = [
		chest_feature,
		_enemies(2, 80, 130, true),
		_pillars_small(5, 70, 130),
		_barrels_ring(2, 40, 90),
		_barrels_disc(Vector2(0, 60), 30, 1),
		_barrels_disc(Vector2(0, -60), 30, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(0, 0), 40, p["pool_mat"], 2, ELITE_POOL_MIN, ELITE_POOL_MAX))
	else:
		# vault: extra pillars instead of pools
		c.features.append(_pillars_small(2, 50, 100))
	return c

static func _build_elite_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = ELITE_NOMINAL_R
	c.lobing_amplitude = ELITE_LOBING
	c.inner_disc_radius = ELITE_INNER_DISC
	var chest_feature := FeatureChestSpawn.new()
	chest_feature.rare = false
	c.features = [
		chest_feature,
		_enemies(2, 60, 120, true),
		_pillars_small(7, 30, 130),
		_barrels_ring(2, 50, 110),
		_barrels_disc(Vector2(-50, 0), 30, 1),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(60, -40), 40, p["pool_mat"], 2, ELITE_POOL_MIN, ELITE_POOL_MAX))
	else:
		c.features.append(_barrels_disc(Vector2(60, -40), 30, 2))
	return c

static func _build_elite_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"elite"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = ELITE_NOMINAL_R
	c.lobing_amplitude = ELITE_LOBING
	c.inner_disc_radius = ELITE_INNER_DISC
	var chest_feature := FeatureChestSpawn.new()
	chest_feature.rare = false
	c.features = [
		chest_feature,
		_enemies(2, 70, 130, true),
		_pillars_small(5, 90, 130),
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

func _init() -> void:
	var dir := DirAccess.open("res://assets/arenas/boss")
	if dir == null:
		DirAccess.make_dir_recursive_absolute("res://assets/arenas/boss")

	for biome in [&"caves", &"mines", &"magma", &"frozen", &"vault"]:
		for variant_builder in [
			[&"a", _build_variant_a],
			[&"b", _build_variant_b],
			[&"c", _build_variant_c],
			[&"d", _build_variant_d],
		]:
			var variant_id: StringName = variant_builder[0]
			var build_fn: Callable = variant_builder[1]
			var comp: ArenaComposition = build_fn.call(biome)
			var path := "res://assets/arenas/boss/%s_%s.tres" % [biome, variant_id]
			var err := ResourceSaver.save(comp, path)
			print("Wrote %s — %s" % [path, "OK" if err == OK else var_to_str(err)])

	DirAccess.make_dir_recursive_absolute("res://assets/arenas/elite")
	for biome in [&"caves", &"mines", &"magma", &"frozen", &"vault"]:
		for variant_builder in [
			[&"a", _build_elite_a],
			[&"b", _build_elite_b],
			[&"c", _build_elite_c],
		]:
			var variant_id: StringName = variant_builder[0]
			var build_fn: Callable = variant_builder[1]
			var comp: ArenaComposition = build_fn.call(biome)
			var path := "res://assets/arenas/elite/%s_%s.tres" % [biome, variant_id]
			var err := ResourceSaver.save(comp, path)
			print("Wrote %s — %s" % [path, "OK" if err == OK else var_to_str(err)])

	print("Done generating compositions.")
	quit(0)
