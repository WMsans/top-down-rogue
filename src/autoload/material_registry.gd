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
        p_damage: int = 0
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

var materials: Array[MaterialDef] = []

var MAT_AIR: int
var MAT_WOOD: int
var MAT_STONE: int
var MAT_GAS: int
var MAT_LAVA: int

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
        10
    )
    mat_lava.id = materials.size()
    materials.append(mat_lava)
    MAT_LAVA = mat_lava.id

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

func get_damage(material_id: int) -> int:
    if material_id < 0 or material_id >= materials.size():
        return 0
    return materials[material_id].damage
