#pragma once

#include "chunk_manager.h"
#include "terrain_modifier.h"
#include "terrain_physical.h"
#include "terrain_collision_helper.h"
#include "../sim/simulator.h"
#include "../generation/generator.h"
#include "../generation/simplex_cave_generator.h"
#include "../physics/collider_builder.h"

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

class WorldManager : public godot::Node2D {
	GDCLASS(WorldManager, godot::Node2D);

public:
	WorldManager() = default;

	void _ready() override;
	void _process(double delta) override;
	void _exit_tree() override;

	void place_gas(godot::Vector2 world_pos, float radius, int density,
			godot::Vector2i velocity = godot::Vector2i(0, 0));
	void place_lava(godot::Vector2 world_pos, float radius);
	void place_material(godot::Vector2 world_pos, float radius, int material_id);
	void place_fire(godot::Vector2 world_pos, float radius);
	void disperse_materials_in_arc(godot::Vector2 origin, godot::Vector2 direction,
			float radius, float arc_angle, float push_speed, const godot::Array &materials);
	void clear_and_push_materials_in_arc(godot::Vector2 origin, godot::Vector2 direction,
			float radius, float arc_angle, float push_speed, float edge_fraction,
			const godot::Array &materials);

	void reset();
	godot::PackedByteArray read_region(godot::Rect2i region) const;
	godot::Vector2i find_spawn_position(godot::Vector2i search_origin, godot::Vector2i body_size,
			float max_radius = 800.0f);
	godot::TypedArray<godot::Vector2i> get_active_chunk_coords() const;
	void generate_chunks_at(const godot::TypedArray<godot::Vector2i> &coords, int64_t seed_val);
	void clear_all_chunks();
	godot::Node2D *get_chunk_container() { return _chunk_container; }

	void set_tracking_position(godot::Vector2 pos) { _tracking_position = pos; }
	godot::Vector2 get_tracking_position() const { return _tracking_position; }

protected:
	static void _bind_methods();

private:
	godot::Ref<ChunkManager> _chunk_manager;
	godot::Ref<Simulator> _simulator;
	godot::Ref<Generator> _generator;
	godot::Ref<SimplexCaveGenerator> _simplex_cave_generator;
	godot::Ref<ColliderBuilder> _collider_builder;
	godot::Ref<TerrainModifier> _terrain_modifier;
	TerrainPhysical *_terrain_physical = nullptr;
	TerrainCollisionHelper *_collision_helper = nullptr;

	godot::Vector2 _tracking_position;
	godot::Node2D *_chunk_container = nullptr;
	godot::Node2D *_collision_container = nullptr;

	void _update_chunks();
	godot::Ref<godot::RefCounted> _generator_for(BiomeDef *biome);
	static bool _pocket_fits(const godot::PackedByteArray &data, int region_w, int region_h,
			godot::Vector2i top_left, godot::Vector2i size);
};

} // namespace toprogue
