#include "material_table.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace toprogue {

MaterialTable *MaterialTable::singleton = nullptr;

// ---------------- MaterialDef ----------------

void MaterialDef::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_id"), &MaterialDef::get_id);
	ClassDB::bind_method(D_METHOD("set_id", "v"), &MaterialDef::set_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "id"), "set_id", "get_id");

	ClassDB::bind_method(D_METHOD("get_name"), &MaterialDef::get_name);
	ClassDB::bind_method(D_METHOD("set_name", "v"), &MaterialDef::set_name);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");

	ClassDB::bind_method(D_METHOD("get_texture_path"), &MaterialDef::get_texture_path);
	ClassDB::bind_method(D_METHOD("set_texture_path", "v"), &MaterialDef::set_texture_path);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "texture_path"), "set_texture_path", "get_texture_path");

	ClassDB::bind_method(D_METHOD("get_flammable"), &MaterialDef::get_flammable);
	ClassDB::bind_method(D_METHOD("set_flammable", "v"), &MaterialDef::set_flammable);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "flammable"), "set_flammable", "get_flammable");

	ClassDB::bind_method(D_METHOD("get_ignition_temp"), &MaterialDef::get_ignition_temp);
	ClassDB::bind_method(D_METHOD("set_ignition_temp", "v"), &MaterialDef::set_ignition_temp);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ignition_temp"), "set_ignition_temp", "get_ignition_temp");

	ClassDB::bind_method(D_METHOD("get_burn_health"), &MaterialDef::get_burn_health);
	ClassDB::bind_method(D_METHOD("set_burn_health", "v"), &MaterialDef::set_burn_health);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "burn_health"), "set_burn_health", "get_burn_health");

	ClassDB::bind_method(D_METHOD("get_has_collider"), &MaterialDef::get_has_collider);
	ClassDB::bind_method(D_METHOD("set_has_collider", "v"), &MaterialDef::set_has_collider);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "has_collider"), "set_has_collider", "get_has_collider");

	ClassDB::bind_method(D_METHOD("get_has_wall_extension"), &MaterialDef::get_has_wall_extension);
	ClassDB::bind_method(D_METHOD("set_has_wall_extension", "v"), &MaterialDef::set_has_wall_extension);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "has_wall_extension"), "set_has_wall_extension", "get_has_wall_extension");

	ClassDB::bind_method(D_METHOD("get_tint_color"), &MaterialDef::get_tint_color);
	ClassDB::bind_method(D_METHOD("set_tint_color", "v"), &MaterialDef::set_tint_color);
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "tint_color"), "set_tint_color", "get_tint_color");

	ClassDB::bind_method(D_METHOD("get_fluid"), &MaterialDef::get_fluid);
	ClassDB::bind_method(D_METHOD("set_fluid", "v"), &MaterialDef::set_fluid);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "fluid"), "set_fluid", "get_fluid");

	ClassDB::bind_method(D_METHOD("get_damage"), &MaterialDef::get_damage);
	ClassDB::bind_method(D_METHOD("set_damage", "v"), &MaterialDef::set_damage);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "damage"), "set_damage", "get_damage");

	ClassDB::bind_method(D_METHOD("get_glow"), &MaterialDef::get_glow);
	ClassDB::bind_method(D_METHOD("set_glow", "v"), &MaterialDef::set_glow);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "glow"), "set_glow", "get_glow");

	ClassDB::bind_method(D_METHOD("get_kind"), &MaterialDef::get_kind);
	ClassDB::bind_method(D_METHOD("set_kind", "v"), &MaterialDef::set_kind);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "kind"), "set_kind", "get_kind");

	ClassDB::bind_method(D_METHOD("get_density"), &MaterialDef::get_density);
	ClassDB::bind_method(D_METHOD("set_density", "v"), &MaterialDef::set_density);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "density"), "set_density", "get_density");

	ClassDB::bind_method(D_METHOD("get_viscosity"), &MaterialDef::get_viscosity);
	ClassDB::bind_method(D_METHOD("set_viscosity", "v"), &MaterialDef::set_viscosity);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "viscosity"), "set_viscosity", "get_viscosity");

	ClassDB::bind_method(D_METHOD("get_dispersion"), &MaterialDef::get_dispersion);
	ClassDB::bind_method(D_METHOD("set_dispersion", "v"), &MaterialDef::set_dispersion);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "dispersion"), "set_dispersion", "get_dispersion");

	ClassDB::bind_method(D_METHOD("get_diffusion_rate"), &MaterialDef::get_diffusion_rate);
	ClassDB::bind_method(D_METHOD("set_diffusion_rate", "v"), &MaterialDef::set_diffusion_rate);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "diffusion_rate"), "set_diffusion_rate", "get_diffusion_rate");

	ClassDB::bind_method(D_METHOD("get_max_temp"), &MaterialDef::get_max_temp);
	ClassDB::bind_method(D_METHOD("set_max_temp", "v"), &MaterialDef::set_max_temp);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_temp"), "set_max_temp", "get_max_temp");
}

