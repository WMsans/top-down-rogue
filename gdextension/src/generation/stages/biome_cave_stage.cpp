#include "../../terrain/chunk.h"
#include "../stage_context.h"
#include "../../util/simplex.h"

using namespace godot;

namespace toprogue {

void stage_biome_cave(Chunk *chunk, const StageContext &ctx) {
	Ref<BiomeDef> b = ctx.biome;
	if (b.is_null())
		return;

	const float cave_scale = static_cast<float>(b->cave_noise_scale);
	const float cave_threshold = static_cast<float>(b->cave_threshold);
	const float ridge_weight = static_cast<float>(b->ridge_weight);
	const float ridge_scale = static_cast<float>(b->ridge_scale);
	const int octaves = b->octaves;
	const int bg_mat = b->background_material;
	const int air_id = ctx.air_id;

	for (int y = 0; y < Chunk::CHUNK_SIZE; y++) {
		for (int x = 0; x < Chunk::CHUNK_SIZE; x++) {
			float wx = static_cast<float>(ctx.chunk_coord.x * Chunk::CHUNK_SIZE + x);
			float wy = static_cast<float>(ctx.chunk_coord.y * Chunk::CHUNK_SIZE + y);

			float n = simplex::simplex_fbm(wx * cave_scale, wy * cave_scale, ctx.world_seed, octaves);
			float r = simplex::simplex_ridge(wx * ridge_scale, wy * ridge_scale,
					simplex::hash_combine(ctx.world_seed, 1000u), 4);
			float c = n * (1.0f - ridge_weight) + r * ridge_weight;

			int idx = y * Chunk::CHUNK_SIZE + x;
			if (c > cave_threshold) {
				chunk->cells[idx] = Cell{ static_cast<uint8_t>(air_id), 0, 0, 0 };
			} else {
				chunk->cells[idx] = Cell{ static_cast<uint8_t>(bg_mat), 0, 0, 0 };
			}
		}
	}
}

} // namespace toprogue
