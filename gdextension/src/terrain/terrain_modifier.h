#pragma once

#include "chunk.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/wrapped.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

class TerrainPhysical;

class TerrainModifier : public godot::RefCounted {
	GDCLASS(TerrainModifier, godot::RefCounted);

	godot::Dictionary _chunks;
	TerrainPhysical *_terrain_physical = nullptr;

public:
	void set_chunks(const godot::Dictionary &chunks);
	void set_terrain_physical(TerrainPhysical *tp);

	void place_gas(godot::Vector2 world_pos, float radius, int density,
			godot::Vector2i velocity = godot::Vector2i(0, 0));
	void place_lava(godot::Vector2 world_pos, float radius);
	void place_fire(godot::Vector2 world_pos, float radius);
	void place_material(godot::Vector2 world_pos, float radius, int material_id);
	void disperse_materials_in_arc(godot::Vector2 origin, godot::Vector2 direction, float radius,
			float arc_angle, float push_speed, const godot::Array &materials);
	void clear_and_push_materials_in_arc(godot::Vector2 origin, godot::Vector2 direction,
			float radius, float arc_angle, float push_speed, float edge_fraction,
			const godot::Array &materials);

protected:
	static void _bind_methods();

private:
	void mark_dirty(Chunk *c, int x_min, int y_min, int x_max, int y_max);
};

} // namespace toprogue
