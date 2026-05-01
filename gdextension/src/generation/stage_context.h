#pragma once

#include "../resources/biome_def.h"
#include "../resources/template_pack.h"

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>

namespace toprogue {

struct StageContext {
	godot::Vector2i chunk_coord;
	uint32_t world_seed;
	godot::Ref<BiomeDef> biome;
	godot::PackedByteArray stamp_bytes;

	int air_id = 0;
	int wood_id = 0;
	int stone_id = 0;
};

} // namespace toprogue
