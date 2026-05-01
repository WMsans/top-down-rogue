#include "generator.h"

#include "../sim/material_table.h"
#include "stage_context.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

#include <cstring>

using namespace godot;

namespace toprogue {

void stage_wood_fill(Chunk *chunk, const StageContext &ctx);
void stage_biome_cave(Chunk *chunk, const StageContext &ctx);
void stage_biome_pools(Chunk *chunk, const StageContext &ctx);
void stage_pixel_scene_stamp(Chunk *chunk, const StageContext &ctx);
void stage_secret_ring(Chunk *chunk, const StageContext &ctx);

Generator::Generator() {
	MaterialTable *mt = MaterialTable::get_singleton();
	if (mt) {
		air_id_ = mt->get_MAT_AIR();
		wood_id_ = mt->get_MAT_WOOD();
		stone_id_ = mt->get_MAT_STONE();
	}
}

void Generator::run_pipeline(Chunk *chunk, const StageContext &ctx) const {
	stage_wood_fill(chunk, ctx);
	stage_biome_cave(chunk, ctx);
	stage_biome_pools(chunk, ctx);
	stage_pixel_scene_stamp(chunk, ctx);
	stage_secret_ring(chunk, ctx);
}

void Generator::generate_chunks(
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
		c.wood_id = wood_id_;
		c.stone_id = stone_id_;
	}

	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	Callable task = callable_mp(this, &Generator::_run_one_indexed);
	int64_t group = pool->add_group_task(task, n, -1, true,
			"toprogue.Generator.generate_chunks");
	pool->wait_for_group_task_completion(group);

	for (int i = 0; i < n; i++) {
		Chunk *c = _current_jobs[i];
		if (!c) {
			continue;
		}

		c->upload_texture_full();

		c->dirty_rect = Rect2i(0, 0, Chunk::CHUNK_SIZE, Chunk::CHUNK_SIZE);
		c->sleeping = false;
	}

	_current_jobs.clear();
	_current_ctxs.clear();
}

void Generator::_run_one_indexed(int idx) {
	Chunk *c = _current_jobs[idx];
	if (!c) {
		return;
	}
	run_pipeline(c, _current_ctxs[idx]);
}

void Generator::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("generate_chunks", "chunks", "new_coords", "world_seed", "biome",
					"stamp_bytes"),
			&Generator::generate_chunks);
}

} // namespace toprogue
