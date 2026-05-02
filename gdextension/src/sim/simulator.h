#pragma once

#include "../terrain/chunk.h"
#include "chunk_view.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <cstdint>
#include <vector>

namespace toprogue {

class Simulator : public godot::RefCounted {
	GDCLASS(Simulator, godot::RefCounted);

	int64_t _world_seed = 0;
	int _frame_index = 0;
	godot::Dictionary _chunks;

	// Phase dispatch temporary storage
	godot::Vector<Chunk *> _phase_chunks;
	godot::Vector<ChunkView> _phase_views;
	uint32_t _current_frame_seed = 0;

public:
	void set_world_seed(int64_t seed);
	void set_chunks(const godot::Dictionary &chunks);
	void tick();
	void add_active(Chunk *chunk);
	void remove_active(Chunk *chunk);

protected:
	static void _bind_methods();

private:
	std::vector<Chunk *> _active;
	void run_phase(int phase_x, int phase_y);
	void _group_task_body(int32_t index);
	void tick_chunk(ChunkView &view);
	void rotate_dirty_rects();
	void upload_dirty_textures();
};

} // namespace toprogue
