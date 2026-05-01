#include "../../resources/pool_def.h"
#include "../../terrain/chunk.h"
#include "../../util/simplex.h"
#include "../stage_context.h"

#include <godot_cpp/variant/typed_array.hpp>

using namespace godot;

namespace toprogue {

void stage_biome_pools(Chunk *chunk, const StageContext &ctx) {
	Ref<BiomeDef> b = ctx.biome;
	if (b.is_null()) {
		return;
	}

	TypedArray<PoolDef> pools = b->pool_materials;
	int pool_count = MIN(pools.size(), 4);
	if (pool_count == 0) {
		return;
	}

	int air_id = ctx.air_id;

	for (int y = 0; y < Chunk::CHUNK_SIZE; y++) {
		for (int x = 0; x < Chunk::CHUNK_SIZE; x++) {
			int idx = y * Chunk::CHUNK_SIZE + x;
			if (chunk->cells[idx].material == air_id) {
				continue;
			}

			float wx = static_cast<float>(ctx.chunk_coord.x * Chunk::CHUNK_SIZE + x);
			float wy = static_cast<float>(ctx.chunk_coord.y * Chunk::CHUNK_SIZE + y);

			for (int i = 0; i < pool_count; i++) {
				Ref<PoolDef> p = pools[i];
				if (p.is_null() || p->material_id <= 0) {
					continue;
				}
				uint32_t pseed = simplex::hash_combine(ctx.world_seed, static_cast<uint32_t>(p->seed_offset));
				float n = simplex::simplex_fbm(wx * static_cast<float>(p->noise_scale),
						wy * static_cast<float>(p->noise_scale), pseed, 2);
				if (n > static_cast<float>(p->noise_threshold)) {
					chunk->cells[idx].material = static_cast<uint8_t>(p->material_id);
					break;
				}
			}
		}
	}
}

} // namespace toprogue
