#pragma once

#include "../terrain/chunk.h"

#include <cstdint>

namespace toprogue {

struct ChunkView {
	Chunk *center;
	Chunk *up, *down, *left, *right;

	Cell *cells;
	Cell *cells_up;
	Cell *cells_down;
	Cell *cells_left;
	Cell *cells_right;

	uint32_t frame_seed;
	int frame_index;
	int air_id, gas_id, lava_id, water_id;

	static constexpr int SZ = Chunk::CHUNK_SIZE;

	Cell *at(int x, int y);
	Cell *at_border(int x, int y);

	static uint32_t hash_u32(uint32_t n);
	uint32_t hash3(int x, int y, uint32_t salt) const;
	bool stochastic_div(int x, int y, uint32_t salt, int divisor) const;
	static void pack_velocity(uint8_t &flags, int8_t vx, int8_t vy);
	static void unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy);
};

} // namespace toprogue
