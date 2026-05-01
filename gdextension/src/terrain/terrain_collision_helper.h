#pragma once

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace toprogue {

// Mirrors src/core/terrain_collision_helper.gd's surface, minus the GPU path.
class TerrainCollisionHelper : public godot::RefCounted {
	GDCLASS(TerrainCollisionHelper, godot::RefCounted);

public:
	static constexpr int CHUNK_SIZE = 256;
	static constexpr double COLLISION_REBUILD_INTERVAL = 0.2;
	static constexpr int COLLISIONS_PER_FRAME = 4;

	godot::Node2D *world_manager = nullptr;

	TerrainCollisionHelper() = default;

	void rebuild_dirty(const godot::Dictionary &chunks, double delta);
	void rebuild_chunk_collision_cpu(const godot::Variant &chunk);

	godot::Node2D *get_world_manager() const { return world_manager; }
	void set_world_manager(godot::Node2D *v) { world_manager = v; }

protected:
	static void _bind_methods();

private:
	double _collision_rebuild_timer = 0.0;
	int _collision_rebuild_index = 0;
};

} // namespace toprogue
