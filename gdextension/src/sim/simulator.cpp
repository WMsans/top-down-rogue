#include "simulator.h"

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

void Simulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_world_seed", "seed"), &Simulator::set_world_seed);
	ClassDB::bind_method(D_METHOD("set_chunks", "chunks"), &Simulator::set_chunks);
	ClassDB::bind_method(D_METHOD("tick"), &Simulator::tick);
	ClassDB::bind_method(D_METHOD("add_active", "chunk"), &Simulator::add_active);
	ClassDB::bind_method(D_METHOD("remove_active", "chunk"), &Simulator::remove_active);
}

void Simulator::set_world_seed(int64_t seed) {
	_world_seed = seed;
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

	Vector<Chunk *> active;
	active.resize(0);
	for (Chunk *c : _active) {
		if (c && !c->get_sleeping()) active.push_back(c);
	}

	// 4-phase chunk-checkerboard.
	for (int phase = 0; phase < 4; phase++) {
		int px = phase & 1;
		int py = (phase >> 1) & 1;

		// Filter chunks matching this phase's parity
		_phase_chunks.clear();
		for (Chunk *c : active) {
			Vector2i coord = c->get_coord();
			if (((coord.x & 1) == px) && ((coord.y & 1) == py)) {
				_phase_chunks.push_back(c);
			}
		}

		if (_phase_chunks.size() == 0) {
			continue;
		}

		// Build ChunkView for each chunk in this phase
		_phase_views.clear();
		for (Chunk *c : _phase_chunks) {
			ChunkView v;
			v.center = c;
			v.up = c->get_neighbor_up().ptr();
			v.down = c->get_neighbor_down().ptr();
			v.left = c->get_neighbor_left().ptr();
			v.right = c->get_neighbor_right().ptr();
			v.cells = c->cells_ptr();
			v.cells_up = v.up ? v.up->cells_ptr() : nullptr;
			v.cells_down = v.down ? v.down->cells_ptr() : nullptr;
			v.cells_left = v.left ? v.left->cells_ptr() : nullptr;
			v.cells_right = v.right ? v.right->cells_ptr() : nullptr;
			MaterialTable *mt = MaterialTable::get_singleton();
			v.frame_seed = _current_frame_seed;
			v.frame_index = _frame_index;
			v.air_id = mt->get_MAT_AIR();
			v.gas_id = mt->get_MAT_GAS();
			v.lava_id = mt->get_MAT_LAVA();
			v.water_id = mt->get_MAT_WATER();
			_phase_views.push_back(v);
		}

		WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
		Callable task = callable_mp(this, &Simulator::_group_task_body);
		pool->add_group_task(task, _phase_chunks.size(), -1, true,
				String("Simulator::phase_") + String::num_int64(phase));
	}

	rotate_dirty_rects();
	upload_dirty_textures();

	// Promote any chunk whose neighbor pushed border writes into it.
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
	if (index < 0 || index >= _phase_views.size()) {
		return;
	}
	tick_chunk(_phase_views.ptrw()[index]);
}

void Simulator::tick_chunk(ChunkView &view) {
	Chunk *chunk = view.center;
	if (!chunk) {
		return;
	}
	if (chunk->get_sleeping()) {
		return;
	}

	run_injection(view);
	run_lava(view);
	run_gas(view);
	run_burning(view);
}

void Simulator::rotate_dirty_rects() {
	Array keys = _chunks.keys();
	for (int i = 0; i < keys.size(); i++) {
		Ref<Chunk> c = _chunks[keys[i]];
		if (!c.is_valid()) {
			continue;
		}

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
