#pragma once

#include "../resources/terrain_cell.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace toprogue {

class TerrainPhysical : public godot::Node {
	GDCLASS(TerrainPhysical, godot::Node);

public:
	godot::Node2D *world_manager = nullptr;
	godot::Dictionary _grid;
	godot::Vector2i _grid_center;
	int _grid_size = 128;
	int _half_grid = 64;

	TerrainPhysical() = default;

	godot::Ref<TerrainCell> query(const godot::Vector2 &world_pos) const;
	void invalidate_rect(const godot::Rect2i &rect);
	void set_center(const godot::Vector2i &world_center);

	godot::Node2D *get_world_manager() const { return world_manager; }
	void set_world_manager(godot::Node2D *v) { world_manager = v; }

	godot::Dictionary get_grid() const { return _grid; }
	void set_grid(const godot::Dictionary &v) { _grid = v; }
	godot::Vector2i get_grid_center() const { return _grid_center; }
	void set_grid_center(const godot::Vector2i &v) { _grid_center = v; }

protected:
	static void _bind_methods();

private:
	std::vector<godot::Rect2i> _dirty_sectors;

	godot::Ref<TerrainCell> _cell_from_material(int mat_id) const;
};

} // namespace toprogue
