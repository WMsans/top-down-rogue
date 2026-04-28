@tool
extends SceneTree

# Run: godot --headless --script tools/generate_biome_resources.gd

const _BiomeDef = preload("res://src/core/biome_def.gd")
const _PoolDef = preload("res://src/core/pool_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func _init() -> void:
	_generate_caves()
	_generate_mines()
	_generate_magma()
	_generate_frozen()
	_generate_vault()
	print("[generate_biome_resources] done")
	quit()

func _make_pool(mat_id: int, scale: float, threshold: float, seed_off: int) -> Resource:
	var p: Resource = _PoolDef.new()
	p.material_id = mat_id
	p.noise_scale = scale
	p.noise_threshold = threshold
	p.seed_offset = seed_off
	return p

func _make_template(path: String, weight: float, size_class: int, is_secret: bool = false, is_boss: bool = false, rotatable: bool = true) -> Resource:
	var rt: Resource = _RoomTemplate.new()
	rt.png_path = path
	rt.weight = weight
	rt.size_class = size_class
	rt.is_secret = is_secret
	rt.is_boss = is_boss
	rt.rotatable = rotatable
	return rt

func _make_biome() -> Resource:
	var b: Resource = _BiomeDef.new()
	b.pool_materials = []
	b.room_templates = []
	b.boss_templates = []
	return b

func _save(b: Resource, path: String) -> void:
	var err := ResourceSaver.save(b, path)
	if err != OK:
		print("  ERROR saving %s: %d" % [path, err])
	else:
		print("  wrote ", path)

func _generate_caves() -> void:
	var b: Resource = _make_biome()
	b.display_name = "Caves"
	b.cave_noise_scale = 0.008
	b.cave_threshold = 0.42
	b.ridge_weight = 0.3
	b.ridge_scale = 0.012
	b.octaves = 5
	b.background_material = 2
	b.pool_materials.append(_make_pool(5, 0.005, 0.7, 11))
	b.room_templates.append(_make_template("res://assets/rooms/caves/blob_a.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/caves/blob_b.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/caves/corridor_a.png", 1.5, 128))
	b.room_templates.append(_make_template("res://assets/rooms/caves/secret_a.png", 1.0, 32, true, false))
	b.boss_templates.append(_make_template("res://assets/rooms/caves/boss_arena.png", 1.0, 128, false, true, false))
	b.secret_ring_thickness = 3
	b.tint = Color(1, 1, 1, 1)
	_save(b, "res://assets/biomes/caves.tres")

func _generate_mines() -> void:
	var b: Resource = _make_biome()
	b.display_name = "Mines"
	b.cave_noise_scale = 0.010
	b.cave_threshold = 0.45
	b.ridge_weight = 0.4
	b.ridge_scale = 0.012
	b.octaves = 5
	b.background_material = 2
	b.pool_materials.append(_make_pool(6, 0.006, 0.65, 21))
	b.pool_materials.append(_make_pool(1, 0.020, 0.85, 22))
	b.room_templates.append(_make_template("res://assets/rooms/mines/corridor_a.png", 1.5, 128))
	b.room_templates.append(_make_template("res://assets/rooms/mines/corridor_b.png", 1.5, 128))
	b.room_templates.append(_make_template("res://assets/rooms/mines/arena_a.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/mines/secret_a.png", 1.0, 32, true, false))
	b.boss_templates.append(_make_template("res://assets/rooms/mines/boss_arena.png", 1.0, 128, false, true, false))
	b.secret_ring_thickness = 3
	b.tint = Color(0.9, 0.85, 0.75, 1)
	_save(b, "res://assets/biomes/mines.tres")

func _generate_magma() -> void:
	var b: Resource = _make_biome()
	b.display_name = "Magma Caverns"
	b.cave_noise_scale = 0.012
	b.cave_threshold = 0.50
	b.ridge_weight = 0.5
	b.ridge_scale = 0.012
	b.octaves = 5
	b.background_material = 2
	b.pool_materials.append(_make_pool(4, 0.004, 0.72, 31))
	b.pool_materials.append(_make_pool(3, 0.015, 0.85, 32))
	b.room_templates.append(_make_template("res://assets/rooms/magma/blob_lava_a.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/magma/blob_lava_b.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/magma/arena_a.png", 2.0, 64))
	b.boss_templates.append(_make_template("res://assets/rooms/magma/boss_arena.png", 1.0, 128, false, true, false))
	b.secret_ring_thickness = 3
	b.tint = Color(1, 0.7, 0.5, 1)
	_save(b, "res://assets/biomes/magma.tres")

func _generate_frozen() -> void:
	var b: Resource = _make_biome()
	b.display_name = "Frozen Depths"
	b.cave_noise_scale = 0.009
	b.cave_threshold = 0.40
	b.ridge_weight = 0.2
	b.ridge_scale = 0.012
	b.octaves = 4
	b.background_material = 7
	b.pool_materials.append(_make_pool(8, 0.007, 0.62, 41))
	b.room_templates.append(_make_template("res://assets/rooms/frozen/blob_water_a.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/frozen/blob_water_b.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/frozen/corridor_a.png", 1.5, 128))
	b.boss_templates.append(_make_template("res://assets/rooms/frozen/boss_arena.png", 1.0, 128, false, true, false))
	b.secret_ring_thickness = 3
	b.tint = Color(0.7, 0.85, 1, 1)
	_save(b, "res://assets/biomes/frozen.tres")

func _generate_vault() -> void:
	var b: Resource = _make_biome()
	b.display_name = "Vault"
	b.cave_noise_scale = 0.014
	b.cave_threshold = 0.55
	b.ridge_weight = 0.5
	b.ridge_scale = 0.012
	b.octaves = 5
	b.background_material = 1
	b.pool_materials.append(_make_pool(2, 0.012, 0.72, 51))
	b.room_templates.append(_make_template("res://assets/rooms/vault/arena_a.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/vault/arena_b.png", 2.0, 64))
	b.room_templates.append(_make_template("res://assets/rooms/vault/shop_a.png", 1.0, 32))
	b.boss_templates.append(_make_template("res://assets/rooms/vault/boss_arena.png", 1.0, 128, false, true, false))
	b.secret_ring_thickness = 3
	b.tint = Color(1, 0.95, 0.85, 1)
	_save(b, "res://assets/biomes/vault.tres")
