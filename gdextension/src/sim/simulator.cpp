#include "simulator.h"

#include "../sim/material_table.h"
#include "rules/injection.h"
#include "rules/lava.h"
#include "rules/gas.h"
#include "rules/burning.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

namespace toprogue {

void Simulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_world_seed", "seed"), &Simulator::set_world_seed);
	ClassDB::bind_method(D_METHOD("set_chunks", "chunks"), &Simulator::set_chunks);
	ClassDB::bind_method(D_METHOD("tick"), &Simulator::tick);
}

void Simulator::set_world_seed(int64_t seed) {
	_world_seed = seed;
}

void Simulator::set_chunks(const Dictionary &chunks) {
	_chunks = chunks;
}

void Simulator::tick() {
	_frame_index++;
	_current_frame_seed = static_cast<uint32_t>(_world_seed) ^
			static_cast<uint32_t>(_frame_index * 0x9E3779B1u);

	// Build the active set: all non-sleeping chunks.
	Array keys = _chunks.keys();
	Vector<Chunk *> active;
	for (int i = 0; i < keys.size(); i++) {
		Ref<Chunk> c = _chunks[keys[i]];
		if (c.is_valid() && !c->get_sleeping()) {
			active.push_back(c.ptr());
		}
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

		if (_phase_chunks.size() == 0) continue;

		WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
		Callable task = callable_mp(this, &Simulator::_group_task_body);
		pool->add_group_task(task, _phase_chunks.size(), -1, true,
				String("Simulator::phase_") + String::num_int64(phase));
	}

	rotate_dirty_rects();
	upload_dirty_textures();
}

void Simulator::_group_task_body(int32_t index) {
	if (index < 0 || index >= _phase_chunks.size()) return;
	tick_chunk(_phase_chunks[index]);
}

void Simulator::tick_chunk(Chunk *chunk) {
	if (!chunk) return;
	if (chunk->get_sleeping()) return;

	MaterialTable *mt = MaterialTable::get_singleton();

	SimContext ctx;
	ctx.chunk = chunk;
	ctx.up = chunk->get_neighbor_up().ptr();
	ctx.down = chunk->get_neighbor_down().ptr();
	ctx.left = chunk->get_neighbor_left().ptr();
	ctx.right = chunk->get_neighbor_right().ptr();
	ctx.frame_seed = _current_frame_seed;
	ctx.frame_index = _frame_index;
	ctx.air_id = mt->get_MAT_AIR();
	ctx.gas_id = mt->get_MAT_GAS();
	ctx.lava_id = mt->get_MAT_LAVA();
	ctx.water_id = mt->get_MAT_WATER();

	run_injection(ctx);
	run_lava(ctx);
	run_gas(ctx);
	run_burning(ctx);
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
