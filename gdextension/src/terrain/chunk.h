#pragma once

#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/light_occluder2d.hpp>
#include <godot_cpp/classes/mesh_instance2d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/static_body2d.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <atomic>
#include <cstdint>
#include <mutex>

namespace toprogue {

struct Cell {
	uint8_t material;
	uint8_t health;
	uint8_t temperature;
	uint8_t flags;
};
static_assert(sizeof(Cell) == 4, "Cell must be 4 bytes; spec §6.1");

#pragma pack(push, 1)
struct InjectionAABB {
	int16_t min_x, min_y, max_x, max_y;
	int8_t vel_x, vel_y;
	uint8_t target_kind;
};
#pragma pack(pop)

class Chunk : public godot::RefCounted {
	GDCLASS(Chunk, godot::RefCounted);

public:
	static constexpr int CHUNK_SIZE = 256;
	static constexpr int CELL_COUNT = CHUNK_SIZE * CHUNK_SIZE;

	// --- Chunk fields ---------------------------------------------------
	godot::Vector2i coord;
	godot::MeshInstance2D *mesh_instance = nullptr;
	godot::MeshInstance2D *wall_mesh_instance = nullptr;
	godot::StaticBody2D *static_body = nullptr;
	godot::TypedArray<godot::LightOccluder2D> occluder_instances;

	// --- New spec §6.1 sim fields ---------------------------------------
private:
	struct ChunkCells {
		alignas(64) uint8_t material[CELL_COUNT] = {};
		alignas(64) uint8_t health[CELL_COUNT] = {};
		alignas(64) uint8_t temperature[CELL_COUNT] = {};
		alignas(64) uint8_t flags[CELL_COUNT] = {};
	};
	ChunkCells _cells;

public:
	uint8_t *material_ptr()    { return _cells.material; }
	uint8_t *health_ptr()      { return _cells.health; }
	uint8_t *temperature_ptr() { return _cells.temperature; }
	uint8_t *flags_ptr()       { return _cells.flags; }
	const uint8_t *material_ptr()    const { return _cells.material; }
	const uint8_t *health_ptr()      const { return _cells.health; }
	const uint8_t *temperature_ptr() const { return _cells.temperature; }
	const uint8_t *flags_ptr()       const { return _cells.flags; }

	inline uint8_t cell_material(int idx) const { return _cells.material[idx]; }
	inline uint8_t cell_health(int idx) const { return _cells.health[idx]; }
	inline uint8_t cell_temperature(int idx) const { return _cells.temperature[idx]; }
	inline uint8_t cell_flags(int idx) const { return _cells.flags[idx]; }

	inline void set_cell_material(int idx, uint8_t v) { _cells.material[idx] = v; }
	inline void set_cell_health(int idx, uint8_t v)   { _cells.health[idx] = v; }
	inline void set_cell_temperature(int idx, uint8_t v) { _cells.temperature[idx] = v; }
	inline void set_cell_flags(int idx, uint8_t v)    { _cells.flags[idx] = v; }

	inline uint8_t *cell_material_ptr(int idx) { return &_cells.material[idx]; }
	inline uint8_t *cell_health_ptr(int idx)   { return &_cells.health[idx]; }
	inline uint8_t *cell_flags_ptr(int idx)    { return &_cells.flags[idx]; }

	godot::Rect2i dirty_rect;
	bool sleeping = true;
	bool collider_dirty = false;
	godot::Ref<Chunk> neighbor_up;
	godot::Ref<Chunk> neighbor_down;
	godot::Ref<Chunk> neighbor_left;
	godot::Ref<Chunk> neighbor_right;
	godot::Ref<godot::ImageTexture> texture;

	static constexpr int TILE_SIZE = 64;
	static constexpr int TILES_PER_SIDE = CHUNK_SIZE / TILE_SIZE;
	static constexpr int TILE_COUNT = TILES_PER_SIDE * TILES_PER_SIDE;

	godot::Ref<godot::Texture2DArray> tiled_texture;
	godot::Ref<godot::Image> tile_images[TILE_COUNT];

	// --- Plain next_dirty_rect (spec §6.4) ----------------------------
private:
	int32_t next_min_x = INT32_MAX;
	int32_t next_min_y = INT32_MAX;
	int32_t next_max_x = INT32_MIN;
	int32_t next_max_y = INT32_MIN;

public:
	std::atomic<bool> wake_pending{ false };

	bool extend_next_dirty_rect(int x0, int y0, int x1, int y1);
	godot::Rect2i take_next_dirty_rect();
	void reset_next_dirty_rect();

	// --- Per-chunk injection queue (spec §8.6) -------------------------
private:
	godot::Vector<InjectionAABB> injection_queue;
	std::mutex injection_queue_mutex;

public:
	void push_injection(const InjectionAABB &aabb);
	godot::Vector<InjectionAABB> take_injections();

	Chunk() = default;

	static int get_chunk_size() { return CHUNK_SIZE; }

	// --- Field bindings -------------------------------------------------
	godot::Vector2i get_coord() const { return coord; }
	void set_coord(const godot::Vector2i &v) { coord = v; }
	godot::MeshInstance2D *get_mesh_instance() const { return mesh_instance; }
	void set_mesh_instance(godot::MeshInstance2D *v) { mesh_instance = v; }
	godot::MeshInstance2D *get_wall_mesh_instance() const { return wall_mesh_instance; }
	void set_wall_mesh_instance(godot::MeshInstance2D *v) { wall_mesh_instance = v; }
	godot::StaticBody2D *get_static_body() const { return static_body; }
	void set_static_body(godot::StaticBody2D *v) { static_body = v; }
	godot::TypedArray<godot::LightOccluder2D> get_occluder_instances() const { return occluder_instances; }
	void set_occluder_instances(const godot::TypedArray<godot::LightOccluder2D> &v) { occluder_instances = v; }

	// --- New sim-field bindings ----------------------------------------
	godot::PackedByteArray get_cells_data() const;
	void set_cells_data(const godot::PackedByteArray &v);

	godot::Rect2i get_dirty_rect() const { return dirty_rect; }
	void set_dirty_rect(const godot::Rect2i &v) { dirty_rect = v; }
	bool get_sleeping() const { return sleeping; }
	void set_sleeping(bool v) { sleeping = v; }
	bool get_collider_dirty() const { return collider_dirty; }
	void set_collider_dirty(bool v) { collider_dirty = v; }

	godot::Ref<Chunk> get_neighbor_up() const { return neighbor_up; }
	void set_neighbor_up(const godot::Ref<Chunk> &v) { neighbor_up = v; }
	godot::Ref<Chunk> get_neighbor_down() const { return neighbor_down; }
	void set_neighbor_down(const godot::Ref<Chunk> &v) { neighbor_down = v; }
	godot::Ref<Chunk> get_neighbor_left() const { return neighbor_left; }
	void set_neighbor_left(const godot::Ref<Chunk> &v) { neighbor_left = v; }
	godot::Ref<Chunk> get_neighbor_right() const { return neighbor_right; }
	void set_neighbor_right(const godot::Ref<Chunk> &v) { neighbor_right = v; }

	godot::Ref<godot::ImageTexture> get_texture() const { return texture; }
	void set_texture(const godot::Ref<godot::ImageTexture> &v) { texture = v; }

	godot::Ref<godot::Texture2DArray> get_tiled_texture() const { return tiled_texture; }
	void set_tiled_texture(const godot::Ref<godot::Texture2DArray> &v) { tiled_texture = v; }

	// upload_texture will be implemented in Task 8
	void upload_texture();
	void upload_texture_full();

protected:
	static void _bind_methods();
};

} // namespace toprogue
