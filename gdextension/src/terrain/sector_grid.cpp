#include "sector_grid.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

void RoomSlot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_is_empty"), &RoomSlot::get_is_empty);
	ClassDB::bind_method(D_METHOD("set_is_empty", "v"), &RoomSlot::set_is_empty);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_empty"), "set_is_empty", "get_is_empty");

	ClassDB::bind_method(D_METHOD("get_is_boss"), &RoomSlot::get_is_boss);
	ClassDB::bind_method(D_METHOD("set_is_boss", "v"), &RoomSlot::set_is_boss);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_boss"), "set_is_boss", "get_is_boss");

	ClassDB::bind_method(D_METHOD("get_template_index"), &RoomSlot::get_template_index);
	ClassDB::bind_method(D_METHOD("set_template_index", "v"), &RoomSlot::set_template_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "template_index"),
			"set_template_index", "get_template_index");

	ClassDB::bind_method(D_METHOD("get_rotation"), &RoomSlot::get_rotation);
	ClassDB::bind_method(D_METHOD("set_rotation", "v"), &RoomSlot::set_rotation);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "rotation"), "set_rotation", "get_rotation");

	ClassDB::bind_method(D_METHOD("get_template_size"), &RoomSlot::get_template_size);
	ClassDB::bind_method(D_METHOD("set_template_size", "v"), &RoomSlot::set_template_size);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "template_size"),
			"set_template_size", "get_template_size");
}

void SectorGrid::init_args(int64_t world_seed, const Ref<BiomeDef> &biome) {
	_seed = world_seed;
	_biome = biome;
}

Vector2i SectorGrid::world_to_sector(const Vector2 &world_pos) const {
	return Vector2i(
			static_cast<int>(std::floor(world_pos.x / SECTOR_SIZE_PX)),
			static_cast<int>(std::floor(world_pos.y / SECTOR_SIZE_PX)));
}

Vector2i SectorGrid::sector_to_world_center(const Vector2i &coord) const {
	return Vector2i(
			coord.x * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2,
			coord.y * SECTOR_SIZE_PX + SECTOR_SIZE_PX / 2);
}

int SectorGrid::chebyshev_distance(const Vector2i &a, const Vector2i &b) const {
	return MAX(std::abs(a.x - b.x), std::abs(a.y - b.y));
}

Ref<RoomSlot> SectorGrid::resolve_sector(const Vector2i &coord) const {
	Ref<RoomSlot> slot;
	slot.instantiate();

	int dist = chebyshev_distance(coord, Vector2i(0, 0));

	if (dist > BOSS_RING_DISTANCE) {
		slot->is_empty = true;
		return slot;
	}

	if (_biome.is_null()) {
		UtilityFunctions::push_error("SectorGrid.resolve_sector: biome is null");
		slot->is_empty = true;
		return slot;
	}

	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	// Mirrors GDScript: rng.seed = hash(_seed ^ x*73856093 ^ y*19349663)
	int64_t mix = _seed ^ (static_cast<int64_t>(coord.x) * 73856093LL) ^ (static_cast<int64_t>(coord.y) * 19349663LL);
	rng->set_seed(static_cast<uint64_t>(mix));

	if (dist == BOSS_RING_DISTANCE) {
		TypedArray<RoomTemplate> bosses = _biome->boss_templates;
		if (bosses.is_empty()) {
			slot->is_empty = true;
			return slot;
		}
		slot->is_boss = true;
		slot->template_index = static_cast<int>(rng->randi() % static_cast<uint32_t>(bosses.size()));
		Ref<RoomTemplate> boss_tmpl = bosses[slot->template_index];
		slot->rotation = boss_tmpl->rotatable ? (static_cast<int>(rng->randi() % 4) * 90) : 0;
		slot->template_size = boss_tmpl->size_class;
		return slot;
	}

	TypedArray<RoomTemplate> rooms = _biome->room_templates;
	if (rooms.is_empty()) {
		slot->is_empty = true;
		return slot;
	}

	double total = EMPTY_WEIGHT;
	for (int i = 0; i < rooms.size(); i++) {
		Ref<RoomTemplate> t = rooms[i];
		total += t->weight;
	}

	double roll = rng->randf() * total;
	if (roll < EMPTY_WEIGHT) {
		slot->is_empty = true;
		return slot;
	}

	double cumulative = EMPTY_WEIGHT;
	for (int i = 0; i < rooms.size(); i++) {
		Ref<RoomTemplate> t = rooms[i];
		cumulative += t->weight;
		if (roll < cumulative) {
			slot->template_index = i;
			slot->rotation = t->rotatable ? (static_cast<int>(rng->randi() % 4) * 90) : 0;
			slot->template_size = t->size_class;
			return slot;
		}
	}

	slot->is_empty = true;
	return slot;
}

Ref<RoomTemplate> SectorGrid::get_template_for_slot(const Ref<RoomSlot> &slot) const {
	if (slot.is_null() || slot->is_empty) {
		return Ref<RoomTemplate>();
	}
	if (_biome.is_null()) {
		return Ref<RoomTemplate>();
	}
	if (slot->is_boss) {
		TypedArray<RoomTemplate> bosses = _biome->boss_templates;
		if (slot->template_index < 0 || slot->template_index >= bosses.size()) {
			return Ref<RoomTemplate>();
		}
		return bosses[slot->template_index];
	}
	TypedArray<RoomTemplate> rooms = _biome->room_templates;
	if (slot->template_index < 0 || slot->template_index >= rooms.size()) {
		return Ref<RoomTemplate>();
	}
	return rooms[slot->template_index];
}

void SectorGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init_args", "world_seed", "biome"), &SectorGrid::init_args);
	ClassDB::bind_method(D_METHOD("world_to_sector", "world_pos"), &SectorGrid::world_to_sector);
	ClassDB::bind_method(D_METHOD("sector_to_world_center", "coord"), &SectorGrid::sector_to_world_center);
	ClassDB::bind_method(D_METHOD("chebyshev_distance", "a", "b"), &SectorGrid::chebyshev_distance);
	ClassDB::bind_method(D_METHOD("resolve_sector", "coord"), &SectorGrid::resolve_sector);
	ClassDB::bind_method(D_METHOD("get_template_for_slot", "slot"), &SectorGrid::get_template_for_slot);

	ClassDB::bind_static_method("SectorGrid", D_METHOD("get_sector_size_px"),
			&SectorGrid::get_sector_size_px);
	ClassDB::bind_static_method("SectorGrid", D_METHOD("get_boss_ring_distance"),
			&SectorGrid::get_boss_ring_distance);
	ClassDB::bind_static_method("SectorGrid", D_METHOD("get_empty_weight"),
			&SectorGrid::get_empty_weight);
}

} // namespace toprogue
