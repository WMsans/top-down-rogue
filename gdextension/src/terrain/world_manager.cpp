#include "world_manager.h"

#include "chunk_manager.h"
#include "terrain_modifier.h"
#include "terrain_physical.h"
#include "terrain_collision_helper.h"
#include "../sim/simulator.h"
#include "../sim/material_table.h"
#include "../generation/generator.h"
#include "../generation/simplex_cave_generator.h"
#include "../physics/collider_builder.h"
#include "../physics/gas_injector.h"
#include "../physics/terrain_collider.h"
#include "../resources/biome_def.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

// --- Signal & method bindings -----------------------------------------------

void WorldManager::_bind_methods() {
	// Signals
	ADD_SIGNAL(MethodInfo("chunks_generated",
			PropertyInfo(Variant::ARRAY, "new_coords")));

	// Public terrain-modification API
	ClassDB::bind_method(D_METHOD("place_gas", "world_pos", "radius", "density", "velocity"),
			&WorldManager::place_gas, DEFVAL(Vector2i(0, 0)));
	ClassDB::bind_method(D_METHOD("place_lava", "world_pos", "radius"),
			&WorldManager::place_lava);
	ClassDB::bind_method(D_METHOD("place_material", "world_pos", "radius", "material_id"),
			&WorldManager::place_material);
	ClassDB::bind_method(D_METHOD("place_fire", "world_pos", "radius"),
			&WorldManager::place_fire);
	ClassDB::bind_method(D_METHOD("disperse_materials_in_arc", "origin", "direction",
			"radius", "arc_angle", "push_speed", "materials"),
			&WorldManager::disperse_materials_in_arc);
	ClassDB::bind_method(D_METHOD("clear_and_push_materials_in_arc", "origin", "direction",
			"radius", "arc_angle", "push_speed", "edge_fraction", "materials"),
			&WorldManager::clear_and_push_materials_in_arc);

	ClassDB::bind_method(D_METHOD("reset"), &WorldManager::reset);
	ClassDB::bind_method(D_METHOD("read_region", "region"), &WorldManager::read_region);
	ClassDB::bind_method(D_METHOD("find_spawn_position", "search_origin", "body_size",
			"max_radius"), &WorldManager::find_spawn_position, DEFVAL(800.0f));
	ClassDB::bind_method(D_METHOD("get_active_chunk_coords"),
			&WorldManager::get_active_chunk_coords);
	ClassDB::bind_method(D_METHOD("generate_chunks_at", "coords", "seed_val"),
			&WorldManager::generate_chunks_at);
	ClassDB::bind_method(D_METHOD("clear_all_chunks"), &WorldManager::clear_all_chunks);
	ClassDB::bind_method(D_METHOD("get_chunk_container"), &WorldManager::get_chunk_container);

	ClassDB::bind_method(D_METHOD("set_tracking_position", "pos"),
			&WorldManager::set_tracking_position);
	ClassDB::bind_method(D_METHOD("get_tracking_position"),
			&WorldManager::get_tracking_position);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "tracking_position"),
			"set_tracking_position", "get_tracking_position");
}

// --- _ready -----------------------------------------------------------------

void WorldManager::_ready() {
	add_to_group("world_manager");

	// Chunk container (expected child node)
	_chunk_container = get_node<Node2D>(NodePath("ChunkContainer"));

	// Collision container
	_collision_container = memnew(Node2D);
	_collision_container->set_name("CollisionContainer");
	add_child(_collision_container);

	// ChunkManager
	_chunk_manager.instantiate();
	_chunk_manager->set_node(this);
	_chunk_manager->set_chunk_container(_chunk_container);
	_chunk_manager->set_collision_container(_collision_container);

	// Simulator
	_simulator.instantiate();
	_simulator->set_chunks(_chunk_manager->get_chunks());

	// Generators
	_generator.instantiate();
	_simplex_cave_generator.instantiate();

	_chunk_manager->set_generator(_generator);
	_chunk_manager->set_simplex_cave_generator(_simplex_cave_generator);

	// TerrainModifier
	_terrain_modifier.instantiate();
	_terrain_modifier->set_chunks(_chunk_manager->get_chunks());

	// TerrainPhysical
	_terrain_physical = memnew(TerrainPhysical);
	_terrain_physical->set_name("TerrainPhysical");
	add_child(_terrain_physical);
	_terrain_physical->world_manager = this;
	_terrain_modifier->set_terrain_physical(_terrain_physical);

	// ColliderBuilder
	_collider_builder.instantiate();

	// CollisionHelper
	_collision_helper = memnew(TerrainCollisionHelper);
	_collision_helper->world_manager = this;

	// Register with TerrainSurface autoload
	Object *tso = Engine::get_singleton()->get_singleton("TerrainSurface");
	if (tso) {
		tso->call("register_adapter", this);
	}
}

