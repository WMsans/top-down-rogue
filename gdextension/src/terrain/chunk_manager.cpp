#include "chunk_manager.h"

#include "../generation/generator.h"
#include "../generation/simplex_cave_generator.h"
#include "../resources/biome_def.h"
#include "../sim/material_table.h"
#include "chunk.h"
#include "sector_grid.h"

#include <godot_cpp/classes/camera2d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh_instance2d.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/static_body2d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

// --- Bind methods ------------------------------------------------------------

void ChunkManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_node", "node"), &ChunkManager::set_node);
	ClassDB::bind_method(D_METHOD("set_chunk_container", "container"), &ChunkManager::set_chunk_container);
	ClassDB::bind_method(D_METHOD("set_collision_container", "container"), &ChunkManager::set_collision_container);
	ClassDB::bind_method(D_METHOD("set_generator", "generator"), &ChunkManager::set_generator);
	ClassDB::bind_method(D_METHOD("set_simplex_cave_generator", "generator"),
			&ChunkManager::set_simplex_cave_generator);

	ClassDB::bind_method(D_METHOD("get_desired_chunks", "tracking_position"),
			&ChunkManager::get_desired_chunks);
	ClassDB::bind_method(D_METHOD("create_chunk", "coord"), &ChunkManager::create_chunk);
	ClassDB::bind_method(D_METHOD("unload_chunk", "coord"), &ChunkManager::unload_chunk);
	ClassDB::bind_method(D_METHOD("update_render_neighbors", "loaded", "unloaded"),
			&ChunkManager::update_render_neighbors);
	ClassDB::bind_method(D_METHOD("clear_all_chunks"), &ChunkManager::clear_all_chunks);
	ClassDB::bind_method(D_METHOD("generate_chunks_at", "coords", "seed_val"),
			&ChunkManager::generate_chunks_at);
	ClassDB::bind_method(D_METHOD("get_chunks"), &ChunkManager::get_chunks);
	ClassDB::bind_method(D_METHOD("read_region", "region"), &ChunkManager::read_region);

	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "chunks"), "", "get_chunks");
}

// --- _init_material_textures ------------------------------------------------

void ChunkManager::_init_material_textures() {
	MaterialTable *mt = MaterialTable::get_singleton();
	TypedArray<MaterialDef> mats = mt->get_materials();

	// First pass: load real textures and discover their dimensions. The
	// Texture2DArray requires every layer to be the same size, so any
	// material without an authored texture must fall back to that size.
	TypedArray<Ref<Image>> images;
	int tex_w = 0;
	int tex_h = 0;
	for (int i = 0; i < mats.size(); i++) {
		Ref<MaterialDef> def = mats[i];
		Ref<Image> img;
		String path = def->get_texture_path();
		if (!path.is_empty()) {
			Ref<Texture2D> tex = ResourceLoader::get_singleton()->load(path);
			if (tex.is_valid()) {
				img = tex->get_image();
			}
		}
		if (img.is_valid() && tex_w == 0) {
			tex_w = img->get_width();
			tex_h = img->get_height();
		}
		images.append(img);
	}

	if (tex_w == 0 || tex_h == 0) {
		tex_w = 16;
		tex_h = 16;
	}

	// Second pass: replace missing entries with a uniformly-sized fallback,
	// and force every layer to RGBA8 so create_from_images sees identical
	// dimensions and format across the whole array.
	for (int i = 0; i < images.size(); i++) {
		Ref<Image> img = images[i];
		if (!img.is_valid()) {
			Ref<Image> fallback = Image::create(tex_w, tex_h, false, Image::FORMAT_RGBA8);
			fallback->fill(Color(1, 1, 1, 1));
			images[i] = fallback;
			continue;
		}
		if (img->get_format() != Image::FORMAT_RGBA8) {
			img->convert(Image::FORMAT_RGBA8);
		}
		if (img->get_width() != tex_w || img->get_height() != tex_h) {
			img->resize(tex_w, tex_h);
		}
		images[i] = img;
	}

	_material_textures.instantiate();
	_material_textures->create_from_images(images);
}

