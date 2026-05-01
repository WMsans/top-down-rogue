#pragma once

#include <godot_cpp/classes/resource.hpp>

namespace toprogue {

class PoolDef : public godot::Resource {
	GDCLASS(PoolDef, godot::Resource);

public:
	int material_id = 0;
	double noise_scale = 0.005;
	double noise_threshold = 0.6;
	int seed_offset = 0;

	PoolDef() = default;

	int get_material_id() const { return material_id; }
	void set_material_id(int v) { material_id = v; }
	double get_noise_scale() const { return noise_scale; }
	void set_noise_scale(double v) { noise_scale = v; }
	double get_noise_threshold() const { return noise_threshold; }
	void set_noise_threshold(double v) { noise_threshold = v; }
	int get_seed_offset() const { return seed_offset; }
	void set_seed_offset(int v) { seed_offset = v; }

protected:
	static void _bind_methods();
};

} // namespace toprogue