// --- _exit_tree -------------------------------------------------------------

void WorldManager::_exit_tree() {
	if (_chunk_manager.is_valid()) {
		_chunk_manager->clear_all_chunks();
	}

	Object *tso = Engine::get_singleton()->get_singleton("TerrainSurface");
	if (tso) {
		tso->call("unregister_adapter", this);
	}
}

// --- _process ---------------------------------------------------------------

void WorldManager::_process(double delta) {
	if (Engine::get_singleton()->is_editor_hint()) {
		return;
	}

	_update_chunks();

	// Gas injection — build payloads for all active chunks
	// TODO: Parse payload bytes and push InjectionAABB via chunk->push_injection()
	Dictionary chunks_dict = _chunk_manager->get_chunks();
	Array chunk_keys = chunks_dict.keys();
	for (int i = 0; i < chunk_keys.size(); i++) {
		Vector2i coord = chunk_keys[i];
		GasInjector::build_payload(get_tree(), coord);
	}

	_simulator->tick();

	// Collision rebuild using CollisionHelper's timing control
	_collision_helper->rebuild_dirty(_chunk_manager->get_chunks(), delta);

	_terrain_physical->set_center(Vector2i(
			static_cast<int>(_tracking_position.x),
			static_cast<int>(_tracking_position.y)));
}

// --- _update_chunks ---------------------------------------------------------

void WorldManager::_update_chunks() {
	TypedArray<Vector2i> desired = _chunk_manager->get_desired_chunks(_tracking_position);

	Dictionary chunks = _chunk_manager->get_chunks();

	// Determine which chunks to create and which to remove
	TypedArray<Vector2i> to_create;
	Dictionary desired_set;
	for (int i = 0; i < desired.size(); i++) {
		Vector2i d = desired[i];
		desired_set[d] = true;
		if (!chunks.has(d)) {
			to_create.append(d);
		}
	}

	TypedArray<Vector2i> to_remove;
	Array existing = chunks.keys();
	for (int i = 0; i < existing.size(); i++) {
		Vector2i coord = existing[i];
		if (!desired_set.has(coord)) {
			to_remove.append(coord);
		}
	}

	// Remove out-of-view chunks
	for (int i = 0; i < to_remove.size(); i++) {
		_chunk_manager->unload_chunk(to_remove[i]);
	}

	// Create new chunks
	if (to_create.size() > 0) {
		Object *lm = Engine::get_singleton()->get_singleton("LevelManager");
		int64_t world_seed = 0;
		Ref<BiomeDef> biome;
		if (lm) {
			world_seed = lm->get("world_seed");
			biome = lm->get("current_biome");
		}
		_simulator->set_world_seed(world_seed);

		// Generate new chunks
		TypedArray<Vector2i> new_chunks = _chunk_manager->generate_chunks_at(
				to_create, world_seed);

		// Emit signal
		emit_signal("chunks_generated", new_chunks);

		// After generation, update texture on new chunks
		for (int i = 0; i < new_chunks.size(); i++) {
			Vector2i coord = new_chunks[i];
			if (chunks.has(coord)) {
				Ref<Chunk> ch = chunks[coord];
				ch->upload_texture_full();
			}
		}

		_chunk_manager->update_render_neighbors(new_chunks, to_remove);
	}
}

// --- _generator_for ---------------------------------------------------------

Ref<RefCounted> WorldManager::_generator_for(BiomeDef *biome) {
	if (biome && biome->get_use_simplex_cave_generator()) {
		return _simplex_cave_generator;
	}
	return _generator;
}

// --- Public delegation methods ----------------------------------------------

void WorldManager::place_gas(Vector2 world_pos, float radius, int density, Vector2i velocity) {
	_terrain_modifier->place_gas(world_pos, radius, density, velocity);
}

void WorldManager::place_lava(Vector2 world_pos, float radius) {
	_terrain_modifier->place_lava(world_pos, radius);
}

void WorldManager::place_material(Vector2 world_pos, float radius, int material_id) {
	_terrain_modifier->place_material(world_pos, radius, material_id);
}

