#include "../../terrain/chunk.h"
#include "../stage_context.h"

using namespace godot;

namespace toprogue {

void stage_stone_fill(Chunk *chunk, const StageContext &ctx) {
	for (int i = 0; i < Chunk::CELL_COUNT; i++) {
		chunk->set_cell_material(i, static_cast<uint8_t>(ctx.stone_id));
		chunk->set_cell_health(i, 255);
		chunk->set_cell_temperature(i, 0);
		chunk->set_cell_flags(i, 0);
	}
}

} // namespace toprogue