// ---------------- MaterialTable ----------------

MaterialTable::MaterialTable() {
	singleton = this;
	_populate();
}

MaterialTable::~MaterialTable() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

MaterialTable *MaterialTable::get_singleton() {
	return singleton;
}

int MaterialTable::_add(const char *p_name,
		const char *p_texture_path,
		bool p_flammable,
		int p_ignition_temp,
		int p_burn_health,
		bool p_has_collider,
		bool p_has_wall_extension,
		Color p_tint,
		bool p_fluid,
		int p_damage,
		double p_glow) {
	Ref<MaterialDef> def;
	def.instantiate();
	def->name = String::utf8(p_name);
	def->texture_path = String::utf8(p_texture_path);
	def->flammable = p_flammable;
	def->ignition_temp = p_ignition_temp;
	def->burn_health = p_burn_health;
	def->has_collider = p_has_collider;
	def->has_wall_extension = p_has_wall_extension;
	def->tint_color = p_tint;
	def->fluid = p_fluid;
	def->damage = p_damage;
	def->glow = p_glow;

	int id = (int)materials.size();
	def->id = id;
	materials.push_back(def);
	by_name[def->name] = id;
	return id;
}

void MaterialTable::_populate() {
	MAT_AIR = _add("AIR", "", false, 0, 0, false, false);

	MAT_WOOD = _add("WOOD", "res://textures/Environments/Walls/plank.png",
			true, 180, 255, true, true);

	MAT_STONE = _add("STONE", "res://textures/Environments/Walls/stone.png",
			false, 0, 0, true, true);

	MAT_GAS = _add("GAS", "", false, 0, 0, false, false,
			Color(0.4, 0.9, 0.3, 1.0), /*fluid=*/true);

	MAT_LAVA = _add("LAVA", "", false, 0, 0, false, false,
			Color(0.9, 0.4, 0.1, 1.0),
			/*fluid=*/true, /*damage=*/10, /*glow=*/10.0);

	MAT_DIRT = _add("DIRT", "res://textures/Environments/Walls/dirt.png",
			false, 0, 0, true, true,
			Color(0.45, 0.32, 0.18, 1.0));

	MAT_COAL = _add("COAL", "res://textures/Environments/Walls/coal.png",
			true, 220, 200, true, true,
			Color(0.12, 0.12, 0.14, 1.0),
			/*fluid=*/false, /*damage=*/0, /*glow=*/20.0);

	MAT_ICE = _add("ICE", "res://textures/Environments/Walls/ice.png",
			false, 0, 0, true, true,
			Color(0.7, 0.85, 0.95, 1.0));

	MAT_WATER = _add("WATER", "", false, 0, 0, true, true,
			Color(0.2, 0.45, 0.75, 1.0),
			/*fluid=*/true);

	// --- Populate simulation parameters (Task 2) ---
	// GLSL-derived; tune in follow-up gameplay work.

	auto set_sim = [this](int id, MaterialKind kind, uint8_t density, uint8_t viscosity,
			uint8_t dispersion, uint8_t diffusion_rate, uint8_t max_temp) {
		if (id < 0 || id >= (int)materials.size()) return;
		Ref<MaterialDef> d = materials[id];
		if (d.is_valid()) {
			d->kind = kind;
			d->density = density;
			d->viscosity = viscosity;
			d->dispersion = dispersion;
			d->diffusion_rate = diffusion_rate;
			d->max_temp = max_temp;
		}
	};

	set_sim(MAT_AIR, MaterialKind::NONE, 0, 0, 0, 0, 255);
	set_sim(MAT_WOOD, MaterialKind::SOLID, 0, 0, 0, 4, 255);
	set_sim(MAT_STONE, MaterialKind::SOLID, 0, 0, 0, 0, 255);
	set_sim(MAT_GAS, MaterialKind::GAS, 128, 0, 4, 0, 255);
	set_sim(MAT_LAVA, MaterialKind::LIQUID, 0, 192, 0, 0, 255);
	set_sim(MAT_DIRT, MaterialKind::SOLID, 0, 0, 0, 0, 255);
	set_sim(MAT_COAL, MaterialKind::SOLID, 0, 0, 0, 4, 255);
	set_sim(MAT_ICE, MaterialKind::SOLID, 0, 0, 0, 0, 255);
	set_sim(MAT_WATER, MaterialKind::LIQUID, 0, 0, 0, 0, 255);
}

bool MaterialTable::is_flammable(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return false;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() && d->flammable;
}

int MaterialTable::get_ignition_temp(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->ignition_temp : 0;
}

bool MaterialTable::has_collider(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return false;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() && d->has_collider;
}

bool MaterialTable::has_wall_extension(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return false;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() && d->has_wall_extension;
}

