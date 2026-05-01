#include "simplex_cave_generator.h"

#include "../sim/material_table.h"
#include "stage_context.h"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

#include <cstring>

using namespace godot;

namespace toprogue {

void stage_stone_fill(Chunk *chunk, const StageContext &ctx);
void stage_simplex_cave(Chunk *chunk, const StageContext &ctx);

SimplexCaveGenerator::SimplexCaveGenerator() {
	MaterialTable *mt = MaterialTable::get_singleton();
	if (mt) {
		air_id_ = mt->get_MAT_AIR();
		stone_id_ = mt->get_MAT_STONE();
	}
}

void SimplexCaveGenerator::run_pipeline(Chunk *chunk, const StageContext &ctx) const {
	stage_stone_fill(chunk, ctx);
	stage_simplex_cave(chunk, ctx);
}

void SimplexCaveGenerator::generate_chunks(
		const Dictionary &chunks,
		const TypedArray<Vector2i> &new_coords,
		int64_t world_seed,
		const Ref<BiomeDef> &biome,
		const PackedByteArray &stamp_bytes) {
	int n = new_coords.size();
	if (n == 0) {
		return;
	}

	_current_jobs.resize(n);
	_current_ctxs.resize(n);
	for (int i = 0; i < n; i++) {
		Vector2i coord = new_coords[i];
		Ref<Chunk> chunk = chunks[coord];
		if (chunk.is_null()) {
			_current_jobs[i] = nullptr;
			continue;
		}
		_current_jobs[i] = chunk.ptr();

		StageContext &c = _current_ctxs[i];
		c.chunk_coord = coord;
		c.world_seed = static_cast<uint32_t>(world_seed);
		c.biome = biome;
		c.stamp_bytes = stamp_bytes;
		c.air_id = air_id_;
		c.stone_id = stone_id_;
	}

	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	Callable task = callable_mp(this, &SimplexCaveGenerator::_run_one_indexed);
	int64_t group = pool->add_group_task(task, n, -1, true,
			"toprogue.SimplexCaveGenerator.generate_chunks");
	pool->wait_for_group_task_completion(group);

	RenderingDevice *rd = RenderingServer::get_singleton()->get_rendering_device();
	for (int i = 0; i < n; i++) {
		Chunk *c = _current_jobs[i];
		if (!c) {
			continue;
		}

		PackedByteArray bytes;
		bytes.resize(Chunk::CELL_COUNT * sizeof(Cell));
		std::memcpy(bytes.ptrw(), c->cells, Chunk::CELL_COUNT * sizeof(Cell));
		rd->texture_update(c->rd_texture, 0, bytes);

		c->dirty_rect = Rect2i(0, 0, Chunk::CHUNK_SIZE, Chunk::CHUNK_SIZE);
		c->sleeping = false;
	}

	_current_jobs.clear();
	_current_ctxs.clear();
}

void SimplexCaveGenerator::_run_one_indexed(int idx) {
	Chunk *c = _current_jobs[idx];
	if (!c) {
		return;
	}
	run_pipeline(c, _current_ctxs[idx]);
}

void SimplexCaveGenerator::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("generate_chunks", "chunks", "new_coords", "world_seed", "biome",
					"stamp_bytes"),
			&SimplexCaveGenerator::generate_chunks);
}

} // namespace toprogue
