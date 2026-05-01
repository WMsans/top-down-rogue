#include "pool_def.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void PoolDef::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_material_id"), &PoolDef::get_material_id);
	ClassDB::bind_method(D_METHOD("set_material_id", "v"), &PoolDef::set_material_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "material_id"), "set_material_id", "get_material_id");

	ClassDB::bind_method(D_METHOD("get_noise_scale"), &PoolDef::get_noise_scale);
	ClassDB::bind_method(D_METHOD("set_noise_scale", "v"), &PoolDef::set_noise_scale);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "noise_scale"), "set_noise_scale", "get_noise_scale");

	ClassDB::bind_method(D_METHOD("get_noise_threshold"), &PoolDef::get_noise_threshold);
	ClassDB::bind_method(D_METHOD("set_noise_threshold", "v"), &PoolDef::set_noise_threshold);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "noise_threshold"),
			"set_noise_threshold", "get_noise_threshold");

	ClassDB::bind_method(D_METHOD("get_seed_offset"), &PoolDef::get_seed_offset);
	ClassDB::bind_method(D_METHOD("set_seed_offset", "v"), &PoolDef::set_seed_offset);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "seed_offset"), "set_seed_offset", "get_seed_offset");
}

} // namespace toprogue