Color MaterialTable::get_tint_color(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return Color(0, 0, 0, 0);
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->tint_color : Color(0, 0, 0, 0);
}

PackedInt32Array MaterialTable::get_fluids() const {
	PackedInt32Array out;
	for (int i = 0; i < (int)materials.size(); i++) {
		Ref<MaterialDef> d = materials[i];
		if (d.is_valid() && d->fluid) {
			out.push_back(d->id);
		}
	}
	return out;
}

bool MaterialTable::is_fluid(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return false;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() && d->fluid;
}

int MaterialTable::get_damage(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->damage : 0;
}

double MaterialTable::get_glow(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 1.0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->glow : 1.0;
}

int MaterialTable::get_kind_int(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? static_cast<int>(d->kind) : 0;
}

MaterialKind MaterialTable::kind_of(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return MaterialKind::SOLID;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->kind : MaterialKind::SOLID;
}

int MaterialTable::get_density(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->density : 0;
}

int MaterialTable::get_viscosity(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->viscosity : 0;
}

int MaterialTable::get_dispersion(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->dispersion : 0;
}

int MaterialTable::get_diffusion_rate(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 0;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->diffusion_rate : 0;
}

int MaterialTable::get_max_temp(int p_id) const {
	if (p_id < 0 || p_id >= (int)materials.size()) {
		return 255;
	}
	Ref<MaterialDef> d = materials[p_id];
	return d.is_valid() ? d->max_temp : 255;
}

void MaterialTable::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_materials"), &MaterialTable::get_materials);
	ClassDB::bind_method(D_METHOD("is_flammable", "material_id"), &MaterialTable::is_flammable);
	ClassDB::bind_method(D_METHOD("get_ignition_temp", "material_id"), &MaterialTable::get_ignition_temp);
	ClassDB::bind_method(D_METHOD("has_collider", "material_id"), &MaterialTable::has_collider);
	ClassDB::bind_method(D_METHOD("has_wall_extension", "material_id"), &MaterialTable::has_wall_extension);
	ClassDB::bind_method(D_METHOD("get_tint_color", "material_id"), &MaterialTable::get_tint_color);
	ClassDB::bind_method(D_METHOD("get_fluids"), &MaterialTable::get_fluids);
	ClassDB::bind_method(D_METHOD("is_fluid", "material_id"), &MaterialTable::is_fluid);
	ClassDB::bind_method(D_METHOD("get_damage", "material_id"), &MaterialTable::get_damage);
	ClassDB::bind_method(D_METHOD("get_glow", "material_id"), &MaterialTable::get_glow);
	ClassDB::bind_method(D_METHOD("get_kind", "material_id"), &MaterialTable::get_kind_int);
	ClassDB::bind_method(D_METHOD("get_density", "material_id"), &MaterialTable::get_density);
	ClassDB::bind_method(D_METHOD("get_viscosity", "material_id"), &MaterialTable::get_viscosity);
	ClassDB::bind_method(D_METHOD("get_dispersion", "material_id"), &MaterialTable::get_dispersion);
	ClassDB::bind_method(D_METHOD("get_diffusion_rate", "material_id"), &MaterialTable::get_diffusion_rate);
	ClassDB::bind_method(D_METHOD("get_max_temp", "material_id"), &MaterialTable::get_max_temp);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "materials",
						 PROPERTY_HINT_ARRAY_TYPE, "MaterialDef",
						 PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY),
			"", "get_materials");

	ClassDB::bind_method(D_METHOD("get_MAT_AIR"), &MaterialTable::get_MAT_AIR);
	ClassDB::bind_method(D_METHOD("get_MAT_WOOD"), &MaterialTable::get_MAT_WOOD);
	ClassDB::bind_method(D_METHOD("get_MAT_STONE"), &MaterialTable::get_MAT_STONE);
	ClassDB::bind_method(D_METHOD("get_MAT_GAS"), &MaterialTable::get_MAT_GAS);
	ClassDB::bind_method(D_METHOD("get_MAT_LAVA"), &MaterialTable::get_MAT_LAVA);
	ClassDB::bind_method(D_METHOD("get_MAT_DIRT"), &MaterialTable::get_MAT_DIRT);
	ClassDB::bind_method(D_METHOD("get_MAT_COAL"), &MaterialTable::get_MAT_COAL);
	ClassDB::bind_method(D_METHOD("get_MAT_ICE"), &MaterialTable::get_MAT_ICE);
	ClassDB::bind_method(D_METHOD("get_MAT_WATER"), &MaterialTable::get_MAT_WATER);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_AIR", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_AIR");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_WOOD", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_WOOD");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_STONE", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_STONE");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_GAS", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_GAS");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_LAVA", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_LAVA");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_DIRT", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_DIRT");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_COAL", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_COAL");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_ICE", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_ICE");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "MAT_WATER", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_MAT_WATER");
}

} // namespace toprogue
