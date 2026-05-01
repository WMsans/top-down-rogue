#pragma once

#include "pool_def.h"
#include "room_template.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace toprogue {

class BiomeDef : public godot::Resource {
	GDCLASS(BiomeDef, godot::Resource);

public:
	godot::String display_name;
	double cave_noise_scale = 0.008;
	double cave_threshold = 0.42;
	double ridge_weight = 0.3;
	double ridge_scale = 0.012;
	int octaves = 5;
	int background_material = 2; // STONE
	godot::TypedArray<PoolDef> pool_materials;
	godot::TypedArray<RoomTemplate> room_templates;
	godot::TypedArray<RoomTemplate> boss_templates;
	int secret_ring_thickness = 3;
	godot::Color tint = godot::Color(1, 1, 1, 1);
	bool use_simplex_cave_generator = false;

	BiomeDef() = default;

	godot::String get_display_name() const { return display_name; }
	void set_display_name(const godot::String &v) { display_name = v; }
	double get_cave_noise_scale() const { return cave_noise_scale; }
	void set_cave_noise_scale(double v) { cave_noise_scale = v; }
	double get_cave_threshold() const { return cave_threshold; }
	void set_cave_threshold(double v) { cave_threshold = v; }
	double get_ridge_weight() const { return ridge_weight; }
	void set_ridge_weight(double v) { ridge_weight = v; }
	double get_ridge_scale() const { return ridge_scale; }
	void set_ridge_scale(double v) { ridge_scale = v; }
	int get_octaves() const { return octaves; }
	void set_octaves(int v) { octaves = v; }
	int get_background_material() const { return background_material; }
	void set_background_material(int v) { background_material = v; }

	godot::TypedArray<PoolDef> get_pool_materials() const { return pool_materials; }
	void set_pool_materials(const godot::TypedArray<PoolDef> &v) { pool_materials = v; }
	godot::TypedArray<RoomTemplate> get_room_templates() const { return room_templates; }
	void set_room_templates(const godot::TypedArray<RoomTemplate> &v) { room_templates = v; }
	godot::TypedArray<RoomTemplate> get_boss_templates() const { return boss_templates; }
	void set_boss_templates(const godot::TypedArray<RoomTemplate> &v) { boss_templates = v; }

	int get_secret_ring_thickness() const { return secret_ring_thickness; }
	void set_secret_ring_thickness(int v) { secret_ring_thickness = v; }
	godot::Color get_tint() const { return tint; }
	void set_tint(const godot::Color &v) { tint = v; }
	bool get_use_simplex_cave_generator() const { return use_simplex_cave_generator; }
	void set_use_simplex_cave_generator(bool v) { use_simplex_cave_generator = v; }

protected:
	static void _bind_methods();
};

} // namespace toprogue
