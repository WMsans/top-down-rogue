#pragma once

#include <godot_cpp/classes/resource.hpp>

namespace toprogue {

class TerrainCell : public godot::Resource {
	GDCLASS(TerrainCell, godot::Resource);

public:
	int material_id = 0;
	bool is_solid = false;
	bool is_fluid = false;
	double damage = 0.0;

	TerrainCell();

	void init_args(int p_material_id, bool p_is_solid, bool p_is_fluid, double p_damage);

	int get_material_id() const { return material_id; }
	void set_material_id(int v) { material_id = v; }
	bool get_is_solid() const { return is_solid; }
	void set_is_solid(bool v) { is_solid = v; }
	bool get_is_fluid() const { return is_fluid; }
	void set_is_fluid(bool v) { is_fluid = v; }
	double get_damage() const { return damage; }
	void set_damage(double v) { damage = v; }

protected:
	static void _bind_methods();
};

} // namespace toprogue
