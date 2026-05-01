#include "material_table.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// The order of entries in this array is load-bearing. It must match the order
// that material_registry.gd produced before deletion. Changing the order
// would shift material IDs and break any .tres files that reference them.
static const MaterialDef s_material_data[MaterialTable::MAT_COUNT] = {
    /* MAT_AIR   */ { 0, "AIR",   "",                                  false,   0,   0, false, false, Color(0.0f, 0.0f, 0.0f, 0.0f), false,  0, 1.0f },
    /* MAT_WOOD  */ { 1, "WOOD",  "res://textures/Environments/Walls/plank.png", true,  180, 255, true,  true,  Color(0.0f, 0.0f, 0.0f, 0.0f), false,  0, 1.0f },
    /* MAT_STONE */ { 2, "STONE", "res://textures/Environments/Walls/stone.png", false,   0,   0, true,  true,  Color(0.0f, 0.0f, 0.0f, 0.0f), false,  0, 1.0f },
    /* MAT_GAS   */ { 3, "GAS",   "",                                  false,   0,   0, false, false, Color(0.4f, 0.9f, 0.3f, 1.0f),  true,   0, 1.0f },
    /* MAT_LAVA  */ { 4, "LAVA",  "",                                  false,   0,   0, false, false, Color(0.9f, 0.4f, 0.1f, 1.0f),  true,  10, 10.0f },
    /* MAT_DIRT  */ { 5, "DIRT",  "res://textures/Environments/Walls/dirt.png",  false,   0,   0, true,  true,  Color(0.45f, 0.32f, 0.18f, 1.0f), false,  0, 1.0f },
    /* MAT_COAL  */ { 6, "COAL",  "res://textures/Environments/Walls/coal.png",  true,  220, 200, true,  true,  Color(0.12f, 0.12f, 0.14f, 1.0f), false,  0, 20.0f },
    /* MAT_ICE   */ { 7, "ICE",   "res://textures/Environments/Walls/ice.png",   false,   0,   0, true,  true,  Color(0.7f, 0.85f, 0.95f, 1.0f),  false,  0, 1.0f },
    /* MAT_WATER */ { 8, "WATER", "",                                  false,   0,   0, true,  true,  Color(0.2f, 0.45f, 0.75f, 1.0f),  false,  0, 1.0f },
};

MaterialTable::MaterialTable() {
    for (int i = 0; i < MAT_COUNT; i++) {
        defs.push_back(s_material_data[i]);
    }
}

MaterialTable::~MaterialTable() {
}

void MaterialTable::populate() {
    // defs is already populated by the constructor. This method exists as an
    // explicit "ready" hook called during MODULE_INITIALIZATION_LEVEL_SCENE
    // in case future steps need to add post-init work.
}

const MaterialDef &MaterialTable::def(int p_id) const {
    return defs[_valid_id(p_id) ? p_id : 0];
}

bool MaterialTable::_valid_id(int p_id) const {
    return p_id >= 0 && p_id < defs.size();
}

bool MaterialTable::is_flammable(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].flammable;
}

int MaterialTable::get_ignition_temp(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].ignition_temp : 0;
}

bool MaterialTable::has_collider(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].has_collider;
}

bool MaterialTable::has_wall_extension(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].has_wall_extension;
}

Color MaterialTable::get_tint_color(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].tint_color : Color(0.0f, 0.0f, 0.0f, 0.0f);
}

PackedInt32Array MaterialTable::get_fluids() const {
    PackedInt32Array result;
    for (const MaterialDef &m : defs) {
        if (m.fluid) {
            result.append(m.id);
        }
    }
    return result;
}

bool MaterialTable::is_fluid(int p_material_id) const {
    return _valid_id(p_material_id) && defs[p_material_id].fluid;
}

int MaterialTable::get_damage(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].damage : 0;
}

float MaterialTable::get_glow(int p_material_id) const {
    return _valid_id(p_material_id) ? defs[p_material_id].glow : 1.0f;
}

Array MaterialTable::get_materials() const {
    Array result;
    for (const MaterialDef &m : defs) {
        Dictionary d;
        d["id"] = m.id;
        d["name"] = m.name;
        d["texture_path"] = m.texture_path;
        d["flammable"] = m.flammable;
        d["ignition_temp"] = m.ignition_temp;
        d["burn_health"] = m.burn_health;
        d["has_collider"] = m.has_collider;
        d["has_wall_extension"] = m.has_wall_extension;
        d["tint_color"] = m.tint_color;
        d["fluid"] = m.fluid;
        d["damage"] = m.damage;
        d["glow"] = m.glow;
        result.append(d);
    }
    return result;
}

void MaterialTable::_bind_methods() {
    // Material ID constants — GDScript reads as MaterialTable.MAT_AIR etc.
    BIND_CONSTANT(MAT_AIR);
    BIND_CONSTANT(MAT_WOOD);
    BIND_CONSTANT(MAT_STONE);
    BIND_CONSTANT(MAT_GAS);
    BIND_CONSTANT(MAT_LAVA);
    BIND_CONSTANT(MAT_DIRT);
    BIND_CONSTANT(MAT_COAL);
    BIND_CONSTANT(MAT_ICE);
    BIND_CONSTANT(MAT_WATER);

    // Query methods — match old MaterialRegistry API exactly.
    ClassDB::bind_method(D_METHOD("is_flammable", "material_id"), &MaterialTable::is_flammable);
    ClassDB::bind_method(D_METHOD("get_ignition_temp", "material_id"), &MaterialTable::get_ignition_temp);
    ClassDB::bind_method(D_METHOD("has_collider", "material_id"), &MaterialTable::has_collider);
    ClassDB::bind_method(D_METHOD("has_wall_extension", "material_id"), &MaterialTable::has_wall_extension);
    ClassDB::bind_method(D_METHOD("get_tint_color", "material_id"), &MaterialTable::get_tint_color);
    ClassDB::bind_method(D_METHOD("get_fluids"), &MaterialTable::get_fluids);
    ClassDB::bind_method(D_METHOD("is_fluid", "material_id"), &MaterialTable::is_fluid);
    ClassDB::bind_method(D_METHOD("get_damage", "material_id"), &MaterialTable::get_damage);
    ClassDB::bind_method(D_METHOD("get_glow", "material_id"), &MaterialTable::get_glow);
    ClassDB::bind_method(D_METHOD("get_materials"), &MaterialTable::get_materials);

    // Expose `materials` as a property so GDScript can write
    // `for m in MaterialTable.materials` (same pattern as today).
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "materials"), "get_materials", "");
}

} // namespace godot
