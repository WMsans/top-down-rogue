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
    var is_gas: bool

    func _init(
        p_name: String,
        p_texture_path: String,
        p_flammable: bool,
        p_ignition_temp: int,
        p_burn_health: int,
        p_has_collider: bool,
        p_has_wall_extension: bool,
        p_is_gas: bool = false
    ):
        name = p_name
        texture_path = p_texture_path
        flammable = p_flammable
        ignition_temp = p_ignition_temp
        burn_health = p_burn_health
        has_collider = p_has_collider
        has_wall_extension = p_has_wall_extension
        is_gas = p_is_gas

var materials: Array[MaterialDef] = []

var MAT_AIR: int
var MAT_WOOD: int
var MAT_STONE: int
var MAT_STEAM_GAS: int

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
        "WOOD", "res://textures/PixelTextures/plank.png",
        true, 180, 255, true, true
    )
    mat_wood.id = materials.size()
    materials.append(mat_wood)
    MAT_WOOD = mat_wood.id
    
    var mat_stone := MaterialDef.new(
        "STONE", "res://textures/PixelTextures/stone.png",
        false, 0, 0, true, true
    )
    mat_stone.id = materials.size()
    materials.append(mat_stone)
    MAT_STONE = mat_stone.id
    
    var mat_steam_gas := MaterialDef.new(
        "STEAM_GAS", "",
        false, 0, 0, false, false, true
    )
    mat_steam_gas.id = materials.size()
    materials.append(mat_steam_gas)
    MAT_STEAM_GAS = mat_steam_gas.id

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

func is_gas(material_id: int) -> bool:
    if material_id < 0 or material_id >= materials.size():
        return false
    return materials[material_id].is_gas