#pragma once

#include "../terrain/chunk.h"

#include <cstdint>

namespace toprogue {

struct ChunkView {
	Chunk *center, *up, *down, *left, *right;

	uint8_t *mat, *mat_up, *mat_down, *mat_left, *mat_right;
	uint8_t *health, *health_up, *health_down, *health_left, *health_right;
	uint8_t *temperature, *temperature_up, *temperature_down, *temperature_left, *temperature_right;
	uint8_t *flags, *flags_up, *flags_down, *flags_left, *flags_right;

	uint32_t frame_seed;
	int frame_index;
	int air_id, gas_id, lava_id, water_id;

	static constexpr int SZ = Chunk::CHUNK_SIZE;

	Cell read(int x, int y);
	bool write_changed(int x, int y, const Cell &nv);

	static uint32_t hash_u32(uint32_t n);
	uint32_t hash3(int x, int y, uint32_t salt) const;
	bool stochastic_div(int x, int y, uint32_t salt, int divisor) const;
	static void pack_velocity(uint8_t &flags, int8_t vx, int8_t vy);
	static void unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy);
};

} // namespace toprogue
