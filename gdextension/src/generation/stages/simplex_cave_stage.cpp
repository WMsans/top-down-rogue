#include "../../terrain/chunk.h"
#include "../../util/simplex.h"
#include "../stage_context.h"

using namespace godot;

namespace toprogue {

void stage_simplex_cave(Chunk *chunk, const StageContext &ctx) {
	constexpr float SCALE = 0.008f;
	constexpr float THRESHOLD = 0.42f;
	constexpr float RIDGE_SCALE = 0.012f;
	constexpr float RIDGE_WEIGHT = 0.3f;
	constexpr int OCTAVES = 5;

	int air_id = ctx.air_id;

	for (int y = 0; y < Chunk::CHUNK_SIZE; y++) {
		for (int x = 0; x < Chunk::CHUNK_SIZE; x++) {
			float wx = static_cast<float>(ctx.chunk_coord.x * Chunk::CHUNK_SIZE + x);
			float wy = static_cast<float>(ctx.chunk_coord.y * Chunk::CHUNK_SIZE + y);
			float n = simplex::simplex_fbm(wx * SCALE, wy * SCALE, ctx.world_seed, OCTAVES);
			float r = simplex::simplex_ridge(wx * RIDGE_SCALE, wy * RIDGE_SCALE,
					simplex::hash_combine(ctx.world_seed, 1000u), 4);
			float c = n * (1.0f - RIDGE_WEIGHT) + r * RIDGE_WEIGHT;
			if (c > THRESHOLD) {
				chunk->set_cell_material(y * Chunk::CHUNK_SIZE + x, static_cast<uint8_t>(air_id)); chunk->set_cell_health(y * Chunk::CHUNK_SIZE + x, 0); chunk->set_cell_temperature(y * Chunk::CHUNK_SIZE + x, 0); chunk->set_cell_flags(y * Chunk::CHUNK_SIZE + x, 0);
			}
		}
	}
}

} // namespace toprogue
