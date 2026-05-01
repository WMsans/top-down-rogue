#pragma once

#include <godot_cpp/classes/collision_shape2d.hpp>
#include <godot_cpp/classes/occluder_polygon2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/static_body2d.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Static-method shell. Mirrors src/physics/terrain_collider.gd 1:1.
class TerrainCollider : public godot::RefCounted {
	GDCLASS(TerrainCollider, godot::RefCounted);

public:
	static constexpr int CELL_SIZE = 2;
	static constexpr double DP_EPSILON = 0.8;
	static constexpr double OCCLUDER_INSET = 4.0;
	static constexpr double MIN_OCCLUDER_AREA = 16.0;

	static godot::CollisionShape2D *build_collision(
			const godot::PackedByteArray &data,
			int size,
			godot::StaticBody2D *static_body,
			const godot::Vector2i &world_offset);

	static godot::CollisionShape2D *build_from_segments(
			const godot::PackedVector2Array &segments,
			godot::StaticBody2D *static_body,
			const godot::Vector2i &world_offset);

	static godot::TypedArray<godot::OccluderPolygon2D> create_occluder_polygons(
			const godot::PackedVector2Array &segments);

	static godot::PackedVector2Array shrink_polygon(
			const godot::PackedVector2Array &points,
			double distance);

protected:
	static void _bind_methods();
};

} // namespace toprogue
