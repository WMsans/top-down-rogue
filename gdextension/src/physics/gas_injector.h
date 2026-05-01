#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Mirrors src/physics/gas_injector.gd 1:1. Byte format is consumed by
// shaders/include/sim/* — must stay byte-for-byte stable until step 7.
class GasInjector : public godot::RefCounted {
	GDCLASS(GasInjector, godot::RefCounted);

public:
	static constexpr int MAX_INJECTIONS_PER_CHUNK = 32;
	static constexpr double MIN_SPEED_SQ = 0.25;
	static constexpr double VELOCITY_SCALE = 1.0 / 60.0;
	static constexpr int CHUNK_SIZE = 256;
	static constexpr int HEADER_BYTES = 16;
	static constexpr int BODY_BYTES = 32;
	static constexpr int BUFFER_BYTES = HEADER_BYTES + BODY_BYTES * MAX_INJECTIONS_PER_CHUNK;

	static godot::PackedByteArray build_payload(
			godot::SceneTree *scene,
			const godot::Vector2i &coord);

protected:
	static void _bind_methods();
};

} // namespace toprogue
