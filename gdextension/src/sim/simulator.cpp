#include "simulator.h"

#include "../sim/material_kind.h"
#include "../sim/material_table.h"
#include "rules/burning.h"
#include "rules/gas.h"
#include "rules/injection.h"
#include "rules/lava.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

namespace toprogue {

Simulator::Simulator() {
	rebuild_material_kind_table();
}

void Simulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_world_seed", "seed"), &Simulator::set_world_seed);
	ClassDB::bind_method(D_METHOD("set_serial_mode", "v"), &Simulator::set_serial_mode);
	ClassDB::bind_method(D_METHOD("set_chunks", "chunks"), &Simulator::set_chunks);
	ClassDB::bind_method(D_METHOD("tick"), &Simulator::tick);
	ClassDB::bind_method(D_METHOD("add_active", "chunk"), &Simulator::add_active);
	ClassDB::bind_method(D_METHOD("remove_active", "chunk"), &Simulator::remove_active);
}

void Simulator::set_world_seed(int64_t seed) {
	_world_seed = seed;
}

void Simulator::set_serial_mode(bool v) {
	_serial_mode = v;
}

void Simulator::set_chunks(const Dictionary &chunks) {
	_chunks = chunks;
}

void Simulator::add_active(Chunk *chunk) {
	if (!chunk) return;
	for (Chunk *c : _active) if (c == chunk) return;
	_active.push_back(chunk);
}

void Simulator::remove_active(Chunk *chunk) {
	for (auto it = _active.begin(); it != _active.end(); ++it) {
		if (*it == chunk) { _active.erase(it); return; }
	}
}

void Simulator::tick() {
	_frame_index++;
	_current_frame_seed = static_cast<uint32_t>(_world_seed) ^
			static_cast<uint32_t>(_frame_index * 0x9E3779B1u);

	// Build active set
	Vector<Chunk *> active;
	for (Chunk *c : _active) {
		if (c && !c->get_sleeping()) active.push_back(c);
	}

	// Dynamic-parity: bucket active chunks by (x&1, y&1)
	godot::Vector<Chunk *> buckets[4];
	for (int b = 0; b < 4; b++) buckets[b].clear();
	for (Chunk *c : active) {
		Vector2i co = c->get_coord();
		int b = (co.x & 1) | ((co.y & 1) << 1);
		buckets[b].push_back(c);
	}

	for (int b = 0; b < 4; b++) {
		if (buckets[b].size() == 0) continue;

		_phase_chunks = buckets[b];

		// Build ChunkView for each chunk in this parity
		_phase_views.clear();
		for (Chunk *c : _phase_chunks) {
			ChunkView v;
			v.center = c;
			v.up = c->get_neighbor_up().ptr();
			v.down = c->get_neighbor_down().ptr();
			v.left = c->get_neighbor_left().ptr();
			v.right = c->get_neighbor_right().ptr();
			v.mat = c->material_ptr();
			v.health = c->health_ptr();
			v.temperature = c->temperature_ptr();
			v.flags = c->flags_ptr();
			v.mat_up = v.up ? v.up->material_ptr() : nullptr;
			v.mat_down = v.down ? v.down->material_ptr() : nullptr;
			v.mat_left = v.left ? v.left->material_ptr() : nullptr;
			v.mat_right = v.right ? v.right->material_ptr() : nullptr;
			v.health_up = v.up ? v.up->health_ptr() : nullptr;
			v.health_down = v.down ? v.down->health_ptr() : nullptr;
			v.health_left = v.left ? v.left->health_ptr() : nullptr;
			v.health_right = v.right ? v.right->health_ptr() : nullptr;
			v.temperature_up = v.up ? v.up->temperature_ptr() : nullptr;
			v.temperature_down = v.down ? v.down->temperature_ptr() : nullptr;
			v.temperature_left = v.left ? v.left->temperature_ptr() : nullptr;
			v.temperature_right = v.right ? v.right->temperature_ptr() : nullptr;
			v.flags_up = v.up ? v.up->flags_ptr() : nullptr;
			v.flags_down = v.down ? v.down->flags_ptr() : nullptr;
			v.flags_left = v.left ? v.left->flags_ptr() : nullptr;
			v.flags_right = v.right ? v.right->flags_ptr() : nullptr;
			MaterialTable *mt = MaterialTable::get_singleton();
			v.frame_seed = _current_frame_seed;
			v.frame_index = _frame_index;
			v.air_id = mt->get_MAT_AIR();
			v.gas_id = mt->get_MAT_GAS();
			v.lava_id = mt->get_MAT_LAVA();
			v.water_id = mt->get_MAT_WATER();
			_phase_views.push_back(v);
		}

		if (_serial_mode) {
			for (int i = 0; i < _phase_views.size(); i++)
				tick_chunk(_phase_views.ptrw()[i]);
		} else {
			WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
			Callable task = callable_mp(this, &Simulator::_group_task_body);
			pool->add_group_task(task, _phase_views.size(), -1, true,
					String("Simulator::parity_") + String::num_int64(b));
		}
	}

	rotate_dirty_rects();
	upload_dirty_textures();

	// Promote wake_pending neighbors
	{
		Array keys = _chunks.keys();
		for (int i = 0; i < keys.size(); i++) {
			Ref<Chunk> c = _chunks[keys[i]];
			if (c.is_valid() && c->wake_pending.load(std::memory_order_relaxed)) {
				c->wake_pending.store(false, std::memory_order_relaxed);
				c->set_sleeping(false);
				add_active(c.ptr());
			}
		}
	}
}

void Simulator::_group_task_body(int32_t index) {
	if (index < 0 || index >= _phase_views.size()) return;
	tick_chunk(_phase_views.ptrw()[index]);
}

void Simulator::tick_chunk(ChunkView &v) {
	Chunk *chunk = v.center;
	if (!chunk || chunk->get_sleeping()) return;

	run_injection(v);
	run_lava(v);
	run_gas(v);
	run_burning(v);
}

void Simulator::rotate_dirty_rects() {
	Array keys = _chunks.keys();
	for (int i = 0; i < keys.size(); i++) {
		Ref<Chunk> c = _chunks[keys[i]];
		if (!c.is_valid()) continue;

		Rect2i next = c->take_next_dirty_rect();
		if (next.size.x > 0 && next.size.y > 0) {
			c->set_dirty_rect(next);
			c->set_sleeping(false);
		} else {
			c->set_dirty_rect(Rect2i());
			c->set_sleeping(true);
		}
	}
}

void Simulator::upload_dirty_textures() {
	Array keys = _chunks.keys();
	for (int i = 0; i < keys.size(); i++) {
		Ref<Chunk> c = _chunks[keys[i]];
		if (c.is_valid() && c->get_dirty_rect().size.x > 0) {
			c->upload_texture();
		}
	}
}

} // namespace toprogue
