#include "terrain_physical.h"

#include "../sim/material_table.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

Ref<TerrainCell> TerrainPhysical::query(const Vector2 &world_pos) const {
	Vector2i cp(static_cast<int>(std::floor(world_pos.x)), static_cast<int>(std::floor(world_pos.y)));
	HashMap<Vector2i, int>::ConstIterator it = _grid.find(cp);
	if (it != _grid.end()) {
		return _cell_from_material(it->value);
	}
	Ref<TerrainCell> empty;
	empty.instantiate();
	return empty;
}

void TerrainPhysical::invalidate_rect(const Rect2i &rect) {
	for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
		for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
			_grid.erase(Vector2i(x, y));
		}
	}
	_dirty_sectors.push_back(rect);
}

void TerrainPhysical::set_center(const Vector2i &world_center) {
	_grid_center = world_center;
}

Ref<TerrainCell> TerrainPhysical::_cell_from_material(int mat_id) const {
	MaterialTable *mt = MaterialTable::get_singleton();
	bool is_solid = mt->has_collider(mat_id);
	bool is_fluid = mt->is_fluid(mat_id);
	int dmg = mt->get_damage(mat_id);
	Ref<TerrainCell> c;
	c.instantiate();
	c->init_args(mat_id, is_solid, is_fluid, dmg);
	return c;
}

void TerrainPhysical::_bind_methods() {
	ClassDB::bind_method(D_METHOD("query", "world_pos"), &TerrainPhysical::query);
	ClassDB::bind_method(D_METHOD("invalidate_rect", "rect"), &TerrainPhysical::invalidate_rect);
	ClassDB::bind_method(D_METHOD("set_center", "world_center"), &TerrainPhysical::set_center);

	ClassDB::bind_method(D_METHOD("get_world_manager"), &TerrainPhysical::get_world_manager);
	ClassDB::bind_method(D_METHOD("set_world_manager", "v"), &TerrainPhysical::set_world_manager);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "world_manager",
						 PROPERTY_HINT_NODE_TYPE, "Node2D"),
			"set_world_manager", "get_world_manager");
}

} // namespace toprogue
