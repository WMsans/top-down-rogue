#pragma once

#include "../terrain/chunk.h"

#include <cstdint>

namespace toprogue {

class SimContext {
public:
	Chunk *chunk = nullptr;
	Chunk *up = nullptr;
	Chunk *down = nullptr;
	Chunk *left = nullptr;
	Chunk *right = nullptr;
	uint32_t frame_seed = 0;
	int frame_index = 0;

	int air_id = 0;
	int gas_id = 0;
	int lava_id = 0;
	int water_id = 0;

	static uint32_t hash_u32(uint32_t n);
	uint32_t hash3(int x, int y, uint32_t salt) const;
	bool stochastic_div(int x, int y, uint32_t salt, int divisor) const;

	Cell *cell_at(int x, int y);
	const Cell *cell_at(int x, int y) const;
	void write_cell(int x, int y, const Cell &c);
	void swap_cell(int x_a, int y_a, int x_b, int y_b);
	bool is_solid(int x, int y) const;

	void wake(Chunk *target, int x, int y);

	// Velocity packing helpers (spec §6.1 flags layout)
	static void pack_velocity(uint8_t &flags, int8_t vx, int8_t vy);
	static void unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy);

private:
	Chunk *resolve_target(int x, int y, int &out_x, int &out_y) const;
};

} // namespace toprogue
