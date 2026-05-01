#pragma once

#include "../resources/biome_def.h"
#include "../terrain/chunk.h"
#include "stage_context.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace toprogue {

class Generator : public godot::RefCounted {
	GDCLASS(Generator, godot::RefCounted);

public:
	Generator();

	void generate_chunks(
			const godot::Dictionary &chunks,
			const godot::TypedArray<godot::Vector2i> &new_coords,
			int64_t world_seed,
			const godot::Ref<BiomeDef> &biome,
			const godot::PackedByteArray &stamp_bytes);

protected:
	static void _bind_methods();

private:
	int air_id_ = 0;
	int wood_id_ = 0;
	int stone_id_ = 0;

	// Worker-thread state (only one generate_chunks call runs at a time).
	std::vector<Chunk *> _current_jobs;
	std::vector<StageContext> _current_ctxs;

	void run_pipeline(Chunk *chunk, const StageContext &ctx) const;
	void _run_one_indexed(int idx);
};

} // namespace toprogue
