#include "terrain_modifier.h"

#include "../sim/material_table.h"
#include "terrain_physical.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

void TerrainModifier::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_chunks", "chunks"), &TerrainModifier::set_chunks);
	ClassDB::bind_method(D_METHOD("set_terrain_physical", "tp"), &TerrainModifier::set_terrain_physical);
	ClassDB::bind_method(D_METHOD("place_gas", "world_pos", "radius", "density", "velocity"),
			&TerrainModifier::place_gas, DEFVAL(Vector2i(0, 0)));
	ClassDB::bind_method(D_METHOD("place_lava", "world_pos", "radius"),
			&TerrainModifier::place_lava);
	ClassDB::bind_method(D_METHOD("place_fire", "world_pos", "radius"),
			&TerrainModifier::place_fire);
	ClassDB::bind_method(D_METHOD("place_material", "world_pos", "radius", "material_id"),
			&TerrainModifier::place_material);
	ClassDB::bind_method(D_METHOD("disperse_materials_in_arc", "origin", "direction", "radius",
								 "arc_angle", "push_speed", "materials"),
			&TerrainModifier::disperse_materials_in_arc);
	ClassDB::bind_method(D_METHOD("clear_and_push_materials_in_arc", "origin", "direction",
								 "radius", "arc_angle", "push_speed", "edge_fraction", "materials"),
			&TerrainModifier::clear_and_push_materials_in_arc);
}

void TerrainModifier::set_chunks(const Dictionary &chunks) {
	_chunks = chunks;
}

void TerrainModifier::set_terrain_physical(TerrainPhysical *tp) {
	_terrain_physical = tp;
}

static constexpr int CHUNK_SIZE = 256;

void TerrainModifier::mark_dirty(Chunk *c, int x_min, int y_min, int x_max, int y_max) {
	if (!c) {
		return;
	}
	c->extend_next_dirty_rect(x_min, y_min, x_max, y_max);
	c->set_sleeping(false);
	c->set_collider_dirty(true);
}

// --- place_gas -----------------------------------------------------------

