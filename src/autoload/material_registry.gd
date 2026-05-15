@tool
extends Node

class MaterialDef:
	var id: int
	var name: String
	var texture_path: String
	var flammable: bool
	var ignition_temp: int
	var burn_health: int
	var has_collider: bool
	var has_wall_extension: bool
	var tint_color: Color
	var fluid: bool
	var damage: int
	var glow: float
	var hardness: float
	var indestructible: bool = false

	func _init(
		p_name: String,
		p_texture_path: String,
		p_flammable: bool,
		p_ignition_temp: int,
		p_burn_health: int,
		p_has_collider: bool,
		p_has_wall_extension: bool,
		p_tint_color: Color = Color(0, 0, 0, 0),
		p_fluid: bool = false,
		p_damage: int = 0,
		p_glow: float = 1.0,
		p_hardness: float = 0.0,
		p_indestructible: bool = false
	):
		name = p_name
		texture_path = p_texture_path
		flammable = p_flammable
		ignition_temp = p_ignition_temp
		burn_health = p_burn_health
		has_collider = p_has_collider
		has_wall_extension = p_has_wall_extension
		tint_color = p_tint_color
		fluid = p_fluid
		damage = p_damage
		glow = p_glow
		hardness = p_hardness
		indestructible = p_indestructible

var materials: Array[MaterialDef] = []

var MAT_AIR: int
var MAT_WOOD: int
var MAT_STONE: int
var MAT_GAS: int
var MAT_LAVA: int
var MAT_DIRT: int
var MAT_COAL: int
var MAT_ICE: int
var MAT_WATER: int
var MAT_BLOOD: int
var MAT_OIL: int
var MAT_EXPLODE_WAVE: int
var MAT_STONE_BRICKS: int
var MAT_WOOD_BEAM: int
var MAT_OBSIDIAN: int
var MAT_PACKED_ICE: int
var MAT_ENGRAVED_METAL: int
var MAT_STONE_CRACKED: int
var MAT_MINE_STONE_CRACKED: int
var MAT_MAGMA_STONE_CRACKED: int
var MAT_FROZEN_ROCK_CRACKED: int
var MAT_VAULT_METAL_CRACKED: int

func _ready():
	_init_materials()

