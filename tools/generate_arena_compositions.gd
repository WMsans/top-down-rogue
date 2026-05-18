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

const MAT_AIR := 0
const MAT_STONE := 2
const MAT_WOOD := 3
const MAT_ICE := 4
const MAT_LAVA := 5
const MAT_WATER := 6

static func _biome_params(biome: StringName) -> Dictionary:
	match biome:
		&"caves":  return {"pillar_mat": MAT_STONE, "pool_mat": MAT_LAVA}
		&"mines":  return {"pillar_mat": MAT_WOOD,  "pool_mat": MAT_LAVA}
		&"magma":  return {"pillar_mat": MAT_STONE, "pool_mat": MAT_LAVA}
		&"frozen": return {"pillar_mat": MAT_ICE,   "pool_mat": MAT_WATER}
		&"vault":  return {"pillar_mat": MAT_STONE, "pool_mat": -1}
	return {}

static func _ring(r_min: float, r_max: float) -> ArenaRegion.RegionRing:
	var r := ArenaRegion.RegionRing.new()
	r.center = Vector2.ZERO
	r.r_min = r_min
	r.r_max = r_max
	return r

static func _disc(center: Vector2, radius: float) -> ArenaRegion.RegionDisc:
	var d := ArenaRegion.RegionDisc.new()
	d.center = center
	d.radius = radius
	return d

static func _point(pos: Vector2 = Vector2.ZERO) -> ArenaRegion.RegionPoint:
	var p := ArenaRegion.RegionPoint.new()
	p.offset = pos
	return p

static func _boss() -> ArenaFeature.FeatureBossSpawn:
	var b := ArenaFeature.FeatureBossSpawn.new()
	b.region = _point()
	b.boss_scene = BOSS_ENEMY_SCENE
	return b

static func _pillars(count: int, r_min: float, r_max: float, pillar_mat: int) -> ArenaFeature.FeaturePillarCluster:
	var f := ArenaFeature.FeaturePillarCluster.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.pillar_radius_cells = 10
	f.spacing_min = 64.0
	return f

static func _enemies(count: int, r_min: float, r_max: float, is_elite: bool) -> ArenaFeature.FeatureEnemyPack:
	var f := ArenaFeature.FeatureEnemyPack.new()
	f.region = _ring(r_min, r_max)
	f.count = count
	f.is_elite = is_elite
	f.enemy_scene = MELEE_ENEMY_SCENE
	return f

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

static func _build_variant_a(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"
	c.biome = biome
	c.variant_id = &"a"
	c.nominal_radius = 960
	c.lobing_amplitude = 160
	c.inner_disc_radius = 256
	c.features = [
		_boss(),
		_pillars(12, 600, 900, p["pillar_mat"]),
		_enemies(6, 700, 950, false),
		_enemies(2, 400, 700, true),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(-200, 100), 200, p["pool_mat"], 1, BOSS_POOL_MIN, BOSS_POOL_MAX))
	return c

static func _build_variant_b(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"b"
	c.nominal_radius = 960; c.lobing_amplitude = 160; c.inner_disc_radius = 256
	c.features = [
		_boss(),
		_pillars(4, 700, 950, p["pillar_mat"]),
		_enemies(4, 800, 1100, false),
		_enemies(2, 800, 1100, true),
	]
	if p["pool_mat"] > 0:
		c.features.append(_pool(Vector2(0, 0), 300, p["pool_mat"], 3, BOSS_POOL_MIN, BOSS_POOL_MAX))
	return c

static func _build_variant_c(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"c"
	c.nominal_radius = 960; c.lobing_amplitude = 160; c.inner_disc_radius = 256
	c.features = [
		_boss(),
		_pillars(5, 500, 850, p["pillar_mat"]),
		_enemies(4, 600, 900, false),
		_enemies(2, 700, 950, true),
	]
	return c

static func _build_variant_d(biome: StringName) -> ArenaComposition:
	var p := _biome_params(biome)
	var c := ArenaComposition.new()
	c.arena_kind = &"boss"; c.biome = biome; c.variant_id = &"d"
	c.nominal_radius = 960; c.lobing_amplitude = 160; c.inner_disc_radius = 256
	c.features = [
		_boss(),
		_pillars(2, 500, 700, p["pillar_mat"]),
		_enemies(8, 500, 800, false),
		_enemies(4, 800, 1100, false),
		_enemies(1, 600, 900, true),
	]
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
