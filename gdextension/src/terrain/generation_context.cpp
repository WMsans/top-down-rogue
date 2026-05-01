#include "generation_context.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void GenerationContext::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_chunk_coord"), &GenerationContext::get_chunk_coord);
	ClassDB::bind_method(D_METHOD("set_chunk_coord", "v"), &GenerationContext::set_chunk_coord);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "chunk_coord"),
			"set_chunk_coord", "get_chunk_coord");

	ClassDB::bind_method(D_METHOD("get_world_seed"), &GenerationContext::get_world_seed);
	ClassDB::bind_method(D_METHOD("set_world_seed", "v"), &GenerationContext::set_world_seed);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "world_seed"),
			"set_world_seed", "get_world_seed");

	ClassDB::bind_method(D_METHOD("get_stage_params"), &GenerationContext::get_stage_params);
	ClassDB::bind_method(D_METHOD("set_stage_params", "v"), &GenerationContext::set_stage_params);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "stage_params"),
			"set_stage_params", "get_stage_params");
}

} // namespace toprogue
