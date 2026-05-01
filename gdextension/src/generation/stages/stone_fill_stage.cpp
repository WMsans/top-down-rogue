#include "../../terrain/chunk.h"
#include "../stage_context.h"

using namespace godot;

namespace toprogue {

void stage_stone_fill(Chunk *chunk, const StageContext &ctx) {
	for (int i = 0; i < Chunk::CELL_COUNT; i++) {
		chunk->cells[i].material = static_cast<uint8_t>(ctx.stone_id);
		chunk->cells[i].health = 255;
		chunk->cells[i].temperature = 0;
		chunk->cells[i].flags = 0;
	}
}

} // namespace toprogue