void WorldManager::place_fire(Vector2 world_pos, float radius) {
	_terrain_modifier->place_fire(world_pos, radius);
}

void WorldManager::disperse_materials_in_arc(Vector2 origin, Vector2 direction,
		float radius, float arc_angle, float push_speed, const Array &materials) {
	_terrain_modifier->disperse_materials_in_arc(origin, direction, radius, arc_angle,
			push_speed, materials);
}

void WorldManager::clear_and_push_materials_in_arc(Vector2 origin, Vector2 direction,
		float radius, float arc_angle, float push_speed, float edge_fraction,
		const Array &materials) {
	_terrain_modifier->clear_and_push_materials_in_arc(origin, direction, radius, arc_angle,
			push_speed, edge_fraction, materials);
}

void WorldManager::reset() {
	_chunk_manager->clear_all_chunks();
}

PackedByteArray WorldManager::read_region(Rect2i region) const {
	return _chunk_manager->read_region(region);
}

Vector2i WorldManager::find_spawn_position(Vector2i search_origin, Vector2i body_size,
		float max_radius) {
	static constexpr int CHUNK_SIZE = 256;
	Vector2i chunk_origin(
			static_cast<int>(Math::floor(static_cast<double>(search_origin.x) / CHUNK_SIZE)),
			static_cast<int>(Math::floor(static_cast<double>(search_origin.y) / CHUNK_SIZE)));

	int radius_chunks = static_cast<int>(Math::ceil(max_radius / CHUNK_SIZE)) + 1;

	for (int dy = -radius_chunks; dy <= radius_chunks; dy++) {
		for (int dx = -radius_chunks; dx <= radius_chunks; dx++) {
			Vector2i coord = chunk_origin + Vector2i(dx, dy);
			if (!_chunk_manager->get_chunks().has(coord)) continue;

			Ref<Chunk> chunk = _chunk_manager->get_chunks()[coord];

			// Scan for air pockets within the chunk that fit body_size
			for (int cy = 0; cy <= CHUNK_SIZE - body_size.y; cy += 4) {
				for (int cx = 0; cx <= CHUNK_SIZE - body_size.x; cx += 4) {
					Vector2i world_top_left = coord * CHUNK_SIZE + Vector2i(cx, cy);
					Vector2i world_center = world_top_left + body_size / 2;
					double dist = Math::sqrt(
							static_cast<double>(
									(search_origin.x - world_center.x) *
									(search_origin.x - world_center.x)) +
							static_cast<double>(
									(search_origin.y - world_center.y) *
									(search_origin.y - world_center.y)));

					if (dist > max_radius) continue;

					bool fits = true;
					for (int py = 0; py < body_size.y && fits; py++) {
						for (int px = 0; px < body_size.x && fits; px++) {
							int idx = (cy + py) * CHUNK_SIZE + (cx + px);
							if (chunk->cells[idx].material != 0) {
								fits = false;
							}
						}
					}
					if (fits) {
						return world_top_left + body_size / 2;
					}
				}
			}
		}
	}

	return search_origin;
}

TypedArray<Vector2i> WorldManager::get_active_chunk_coords() const {
	TypedArray<Vector2i> result;
	Dictionary chunks = _chunk_manager->get_chunks();
	Array keys = chunks.keys();
	for (int i = 0; i < keys.size(); i++) {
		result.append(keys[i]);
	}
	return result;
}

void WorldManager::generate_chunks_at(const TypedArray<Vector2i> &coords, int64_t seed_val) {
	TypedArray<Vector2i> new_chunks = _chunk_manager->generate_chunks_at(coords, seed_val);
	if (new_chunks.size() > 0) {
		emit_signal("chunks_generated", new_chunks);
	}
}

void WorldManager::clear_all_chunks() {
	_chunk_manager->clear_all_chunks();
}

// --- _pocket_fits (static helper) -------------------------------------------

bool WorldManager::_pocket_fits(const PackedByteArray &data, int region_w, int region_h,
		Vector2i top_left, Vector2i size) {
	int air_id = MaterialTable::get_singleton()->get_MAT_AIR();
	for (int y = 0; y < size.y; y++) {
		for (int x = 0; x < size.x; x++) {
			int px = top_left.x + x;
			int py = top_left.y + y;
			if (px < 0 || px >= region_w || py < 0 || py >= region_h) return false;
			if (data[py * region_w + px] != air_id) return false;
		}
	}
	return true;
}

} // namespace toprogue
