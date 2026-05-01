#pragma once

#include "../resources/terrain_cell.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace toprogue {

class TerrainPhysical : public godot::Node {
	GDCLASS(TerrainPhysical, godot::Node);

public:
	godot::Node2D *world_manager = nullptr;

	TerrainPhysical() = default;

	godot::Ref<TerrainCell> query(const godot::Vector2 &world_pos) const;
	void invalidate_rect(const godot::Rect2i &rect);
	void set_center(const godot::Vector2i &world_center);

	godot::Node2D *get_world_manager() const { return world_manager; }
	void set_world_manager(godot::Node2D *v) { world_manager = v; }

protected:
	static void _bind_methods();

private:
	godot::HashMap<godot::Vector2i, int> _grid;
	godot::Vector2i _grid_center;
	int _grid_size = 128;
	int _half_grid = 64;
	std::vector<godot::Rect2i> _dirty_sectors;

	godot::Ref<TerrainCell> _cell_from_material(int mat_id) const;
};

} // namespace toprogue
