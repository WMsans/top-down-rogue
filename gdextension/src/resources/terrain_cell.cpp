#include "terrain_cell.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

TerrainCell::TerrainCell() = default;

void TerrainCell::init_args(int p_material_id, bool p_is_solid, bool p_is_fluid, double p_damage) {
	material_id = p_material_id;
	is_solid = p_is_solid;
	is_fluid = p_is_fluid;
	damage = p_damage;
}

void TerrainCell::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init_args", "material_id", "is_solid", "is_fluid", "damage"),
			&TerrainCell::init_args);

	ClassDB::bind_method(D_METHOD("get_material_id"), &TerrainCell::get_material_id);
	ClassDB::bind_method(D_METHOD("set_material_id", "v"), &TerrainCell::set_material_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "material_id"), "set_material_id", "get_material_id");

	ClassDB::bind_method(D_METHOD("get_is_solid"), &TerrainCell::get_is_solid);
	ClassDB::bind_method(D_METHOD("set_is_solid", "v"), &TerrainCell::set_is_solid);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_solid"), "set_is_solid", "get_is_solid");

	ClassDB::bind_method(D_METHOD("get_is_fluid"), &TerrainCell::get_is_fluid);
	ClassDB::bind_method(D_METHOD("set_is_fluid", "v"), &TerrainCell::set_is_fluid);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_fluid"), "set_is_fluid", "get_is_fluid");

	ClassDB::bind_method(D_METHOD("get_damage"), &TerrainCell::get_damage);
	ClassDB::bind_method(D_METHOD("set_damage", "v"), &TerrainCell::set_damage);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damage"), "set_damage", "get_damage");
}

} // namespace toprogue
