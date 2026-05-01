#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

class GenerationContext : public godot::RefCounted {
	GDCLASS(GenerationContext, godot::RefCounted);

public:
	godot::Vector2i chunk_coord;
	int64_t world_seed = 0;
	godot::Dictionary stage_params;

	GenerationContext() = default;

	godot::Vector2i get_chunk_coord() const { return chunk_coord; }
	void set_chunk_coord(const godot::Vector2i &v) { chunk_coord = v; }
	int64_t get_world_seed() const { return world_seed; }
	void set_world_seed(int64_t v) { world_seed = v; }
	godot::Dictionary get_stage_params() const { return stage_params; }
	void set_stage_params(const godot::Dictionary &v) { stage_params = v; }

protected:
	static void _bind_methods();
};

} // namespace toprogue