// --- get_desired_chunks -----------------------------------------------------

TypedArray<Vector2i> ChunkManager::get_desired_chunks(Vector2 tracking_position) const {
	TypedArray<Vector2i> result;
	if (!_node) {
		return result;
	}

	Viewport *vp = _node->get_viewport();
	if (!vp) {
		return result;
	}

	Vector2 vp_size = vp->get_visible_rect().size;
	Camera2D *cam = vp->get_camera_2d();
	Vector2 cam_zoom = cam ? cam->get_zoom() : Vector2(8, 8);

	Vector2 half_view = vp_size / (2.0 * cam_zoom);

	Vector2i min_chunk(
			static_cast<int>(Math::floor((tracking_position.x - half_view.x) / CHUNK_SIZE)) - 1,
			static_cast<int>(Math::floor((tracking_position.y - half_view.y) / CHUNK_SIZE)) - 1);
	Vector2i max_chunk(
			static_cast<int>(Math::floor((tracking_position.x + half_view.x) / CHUNK_SIZE)) + 1,
			static_cast<int>(Math::floor((tracking_position.y + half_view.y) / CHUNK_SIZE)) + 1);

	for (int x = min_chunk.x; x <= max_chunk.x; x++) {
		for (int y = min_chunk.y; y <= max_chunk.y; y++) {
			result.append(Vector2i(x, y));
		}
	}
	return result;
}

// --- create_chunk -----------------------------------------------------------

Ref<Chunk> ChunkManager::create_chunk(Vector2i coord) {
	if (_render_shader.is_null()) {
		_render_shader = ResourceLoader::get_singleton()->load("res://shaders/visual/render_chunk.gdshader");
	}
	if (_material_textures.is_null()) {
		_init_material_textures();
	}

	Ref<Chunk> chunk;
	chunk.instantiate();
	chunk->coord = coord;

	// Pre-create the chunk's data texture so the shader sees a valid
	// sampler when its parameter is bound below; later upload_texture_full
	// calls go through ImageTexture::update on this same instance.
	{
		PackedByteArray zeros;
		zeros.resize(CHUNK_SIZE * CHUNK_SIZE * 4);
		Ref<Image> blank = Image::create_from_data(
				CHUNK_SIZE, CHUNK_SIZE, false, Image::FORMAT_RGBA8, zeros);
		chunk->texture = ImageTexture::create_from_image(blank);
	}

	// --- Mesh instance --------------------------------------------------
	chunk->mesh_instance = memnew(MeshInstance2D);
	Ref<QuadMesh> quad;
	quad.instantiate();
	quad->set_size(Vector2(CHUNK_SIZE, CHUNK_SIZE));
	chunk->mesh_instance->set_mesh(quad);
	chunk->mesh_instance->set_position(
			Vector2(coord) * CHUNK_SIZE + Vector2(CHUNK_SIZE / 2.0, CHUNK_SIZE / 2.0));

	Ref<ShaderMaterial> mat;
	mat.instantiate();
	mat->set_shader(_render_shader);
	mat->set_shader_parameter("chunk_data", chunk->get_texture());
	mat->set_shader_parameter("material_textures", _material_textures);
	mat->set_shader_parameter("wall_height", 16);
	mat->set_shader_parameter("layer_mode", 1);
	chunk->mesh_instance->set_material(mat);

	if (_chunk_container) {
		_chunk_container->add_child(chunk->mesh_instance);
	}

	// --- Wall mesh instance ---------------------------------------------
	chunk->wall_mesh_instance = memnew(MeshInstance2D);
	Ref<QuadMesh> wall_quad;
	wall_quad.instantiate();
	wall_quad->set_size(Vector2(CHUNK_SIZE, CHUNK_SIZE));
	chunk->wall_mesh_instance->set_mesh(wall_quad);
	chunk->wall_mesh_instance->set_position(chunk->mesh_instance->get_position());
	chunk->wall_mesh_instance->set_z_index(1);

	Ref<ShaderMaterial> wall_mat;
	wall_mat.instantiate();
	wall_mat->set_shader(_render_shader);
	wall_mat->set_shader_parameter("chunk_data", chunk->get_texture());
	wall_mat->set_shader_parameter("material_textures", _material_textures);
	wall_mat->set_shader_parameter("wall_height", 16);
	wall_mat->set_shader_parameter("layer_mode", 0);
	chunk->wall_mesh_instance->set_material(wall_mat);

	if (_chunk_container) {
		_chunk_container->add_child(chunk->wall_mesh_instance);
	}

	// --- Static body ----------------------------------------------------
	chunk->static_body = memnew(StaticBody2D);
	chunk->static_body->set_collision_layer(1);
	chunk->static_body->set_collision_mask(0);
	if (_collision_container) {
		_collision_container->add_child(chunk->static_body);
	}

	// --- Occluder instances (empty initially) ---------------------------
	chunk->occluder_instances = TypedArray<LightOccluder2D>();

	_chunks[coord] = chunk;

	wire_neighbors(chunk.ptr());

	return chunk;
}

