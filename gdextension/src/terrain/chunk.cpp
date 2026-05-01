#include "chunk.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/mutex_lock.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>

using namespace godot;

namespace toprogue {

// --- Atomic dirty rect helpers (spec §6.4) -------------------------------

bool Chunk::extend_next_dirty_rect(int x0, int y0, int x1, int y1) {
	bool changed = false;

	int32_t old_v = next_min_x.load(std::memory_order_relaxed);
	while (x0 < old_v && !next_min_x.compare_exchange_weak(old_v, x0, std::memory_order_relaxed)) {
	}
	if (x0 < old_v)
		changed = true;

	old_v = next_min_y.load(std::memory_order_relaxed);
	while (y0 < old_v && !next_min_y.compare_exchange_weak(old_v, y0, std::memory_order_relaxed)) {
	}
	if (y0 < old_v)
		changed = true;

	old_v = next_max_x.load(std::memory_order_relaxed);
	while (x1 > old_v && !next_max_x.compare_exchange_weak(old_v, x1, std::memory_order_relaxed)) {
	}
	if (x1 > old_v)
		changed = true;

	old_v = next_max_y.load(std::memory_order_relaxed);
	while (y1 > old_v && !next_max_y.compare_exchange_weak(old_v, y1, std::memory_order_relaxed)) {
	}
	if (y1 > old_v)
		changed = true;

	return changed;
}

Rect2i Chunk::take_next_dirty_rect() {
	int32_t mx = next_min_x.exchange(INT32_MAX, std::memory_order_relaxed);
	int32_t my = next_min_y.exchange(INT32_MAX, std::memory_order_relaxed);
	int32_t Mx = next_max_x.exchange(INT32_MIN, std::memory_order_relaxed);
	int32_t My = next_max_y.exchange(INT32_MIN, std::memory_order_relaxed);

	if (Mx < mx || My < my) {
		return Rect2i();
	}
	return Rect2i(mx, my, Mx - mx, My - my);
}

void Chunk::reset_next_dirty_rect() {
	next_min_x.store(INT32_MAX, std::memory_order_relaxed);
	next_min_y.store(INT32_MAX, std::memory_order_relaxed);
	next_max_x.store(INT32_MIN, std::memory_order_relaxed);
	next_max_y.store(INT32_MIN, std::memory_order_relaxed);
}

// --- Injection queue (spec §8.6) -----------------------------------------

void Chunk::push_injection(const InjectionAABB &aabb) {
	MutexLock lock(injection_queue_mutex);
	injection_queue.push_back(aabb);
}

Vector<InjectionAABB> Chunk::take_injections() {
	MutexLock lock(injection_queue_mutex);
	Vector<InjectionAABB> out = injection_queue;
	injection_queue.clear();
	return out;
}

PackedByteArray Chunk::get_cells_data() const {
	PackedByteArray out;
	out.resize(static_cast<int64_t>(sizeof(cells)));
	std::memcpy(out.ptrw(), cells, sizeof(cells));
	return out;
}

void Chunk::set_cells_data(const PackedByteArray &v) {
	if (v.size() != static_cast<int64_t>(sizeof(cells))) {
		UtilityFunctions::push_error(
				String("Chunk.set_cells_data: expected ") + String::num_int64(sizeof(cells)) +
				String(" bytes, got ") + String::num_int64(v.size()));
		return;
	}
	std::memcpy(cells, v.ptr(), sizeof(cells));
}

void Chunk::_bind_methods() {
	ClassDB::bind_static_method("Chunk", D_METHOD("get_chunk_size"), &Chunk::get_chunk_size);

	// --- Legacy GPU-pipeline properties ------------------------------
	ClassDB::bind_method(D_METHOD("get_coord"), &Chunk::get_coord);
	ClassDB::bind_method(D_METHOD("set_coord", "v"), &Chunk::set_coord);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "coord"), "set_coord", "get_coord");

	ClassDB::bind_method(D_METHOD("get_rd_texture"), &Chunk::get_rd_texture);
	ClassDB::bind_method(D_METHOD("set_rd_texture", "v"), &Chunk::set_rd_texture);
	ADD_PROPERTY(PropertyInfo(Variant::RID, "rd_texture"),
			"set_rd_texture", "get_rd_texture");

	ClassDB::bind_method(D_METHOD("get_texture_2d_rd"), &Chunk::get_texture_2d_rd);
	ClassDB::bind_method(D_METHOD("set_texture_2d_rd", "v"), &Chunk::set_texture_2d_rd);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "texture_2d_rd",
						 PROPERTY_HINT_RESOURCE_TYPE, "Texture2DRD"),
			"set_texture_2d_rd", "get_texture_2d_rd");

	ClassDB::bind_method(D_METHOD("get_mesh_instance"), &Chunk::get_mesh_instance);
	ClassDB::bind_method(D_METHOD("set_mesh_instance", "v"), &Chunk::set_mesh_instance);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "mesh_instance",
						 PROPERTY_HINT_NODE_TYPE, "MeshInstance2D"),
			"set_mesh_instance", "get_mesh_instance");

	ClassDB::bind_method(D_METHOD("get_wall_mesh_instance"), &Chunk::get_wall_mesh_instance);
	ClassDB::bind_method(D_METHOD("set_wall_mesh_instance", "v"), &Chunk::set_wall_mesh_instance);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "wall_mesh_instance",
						 PROPERTY_HINT_NODE_TYPE, "MeshInstance2D"),
			"set_wall_mesh_instance", "get_wall_mesh_instance");

	ClassDB::bind_method(D_METHOD("get_sim_uniform_set"), &Chunk::get_sim_uniform_set);
	ClassDB::bind_method(D_METHOD("set_sim_uniform_set", "v"), &Chunk::set_sim_uniform_set);
	ADD_PROPERTY(PropertyInfo(Variant::RID, "sim_uniform_set"),
			"set_sim_uniform_set", "get_sim_uniform_set");

	ClassDB::bind_method(D_METHOD("get_injection_buffer"), &Chunk::get_injection_buffer);
	ClassDB::bind_method(D_METHOD("set_injection_buffer", "v"), &Chunk::set_injection_buffer);
	ADD_PROPERTY(PropertyInfo(Variant::RID, "injection_buffer"),
			"set_injection_buffer", "get_injection_buffer");

	ClassDB::bind_method(D_METHOD("get_static_body"), &Chunk::get_static_body);
	ClassDB::bind_method(D_METHOD("set_static_body", "v"), &Chunk::set_static_body);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "static_body",
						 PROPERTY_HINT_NODE_TYPE, "StaticBody2D"),
			"set_static_body", "get_static_body");

	ClassDB::bind_method(D_METHOD("get_occluder_instances"), &Chunk::get_occluder_instances);
	ClassDB::bind_method(D_METHOD("set_occluder_instances", "v"), &Chunk::set_occluder_instances);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "occluder_instances",
						 PROPERTY_HINT_ARRAY_TYPE, "LightOccluder2D"),
			"set_occluder_instances", "get_occluder_instances");

	// --- New spec §6.1 sim properties --------------------------------
	ClassDB::bind_method(D_METHOD("get_cells_data"), &Chunk::get_cells_data);
	ClassDB::bind_method(D_METHOD("set_cells_data", "v"), &Chunk::set_cells_data);

	ClassDB::bind_method(D_METHOD("get_dirty_rect"), &Chunk::get_dirty_rect);
	ClassDB::bind_method(D_METHOD("set_dirty_rect", "v"), &Chunk::set_dirty_rect);
	ADD_PROPERTY(PropertyInfo(Variant::RECT2I, "dirty_rect"),
			"set_dirty_rect", "get_dirty_rect");

	ClassDB::bind_method(D_METHOD("get_sleeping"), &Chunk::get_sleeping);
	ClassDB::bind_method(D_METHOD("set_sleeping", "v"), &Chunk::set_sleeping);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "sleeping"),
			"set_sleeping", "get_sleeping");

	ClassDB::bind_method(D_METHOD("get_collider_dirty"), &Chunk::get_collider_dirty);
	ClassDB::bind_method(D_METHOD("set_collider_dirty", "v"), &Chunk::set_collider_dirty);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "collider_dirty"),
			"set_collider_dirty", "get_collider_dirty");

	ClassDB::bind_method(D_METHOD("get_neighbor_up"), &Chunk::get_neighbor_up);
	ClassDB::bind_method(D_METHOD("set_neighbor_up", "v"), &Chunk::set_neighbor_up);
	ClassDB::bind_method(D_METHOD("get_neighbor_down"), &Chunk::get_neighbor_down);
	ClassDB::bind_method(D_METHOD("set_neighbor_down", "v"), &Chunk::set_neighbor_down);
	ClassDB::bind_method(D_METHOD("get_neighbor_left"), &Chunk::get_neighbor_left);
	ClassDB::bind_method(D_METHOD("set_neighbor_left", "v"), &Chunk::set_neighbor_left);
	ClassDB::bind_method(D_METHOD("get_neighbor_right"), &Chunk::get_neighbor_right);
	ClassDB::bind_method(D_METHOD("set_neighbor_right", "v"), &Chunk::set_neighbor_right);

	ClassDB::bind_method(D_METHOD("get_texture"), &Chunk::get_texture);
	ClassDB::bind_method(D_METHOD("set_texture", "v"), &Chunk::set_texture);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "texture",
						 PROPERTY_HINT_RESOURCE_TYPE, "ImageTexture"),
			"set_texture", "get_texture");
}

} // namespace toprogue