func _init_materials():
	var mat_air := MaterialDef.new(
		"AIR", "", false, 0, 0, false, false
	)
	mat_air.id = materials.size()
	materials.append(mat_air)
	MAT_AIR = mat_air.id
	
	var mat_wood := MaterialDef.new(
		"WOOD", "res://textures/Environments/Walls/plank.png",
		true, 180, 255, true, true,
		Color(0, 0, 0, 0), false, 0, 1.0,
		2.0
	)
	mat_wood.id = materials.size()
	materials.append(mat_wood)
	MAT_WOOD = mat_wood.id
	
	var mat_stone := MaterialDef.new(
		"STONE", "res://textures/Environments/Walls/stone.png",
		false, 0, 0, true, true,
		Color(0, 0, 0, 0), false, 0, 1.0,
		5.0
	)
	mat_stone.id = materials.size()
	materials.append(mat_stone)
	MAT_STONE = mat_stone.id

	var mat_gas := MaterialDef.new(
		"GAS", "",
		false, 0, 0,
		false, false,
		Color(0.4, 0.9, 0.3, 1.0),
		true
	)
	mat_gas.id = materials.size()
	materials.append(mat_gas)
	MAT_GAS = mat_gas.id

	var mat_lava := MaterialDef.new(
		"LAVA", "",
		false, 0, 0,
		false, false,
		Color(0.9, 0.4, 0.1, 1.0),
		true,
		10,
		10.0
	)
	mat_lava.id = materials.size()
	materials.append(mat_lava)
	MAT_LAVA = mat_lava.id

	var mat_dirt := MaterialDef.new(
		"DIRT", "res://textures/Environments/Walls/dirt.png",
		false, 0, 0,
		true, true,
		Color(0.45, 0.32, 0.18, 1.0),
		false, 0, 1.0,
		0.5
	)
	mat_dirt.id = materials.size()
	materials.append(mat_dirt)
	MAT_DIRT = mat_dirt.id

	var mat_coal := MaterialDef.new(
		"COAL", "res://textures/Environments/Walls/coal.png",
		true, 220, 200,
		true, true,
		Color(0.12, 0.12, 0.14, 1.0),
		false,
		0,
		20.0,
		3.0
	)
	mat_coal.id = materials.size()
	materials.append(mat_coal)
	MAT_COAL = mat_coal.id

	var mat_ice := MaterialDef.new(
		"ICE", "res://textures/Environments/Walls/ice.png",
		false, 0, 0,
		true, true,
		Color(0.7, 0.85, 0.95, 1.0),
		false, 0, 1.0,
		4.0
	)
	mat_ice.id = materials.size()
	materials.append(mat_ice)
	MAT_ICE = mat_ice.id

	var mat_water := MaterialDef.new(
		"WATER", "",
		false, 0, 0,
		true, true,
		Color(0.2, 0.45, 0.75, 1.0)
	)
	mat_water.id = materials.size()
	materials.append(mat_water)
	MAT_WATER = mat_water.id

	var mat_blood := MaterialDef.new(
		"BLOOD", "",
		false, 0, 0,
		false, false,
		Color(0.8, 0.05, 0.05, 1.0),
		true,
		0,
		1.0
	)
	mat_blood.id = materials.size()
	materials.append(mat_blood)
	MAT_BLOOD = mat_blood.id

	# OIL — fluid; non-flammable in base state (ignites by direct contact only)
	var mat_oil := MaterialDef.new(
		"OIL", "",
		false, 0, 60,   # not auto-ignitable; burn_health=60 = 60-tick burn lifetime
		false, false,
		Color(0.10, 0.06, 0.04, 1.0),
		true,           # fluid
		0, 1.0, 0.0
	)
	mat_oil.id = materials.size()
	materials.append(mat_oil)
	MAT_OIL = mat_oil.id

	# EXPLODE_WAVE — custom sim, transient
	var mat_explode := MaterialDef.new(
		"EXPLODE_WAVE", "",
		false, 0, 0,
		false, false,
		Color(1.0, 0.95, 0.5, 1.0),
		false,
		0, 30.0, 0.0
	)
	mat_explode.id = materials.size()
	materials.append(mat_explode)
	MAT_EXPLODE_WAVE = mat_explode.id

	# Per-biome perimeter accents (5)
	var perim_specs := [
		{"name": "STONE_BRICKS", "tint": Color(0.55, 0.55, 0.58, 1.0)},
		{"name": "WOOD_BEAM",    "tint": Color(0.45, 0.30, 0.18, 1.0)},
		{"name": "OBSIDIAN",     "tint": Color(0.10, 0.08, 0.15, 1.0)},
		{"name": "PACKED_ICE",   "tint": Color(0.78, 0.90, 0.98, 1.0)},
		{"name": "ENGRAVED_METAL", "tint": Color(0.65, 0.62, 0.45, 1.0)},
	]
	for spec in perim_specs:
		var m := MaterialDef.new(
			spec.name, "",
			false, 0, 0,
			true, true,           # solid, wall-extension
			spec.tint,
			false, 0, 1.0, 5.0
		)
		m.id = materials.size()
		materials.append(m)
		set("MAT_" + spec.name, m.id)

	# Per-biome cracked variants (5)
	var cracked_specs := [
		{"name": "STONE_CRACKED",    "tint": Color(0.50, 0.50, 0.52, 1.0)},
		{"name": "MINE_STONE_CRACKED", "tint": Color(0.42, 0.36, 0.28, 1.0)},
		{"name": "MAGMA_STONE_CRACKED", "tint": Color(0.40, 0.20, 0.15, 1.0)},
		{"name": "FROZEN_ROCK_CRACKED", "tint": Color(0.62, 0.78, 0.88, 1.0)},
		{"name": "VAULT_METAL_CRACKED", "tint": Color(0.60, 0.58, 0.42, 1.0)},
	]
	for spec in cracked_specs:
		var m := MaterialDef.new(
			spec.name, "",
			false, 0, 0,
			true, true,
			spec.tint,
			false, 0, 1.0, 4.0
		)
		m.id = materials.size()
		materials.append(m)
		set("MAT_" + spec.name, m.id)

func is_flammable(material_id: int) -> bool:
	if material_id < 0 or material_id >= materials.size():
		return false
	return materials[material_id].flammable

func get_ignition_temp(material_id: int) -> int:
	if material_id < 0 or material_id >= materials.size():
		return 0
	return materials[material_id].ignition_temp

func has_collider(material_id: int) -> bool:
	if material_id < 0 or material_id >= materials.size():
		return false
	return materials[material_id].has_collider

func has_wall_extension(material_id: int) -> bool:
	if material_id < 0 or material_id >= materials.size():
		return false
	return materials[material_id].has_wall_extension

func get_tint_color(material_id: int) -> Color:
	if material_id < 0 or material_id >= materials.size():
		return Color(0, 0, 0, 0)
	return materials[material_id].tint_color

func get_fluids() -> Array[int]:
	var result: Array[int] = []
	for mat in materials:
		if mat.fluid:
			result.append(mat.id)
	return result

func is_fluid(material_id: int) -> bool:
	if material_id < 0 or material_id >= materials.size():
		return false
	return materials[material_id].fluid


func get_damage(material_id: int) -> int:
	if material_id < 0 or material_id >= materials.size():
		return 0
	return materials[material_id].damage


func get_glow(material_id: int) -> float:
	if material_id < 0 or material_id >= materials.size():
		return 1.0
	return materials[material_id].glow


func get_hardness(material_id: int) -> float:
	if material_id < 0 or material_id >= materials.size():
		return 0.0
	return materials[material_id].hardness