// --- unload_chunk -----------------------------------------------------------

void ChunkManager::unload_chunk(Vector2i coord) {
	if (!_chunks.has(coord)) {
		return;
	}
	Ref<Chunk> chunk = _chunks[coord];
	free_chunk_resources(chunk.ptr());
	_chunks.erase(coord);
}

// --- free_chunk_resources ---------------------------------------------------

void ChunkManager::free_chunk_resources(Chunk *chunk) {
	if (!chunk) {
		return;
	}

	if (chunk->mesh_instance && chunk->mesh_instance->is_inside_tree()) {
		chunk->mesh_instance->queue_free();
	}
	if (chunk->wall_mesh_instance && chunk->wall_mesh_instance->is_inside_tree()) {
		chunk->wall_mesh_instance->queue_free();
	}
	if (chunk->static_body && chunk->static_body->is_inside_tree()) {
		chunk->static_body->queue_free();
	}

	TypedArray<LightOccluder2D> occluders = chunk->occluder_instances;
	for (int i = 0; i < occluders.size(); i++) {
		LightOccluder2D *occ = Object::cast_to<LightOccluder2D>(occluders[i].operator Object *());
		if (occ && occ->is_inside_tree()) {
			occ->queue_free();
		}
	}
	chunk->occluder_instances.clear();
}

// --- wire_neighbors ---------------------------------------------------------

void ChunkManager::wire_neighbors(Chunk *chunk) {
	if (!chunk) {
		return;
	}
	Vector2i coord = chunk->coord;

	if (_chunks.has(coord + Vector2i(0, -1))) {
		chunk->set_neighbor_up(_chunks[coord + Vector2i(0, -1)]);
	} else {
		chunk->set_neighbor_up(Ref<Chunk>());
	}

	if (_chunks.has(coord + Vector2i(0, 1))) {
		chunk->set_neighbor_down(_chunks[coord + Vector2i(0, 1)]);
	} else {
		chunk->set_neighbor_down(Ref<Chunk>());
	}

	if (_chunks.has(coord + Vector2i(-1, 0))) {
		chunk->set_neighbor_left(_chunks[coord + Vector2i(-1, 0)]);
	} else {
		chunk->set_neighbor_left(Ref<Chunk>());
	}

	if (_chunks.has(coord + Vector2i(1, 0))) {
		chunk->set_neighbor_right(_chunks[coord + Vector2i(1, 0)]);
	} else {
		chunk->set_neighbor_right(Ref<Chunk>());
	}
}

// --- update_render_neighbors ------------------------------------------------

