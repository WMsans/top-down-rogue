#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace toprogue {

class MaterialDef : public godot::RefCounted {
	GDCLASS(MaterialDef, godot::RefCounted);

protected:
	static void _bind_methods();

public:
	int     id           = 0;
	godot::String name;
	godot::String texture_path;
	bool    flammable    = false;
	int     ignition_temp = 0;
	int     burn_health  = 0;
	bool    has_collider = false;
	bool    has_wall_extension = false;
	godot::Color tint_color    = godot::Color(0, 0, 0, 0);
	bool    fluid        = false;
	int     damage       = 0;
	double  glow         = 1.0;

	int     get_id() const            { return id; }
	void    set_id(int v)             { id = v; }
	godot::String get_name() const    { return name; }
	void    set_name(const godot::String &v) { name = v; }
	godot::String get_texture_path() const { return texture_path; }
	void    set_texture_path(const godot::String &v) { texture_path = v; }
	bool    get_flammable() const     { return flammable; }
	void    set_flammable(bool v)     { flammable = v; }
	int     get_ignition_temp() const { return ignition_temp; }
	void    set_ignition_temp(int v)  { ignition_temp = v; }
	int     get_burn_health() const   { return burn_health; }
	void    set_burn_health(int v)    { burn_health = v; }
	bool    get_has_collider() const  { return has_collider; }
	void    set_has_collider(bool v)  { has_collider = v; }
	bool    get_has_wall_extension() const { return has_wall_extension; }
	void    set_has_wall_extension(bool v) { has_wall_extension = v; }
	godot::Color get_tint_color() const { return tint_color; }
	void    set_tint_color(const godot::Color &v) { tint_color = v; }
	bool    get_fluid() const         { return fluid; }
	void    set_fluid(bool v)         { fluid = v; }
	int     get_damage() const        { return damage; }
	void    set_damage(int v)         { damage = v; }
	double  get_glow() const          { return glow; }
	void    set_glow(double v)        { glow = v; }
};

class MaterialTable : public godot::Object {
	GDCLASS(MaterialTable, godot::Object);

	static MaterialTable *singleton;

	godot::TypedArray<MaterialDef> materials;
	godot::HashMap<godot::String, int> by_name;

	int MAT_AIR   = -1;
	int MAT_WOOD  = -1;
	int MAT_STONE = -1;
	int MAT_GAS   = -1;
	int MAT_LAVA  = -1;
	int MAT_DIRT  = -1;
	int MAT_COAL  = -1;
	int MAT_ICE   = -1;
	int MAT_WATER = -1;

	void _populate();
	int  _add(const char *p_name,
			  const char *p_texture_path,
			  bool p_flammable,
			  int p_ignition_temp,
			  int p_burn_health,
			  bool p_has_collider,
			  bool p_has_wall_extension,
			  godot::Color p_tint = godot::Color(0, 0, 0, 0),
			  bool p_fluid = false,
			  int p_damage = 0,
			  double p_glow = 1.0);

protected:
	static void _bind_methods();

public:
	MaterialTable();
	~MaterialTable();

	static MaterialTable *get_singleton();

	godot::TypedArray<MaterialDef> get_materials() const { return materials; }

	bool   is_flammable(int p_id) const;
	int    get_ignition_temp(int p_id) const;
	bool   has_collider(int p_id) const;
	bool   has_wall_extension(int p_id) const;
	godot::Color get_tint_color(int p_id) const;
	godot::PackedInt32Array get_fluids() const;
	bool   is_fluid(int p_id) const;
	int    get_damage(int p_id) const;
	double get_glow(int p_id) const;

	int get_MAT_AIR()   const { return MAT_AIR; }
	int get_MAT_WOOD()  const { return MAT_WOOD; }
	int get_MAT_STONE() const { return MAT_STONE; }
	int get_MAT_GAS()   const { return MAT_GAS; }
	int get_MAT_LAVA()  const { return MAT_LAVA; }
	int get_MAT_DIRT()  const { return MAT_DIRT; }
	int get_MAT_COAL()  const { return MAT_COAL; }
	int get_MAT_ICE()   const { return MAT_ICE; }
	int get_MAT_WATER() const { return MAT_WATER; }
};

} // namespace toprogue
