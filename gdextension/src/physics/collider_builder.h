#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace toprogue {

// Spec §8.3. Walks a chunk's solid-cell mask and produces the segment-pair endpoint
// list consumed by TerrainCollider::build_from_segments / create_occluder_polygons.
// Replaces shaders/compute/collider.glsl.
class ColliderBuilder : public godot::RefCounted {
	GDCLASS(ColliderBuilder, godot::RefCounted);

public:
	static godot::PackedVector2Array build_segments(
			const godot::PackedByteArray &data, int size);

protected:
	static void _bind_methods();
};

} // namespace toprogue