void ChunkManager::update_render_neighbors(const TypedArray<Vector2i> &loaded,
		const TypedArray<Vector2i> &unloaded) {
	Dictionary to_update;

	for (int i = 0; i < loaded.size(); i++) {
		Vector2i coord = loaded[i];
		to_update[coord] = true;
		Vector2i south = coord + Vector2i(0, 1);
		if (_chunks.has(south)) {
			to_update[south] = true;
		}
	}
	for (int i = 0; i < unloaded.size(); i++) {
		Vector2i coord = unloaded[i];
		Vector2i south = coord + Vector2i(0, 1);
		if (_chunks.has(south)) {
			to_update[south] = true;
		}
	}

	Array keys = to_update.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i coord = keys[i];
		if (!_chunks.has(coord)) {
			continue;
		}

		Ref<Chunk> chunk = _chunks[coord];
		Vector2i north_coord = coord + Vector2i(0, -1);

		// Update north neighbor ref
		if (_chunks.has(north_coord)) {
			chunk->set_neighbor_up(_chunks[north_coord]);
		} else {
			chunk->set_neighbor_up(Ref<Chunk>());
		}

		// Update shader parameters on the main mesh material
		ShaderMaterial *mat = Object::cast_to<ShaderMaterial>(
				chunk->mesh_instance->get_material().ptr());
		if (mat) {
			if (_chunks.has(north_coord)) {
				Ref<Chunk> north_chunk = _chunks[north_coord];
				mat->set_shader_parameter("neighbor_data", north_chunk->get_texture());
				mat->set_shader_parameter("has_neighbor", true);
			} else {
				mat->set_shader_parameter("has_neighbor", false);
			}
		}
	}
}

// --- clear_all_chunks -------------------------------------------------------

void ChunkManager::clear_all_chunks() {
	Array keys = _chunks.keys();
	for (int i = 0; i < keys.size(); i++) {
		Ref<Chunk> chunk = _chunks[keys[i]];
		free_chunk_resources(chunk.ptr());
	}
	_chunks.clear();
}

// --- generate_chunks_at -----------------------------------------------------

TypedArray<Vector2i> ChunkManager::generate_chunks_at(
		const TypedArray<Vector2i> &coords, int64_t seed_val) {
	TypedArray<Vector2i> new_chunks;

	for (int i = 0; i < coords.size(); i++) {
		Vector2i coord = coords[i];
		if (!_chunks.has(coord)) {
			create_chunk(coord);
			new_chunks.append(coord);
		}
	}

	if (new_chunks.is_empty()) {
		return new_chunks;
	}

	Ref<BiomeDef> biome;
	if (_node) {
		Node *lm = _node->get_node_or_null(NodePath("/root/LevelManager"));
		if (lm) {
			biome = lm->get("current_biome");
		}
	}

	Object *gen_obj = nullptr;
	if (biome.is_valid() && biome->get_use_simplex_cave_generator() &&
			_simplex_cave_generator.is_valid()) {
		gen_obj = _simplex_cave_generator.ptr();
	} else if (_generator.is_valid()) {
		gen_obj = _generator.ptr();
	}

	if (gen_obj) {
		gen_obj->call("generate_chunks", _chunks, new_chunks, seed_val, biome,
				PackedByteArray());
	}

	update_render_neighbors(new_chunks, TypedArray<Vector2i>());
	return new_chunks;
}

// --- read_region ------------------------------------------------------------

PackedByteArray ChunkManager::read_region(Rect2i region) const {
	PackedByteArray out;
	out.resize(region.size.x * region.size.y);

	for (int y = region.position.y; y < region.position.y + region.size.y; y++) {
		for (int x = region.position.x; x < region.position.x + region.size.x; x++) {
			int chunk_cx = static_cast<int>(Math::floor(static_cast<double>(x) / CHUNK_SIZE));
			int chunk_cy = static_cast<int>(Math::floor(static_cast<double>(y) / CHUNK_SIZE));
			Vector2i chunk_coord(chunk_cx, chunk_cy);

			int out_idx = (y - region.position.y) * region.size.x + (x - region.position.x);
			out[out_idx] = 0;

			if (_chunks.has(chunk_coord)) {
				Ref<Chunk> chunk = _chunks[chunk_coord];
				int local_x = ((x % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE;
				int local_y = ((y % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE;
				out[out_idx] = chunk->cells[local_y * CHUNK_SIZE + local_x].material;
			}
		}
	}
	return out;
}

} // namespace toprogue