void TerrainModifier::place_gas(Vector2 world_pos, float radius, int density,
		Vector2i velocity) {
	int center_x = static_cast<int>(std::floor(world_pos.x));
	int center_y = static_cast<int>(std::floor(world_pos.y));
	int r = static_cast<int>(std::ceil(radius));

	Dictionary affected;
	for (int dx = -r; dx <= r; dx++) {
		for (int dy = -r; dy <= r; dy++) {
			if (dx * dx + dy * dy > r * r) {
				continue;
			}
			int wx = center_x + dx;
			int wy = center_y + dy;
			Vector2i chunk_coord(
					static_cast<int>(std::floor(static_cast<float>(wx) / CHUNK_SIZE)),
					static_cast<int>(std::floor(static_cast<float>(wy) / CHUNK_SIZE)));
			if (!_chunks.has(chunk_coord)) {
				continue;
			}
			Vector2i local(((wx % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
					((wy % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE);
			if (!affected.has(chunk_coord)) {
				affected[chunk_coord] = Array();
			}
			((Array)affected[chunk_coord]).push_back(local);
		}
	}

	int gas_id = MaterialTable::get_singleton()->get_MAT_GAS();
	int air_id = MaterialTable::get_singleton()->get_MAT_AIR();
	int clamped_density = std::min(std::max(density, 0), 255);
	int vx_clamped = std::min(std::max(velocity.x + 8, 0), 15);
	int vy_clamped = std::min(std::max(velocity.y + 8, 0), 15);
	uint8_t packed_vel = static_cast<uint8_t>((vx_clamped << 4) | vy_clamped);

	Array keys = affected.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i chunk_coord = keys[i];
		Ref<Chunk> chunk_ref = _chunks[chunk_coord];
		if (!chunk_ref.is_valid()) {
			continue;
		}
		Chunk *chunk = chunk_ref.ptr();

		Array locals = affected[chunk_coord];
		bool modified = false;
		for (int j = 0; j < locals.size(); j++) {
			Vector2i local = locals[j];
			Cell &cell = chunk->cells[local.y * CHUNK_SIZE + local.x];
			if (cell.material != air_id) {
				continue;
			}
			cell.material = static_cast<uint8_t>(gas_id);
			cell.health = static_cast<uint8_t>(clamped_density);
			cell.temperature = 0;
			cell.flags = packed_vel;
			modified = true;
		}
		if (modified) {
			mark_dirty(chunk, center_x - r, center_y - r,
					center_x + r + 1, center_y + r + 1);
		}
	}

	if (_terrain_physical) {
		_terrain_physical->invalidate_rect(
				Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1));
	}
}

// --- place_lava ----------------------------------------------------------

void TerrainModifier::place_lava(Vector2 world_pos, float radius) {
	int center_x = static_cast<int>(std::floor(world_pos.x));
	int center_y = static_cast<int>(std::floor(world_pos.y));
	int r = static_cast<int>(std::ceil(radius));

	Dictionary affected;
	for (int dx = -r; dx <= r; dx++) {
		for (int dy = -r; dy <= r; dy++) {
			if (dx * dx + dy * dy > r * r) {
				continue;
			}
			int wx = center_x + dx;
			int wy = center_y + dy;
			Vector2i chunk_coord(
					static_cast<int>(std::floor(static_cast<float>(wx) / CHUNK_SIZE)),
					static_cast<int>(std::floor(static_cast<float>(wy) / CHUNK_SIZE)));
			if (!_chunks.has(chunk_coord)) {
				continue;
			}
			Vector2i local(((wx % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
					((wy % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE);
			if (!affected.has(chunk_coord)) {
				affected[chunk_coord] = Array();
			}
			((Array)affected[chunk_coord]).push_back(local);
		}
	}

	int lava_id = MaterialTable::get_singleton()->get_MAT_LAVA();
	int air_id = MaterialTable::get_singleton()->get_MAT_AIR();

	Array keys = affected.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i chunk_coord = keys[i];
		Ref<Chunk> chunk_ref = _chunks[chunk_coord];
		if (!chunk_ref.is_valid()) {
			continue;
		}
		Chunk *chunk = chunk_ref.ptr();

		Array locals = affected[chunk_coord];
		bool modified = false;
		for (int j = 0; j < locals.size(); j++) {
			Vector2i local = locals[j];
			Cell &cell = chunk->cells[local.y * CHUNK_SIZE + local.x];
			if (cell.material != air_id) {
				continue;
			}
			cell.material = static_cast<uint8_t>(lava_id);
			cell.health = 200;
			cell.temperature = 255;
			cell.flags = 136;
			modified = true;
		}
		if (modified) {
			mark_dirty(chunk, center_x - r, center_y - r,
					center_x + r + 1, center_y + r + 1);
		}
	}

	if (_terrain_physical) {
		_terrain_physical->invalidate_rect(
				Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1));
	}
}

// --- place_material ------------------------------------------------------

void TerrainModifier::place_material(Vector2 world_pos, float radius, int material_id) {
	int center_x = static_cast<int>(std::floor(world_pos.x));
	int center_y = static_cast<int>(std::floor(world_pos.y));
	int r = static_cast<int>(std::ceil(radius));

	Dictionary affected;
	for (int dx = -r; dx <= r; dx++) {
		for (int dy = -r; dy <= r; dy++) {
			if (dx * dx + dy * dy > r * r) {
				continue;
			}
			int wx = center_x + dx;
			int wy = center_y + dy;
			Vector2i chunk_coord(
					static_cast<int>(std::floor(static_cast<float>(wx) / CHUNK_SIZE)),
					static_cast<int>(std::floor(static_cast<float>(wy) / CHUNK_SIZE)));
			if (!_chunks.has(chunk_coord)) {
				continue;
			}
			Vector2i local(((wx % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
					((wy % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE);
			if (!affected.has(chunk_coord)) {
				affected[chunk_coord] = Array();
			}
			((Array)affected[chunk_coord]).push_back(local);
		}
	}

	int air_id = MaterialTable::get_singleton()->get_MAT_AIR();

	Array keys = affected.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i chunk_coord = keys[i];
		Ref<Chunk> chunk_ref = _chunks[chunk_coord];
		if (!chunk_ref.is_valid()) {
			continue;
		}
		Chunk *chunk = chunk_ref.ptr();

		Array locals = affected[chunk_coord];
		bool modified = false;
		for (int j = 0; j < locals.size(); j++) {
			Vector2i local = locals[j];
			Cell &cell = chunk->cells[local.y * CHUNK_SIZE + local.x];
			if (cell.material != air_id) {
				continue;
			}
			cell.material = static_cast<uint8_t>(material_id);
			cell.health = 255;
			cell.temperature = 0;
			cell.flags = 136;
			modified = true;
		}
		if (modified) {
			mark_dirty(chunk, center_x - r, center_y - r,
					center_x + r + 1, center_y + r + 1);
		}
	}

	if (_terrain_physical) {
		_terrain_physical->invalidate_rect(
				Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1));
	}
}

// --- place_fire ----------------------------------------------------------

void TerrainModifier::place_fire(Vector2 world_pos, float radius) {
	int center_x = static_cast<int>(std::floor(world_pos.x));
	int center_y = static_cast<int>(std::floor(world_pos.y));
	int r = static_cast<int>(std::ceil(radius));

	Dictionary affected;
	for (int dx = -r; dx <= r; dx++) {
		for (int dy = -r; dy <= r; dy++) {
			if (dx * dx + dy * dy > r * r) {
				continue;
			}
			int wx = center_x + dx;
			int wy = center_y + dy;
			Vector2i chunk_coord(
					static_cast<int>(std::floor(static_cast<float>(wx) / CHUNK_SIZE)),
					static_cast<int>(std::floor(static_cast<float>(wy) / CHUNK_SIZE)));
			if (!_chunks.has(chunk_coord)) {
				continue;
			}
			Vector2i local(((wx % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
					((wy % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE);
			if (!affected.has(chunk_coord)) {
				affected[chunk_coord] = Array();
			}
			((Array)affected[chunk_coord]).push_back(local);
		}
	}

	MaterialTable *mt = MaterialTable::get_singleton();

	Array keys = affected.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i chunk_coord = keys[i];
		Ref<Chunk> chunk_ref = _chunks[chunk_coord];
		if (!chunk_ref.is_valid()) {
			continue;
		}
		Chunk *chunk = chunk_ref.ptr();

		Array locals = affected[chunk_coord];
		bool modified = false;
		for (int j = 0; j < locals.size(); j++) {
			Vector2i local = locals[j];
			Cell &cell = chunk->cells[local.y * CHUNK_SIZE + local.x];
			if (!mt->is_flammable(cell.material)) {
				continue;
			}
			cell.temperature = 255;
			modified = true;
		}
		if (modified) {
			mark_dirty(chunk, center_x - r, center_y - r,
					center_x + r + 1, center_y + r + 1);
		}
	}

	if (_terrain_physical) {
		_terrain_physical->invalidate_rect(
				Rect2i(center_x - r, center_y - r, r * 2 + 1, r * 2 + 1));
	}
}

// --- disperse_materials_in_arc -------------------------------------------

void TerrainModifier::disperse_materials_in_arc(Vector2 origin, Vector2 direction, float radius,
		float arc_angle, float push_speed, const Array &materials) {
	Vector2i origin_int(static_cast<int>(origin.x), static_cast<int>(origin.y));
	int r_int = static_cast<int>(std::ceil(radius));
	float half_arc = arc_angle / 2.0f;
	float dir_angle = std::atan2(direction.y, direction.x);
	float start_angle = dir_angle - half_arc;
	float end_angle = dir_angle + half_arc;

	Dictionary affected;

	for (int dx = -r_int; dx <= r_int; dx++) {
		for (int dy = -r_int; dy <= r_int; dy++) {
			int dist_sq = dx * dx + dy * dy;
			if (dist_sq > r_int * r_int) {
				continue;
			}

			float pixel_angle = std::atan2(static_cast<float>(dy), static_cast<float>(dx));
			float delta_start = pixel_angle - start_angle;
			float delta_end = pixel_angle - end_angle;

			auto wrap = [](float a) {
				const float TAU = 2.0f * Math_PI;
				while (a > Math_PI) {
					a -= TAU;
				}
				while (a < -Math_PI) {
					a += TAU;
				}
				return a;
			};
			delta_start = wrap(delta_start);
			delta_end = wrap(delta_end);

			if (delta_start < 0.0f || delta_end > 0.0f) {
				continue;
			}

			int wx = origin_int.x + dx;
			int wy = origin_int.y + dy;
			Vector2i chunk_coord(
					static_cast<int>(std::floor(static_cast<float>(wx) / CHUNK_SIZE)),
					static_cast<int>(std::floor(static_cast<float>(wy) / CHUNK_SIZE)));
			if (!_chunks.has(chunk_coord)) {
				continue;
			}
			Vector2i local(((wx % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
					((wy % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE);
			if (!affected.has(chunk_coord)) {
				affected[chunk_coord] = Array();
			}
			Vector2 norm_dir = Vector2(static_cast<float>(dx), static_cast<float>(dy)).normalized();
			Array entry;
			entry.push_back(local);
			entry.push_back(norm_dir);
			((Array)affected[chunk_coord]).push_back(entry);
		}
	}

	if (affected.is_empty()) {
		return;
	}

	Array keys = affected.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i chunk_coord = keys[i];
		Ref<Chunk> chunk_ref = _chunks[chunk_coord];
		if (!chunk_ref.is_valid()) {
			continue;
		}
		Chunk *chunk = chunk_ref.ptr();

		Array entries = affected[chunk_coord];
		bool modified = false;
		for (int j = 0; j < entries.size(); j++) {
			Array entry = entries[j];
			Vector2i pixel_pos = entry[0];
			Vector2 push_dir = entry[1];

			Cell &cell = chunk->cells[pixel_pos.y * CHUNK_SIZE + pixel_pos.x];

			bool is_target = false;
			for (int k = 0; k < materials.size(); k++) {
				if (static_cast<int>(cell.material) == static_cast<int>(materials[k])) {
					is_target = true;
					break;
				}
			}
			if (!is_target) {
				continue;
			}

			int push_vx = static_cast<int>(std::round(push_dir.x * push_speed / 60.0f));
			int push_vy = static_cast<int>(std::round(push_dir.y * push_speed / 60.0f));
			int vx_enc = std::min(std::max(push_vx + 8, 0), 15);
			int vy_enc = std::min(std::max(push_vy + 8, 0), 15);
			cell.flags = static_cast<uint8_t>((vx_enc << 4) | vy_enc);
			modified = true;
		}
		if (modified) {
			mark_dirty(chunk, origin_int.x - r_int, origin_int.y - r_int,
					origin_int.x + r_int + 1, origin_int.y + r_int + 1);
		}
	}

	if (_terrain_physical) {
		_terrain_physical->invalidate_rect(
				Rect2i(origin_int.x - r_int, origin_int.y - r_int,
						r_int * 2 + 1, r_int * 2 + 1));
	}
}

// --- clear_and_push_materials_in_arc -------------------------------------

void TerrainModifier::clear_and_push_materials_in_arc(Vector2 origin, Vector2 direction,
		float radius, float arc_angle, float push_speed, float edge_fraction,
		const Array &materials) {
	Vector2i origin_int(static_cast<int>(origin.x), static_cast<int>(origin.y));
	int r_int = static_cast<int>(std::ceil(radius));
	float half_arc = arc_angle / 2.0f;
	float dir_angle = std::atan2(direction.y, direction.x);
	float start_angle = dir_angle - half_arc;
	float end_angle = dir_angle + half_arc;
	float inner_r = radius * (1.0f - edge_fraction);
	int inner_r_sq = static_cast<int>(inner_r) * static_cast<int>(inner_r);
	int r_sq = r_int * r_int;

	Dictionary affected;

	for (int dx = -r_int; dx <= r_int; dx++) {
		for (int dy = -r_int; dy <= r_int; dy++) {
			int dist_sq = dx * dx + dy * dy;
			if (dist_sq > r_sq) {
				continue;
			}

			float pixel_angle = std::atan2(static_cast<float>(dy), static_cast<float>(dx));
			float delta_start = pixel_angle - start_angle;
			float delta_end = pixel_angle - end_angle;

			auto wrap = [](float a) {
				const float TAU = 2.0f * Math_PI;
				while (a > Math_PI) {
					a -= TAU;
				}
				while (a < -Math_PI) {
					a += TAU;
				}
				return a;
			};
			delta_start = wrap(delta_start);
			delta_end = wrap(delta_end);

			if (delta_start < 0.0f || delta_end > 0.0f) {
				continue;
			}

			int wx = origin_int.x + dx;
			int wy = origin_int.y + dy;
			Vector2i chunk_coord(
					static_cast<int>(std::floor(static_cast<float>(wx) / CHUNK_SIZE)),
					static_cast<int>(std::floor(static_cast<float>(wy) / CHUNK_SIZE)));
			if (!_chunks.has(chunk_coord)) {
				continue;
			}
			Vector2i local(((wx % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE,
					((wy % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE);
			if (!affected.has(chunk_coord)) {
				affected[chunk_coord] = Array();
			}
			Array entry;
			entry.push_back(local);
			if (dist_sq >= inner_r_sq) {
				Vector2 norm_dir = Vector2(static_cast<float>(dx), static_cast<float>(dy)).normalized();
				entry.push_back(norm_dir);
				entry.push_back(false);
			} else {
				entry.push_back(Vector2());
				entry.push_back(true);
			}
			((Array)affected[chunk_coord]).push_back(entry);
		}
	}

	if (affected.is_empty()) {
		return;
	}

	int air_id = MaterialTable::get_singleton()->get_MAT_AIR();

	Array keys = affected.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i chunk_coord = keys[i];
		Ref<Chunk> chunk_ref = _chunks[chunk_coord];
		if (!chunk_ref.is_valid()) {
			continue;
		}
		Chunk *chunk = chunk_ref.ptr();

		Array entries = affected[chunk_coord];
		bool modified = false;
		for (int j = 0; j < entries.size(); j++) {
			Array entry = entries[j];
			Vector2i pixel_pos = entry[0];
			Vector2 push_dir = entry[1];
			bool do_clear = entry[2];

			Cell &cell = chunk->cells[pixel_pos.y * CHUNK_SIZE + pixel_pos.x];

			bool is_target = false;
			for (int k = 0; k < materials.size(); k++) {
				if (static_cast<int>(cell.material) == static_cast<int>(materials[k])) {
					is_target = true;
					break;
				}
			}
			if (!is_target) {
				continue;
			}

			if (do_clear) {
				cell.material = static_cast<uint8_t>(air_id);
				cell.health = 0;
				cell.temperature = 0;
				cell.flags = 136;
			} else {
				int push_vx = static_cast<int>(std::round(push_dir.x * push_speed / 60.0f));
				int push_vy = static_cast<int>(std::round(push_dir.y * push_speed / 60.0f));
				int vx_enc = std::min(std::max(push_vx + 8, 0), 15);
				int vy_enc = std::min(std::max(push_vy + 8, 0), 15);
				cell.flags = static_cast<uint8_t>((vx_enc << 4) | vy_enc);
			}
			modified = true;
		}
		if (modified) {
			mark_dirty(chunk, origin_int.x - r_int, origin_int.y - r_int,
					origin_int.x + r_int + 1, origin_int.y + r_int + 1);
		}
	}

	if (_terrain_physical) {
		_terrain_physical->invalidate_rect(
				Rect2i(origin_int.x - r_int, origin_int.y - r_int,
						r_int * 2 + 1, r_int * 2 + 1));
	}
}

} // namespace toprogue
