#pragma once

#include "chunk.h"

#include "../generation/generator.h"
#include "../generation/simplex_cave_generator.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

class ChunkManager : public godot::RefCounted {
	GDCLASS(ChunkManager, godot::RefCounted);

public:
	static constexpr int CHUNK_SIZE = 256;
	static constexpr int WORKGROUP_SIZE = 8;
	static constexpr int NUM_WORKGROUPS = CHUNK_SIZE / WORKGROUP_SIZE;

	ChunkManager() = default;

	void set_node(godot::Node *n) { _node = n; }
	void set_chunk_container(godot::Node2D *c) { _chunk_container = c; }
	void set_collision_container(godot::Node2D *c) { _collision_container = c; }
	void set_generator(const godot::Ref<Generator> &g) { _generator = g; }
	void set_simplex_cave_generator(const godot::Ref<SimplexCaveGenerator> &g) { _simplex_cave_generator = g; }

	godot::TypedArray<godot::Vector2i> get_desired_chunks(godot::Vector2 tracking_position) const;
	godot::Ref<Chunk> create_chunk(godot::Vector2i coord);
	void unload_chunk(godot::Vector2i coord);
	void update_render_neighbors(const godot::TypedArray<godot::Vector2i> &loaded,
			const godot::TypedArray<godot::Vector2i> &unloaded);
	void clear_all_chunks();
	godot::TypedArray<godot::Vector2i> generate_chunks_at(
			const godot::TypedArray<godot::Vector2i> &coords, int64_t seed_val);
	godot::Dictionary get_chunks() const { return _chunks; }
	godot::PackedByteArray read_region(godot::Rect2i region) const;

protected:
	static void _bind_methods();

private:
	godot::Dictionary _chunks;
	godot::Node *_node = nullptr;
	godot::Node2D *_chunk_container = nullptr;
	godot::Node2D *_collision_container = nullptr;
	godot::Ref<godot::Shader> _render_shader;
	godot::Ref<godot::Texture2DArray> _material_textures;
	godot::Ref<Generator> _generator;
	godot::Ref<SimplexCaveGenerator> _simplex_cave_generator;

	void free_chunk_resources(Chunk *chunk);
	void wire_neighbors(Chunk *chunk);
	void _init_material_textures();
};

} // namespace toprogue
