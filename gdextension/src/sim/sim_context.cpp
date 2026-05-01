#include "sim_context.h"

namespace toprogue {

uint32_t SimContext::hash_u32(uint32_t n) {
	n = (n >> 16) ^ n;
	n *= 0xed5ad0bb;
	n = (n >> 16) ^ n;
	n *= 0xac4c1b51;
	n = (n >> 16) ^ n;
	return n;
}

uint32_t SimContext::hash3(int x, int y, uint32_t salt) const {
	return hash_u32(static_cast<uint32_t>(x) ^
			hash_u32(static_cast<uint32_t>(y) ^ frame_seed ^ salt));
}

bool SimContext::stochastic_div(int x, int y, uint32_t salt, int divisor) const {
	if (divisor <= 0) return false;
	uint32_t rng = hash3(x, y, salt);
	return (static_cast<int>(rng % static_cast<uint32_t>(divisor)) == 0);
}

static Cell EMPTY_CELL = { 0, 0, 0, 0 };

Chunk *SimContext::resolve_target(int x, int y, int &out_x, int &out_y) const {
	constexpr int SZ = Chunk::CHUNK_SIZE;

	if (x >= 0 && x < SZ && y >= 0 && y < SZ) {
		out_x = x;
		out_y = y;
		return chunk;
	}

	if (y < 0) {
		out_x = x;
		out_y = SZ + y;
		return up;
	}
	if (y >= SZ) {
		out_x = x;
		out_y = y - SZ;
		return down;
	}
	if (x < 0) {
		out_x = SZ + x;
		out_y = y;
		return left;
	}
	// x >= SZ
	out_x = x - SZ;
	out_y = y;
	return right;
}

Cell *SimContext::cell_at(int x, int y) {
	int lx, ly;
	Chunk *target = resolve_target(x, y, lx, ly);
	if (!target) return nullptr;
	return &target->cells[ly * Chunk::CHUNK_SIZE + lx];
}

const Cell *SimContext::cell_at(int x, int y) const {
	int lx, ly;
	Chunk *target = const_cast<SimContext *>(this)->resolve_target(x, y, lx, ly);
	if (!target) return nullptr;
	return &target->cells[ly * Chunk::CHUNK_SIZE + lx];
}

void SimContext::write_cell(int x, int y, const Cell &c) {
	int lx, ly;
	Chunk *target = resolve_target(x, y, lx, ly);
	if (!target) return;
	target->cells[ly * Chunk::CHUNK_SIZE + lx] = c;
	target->extend_next_dirty_rect(lx, ly, lx + 1, ly + 1);
	wake(target, lx, ly);
}

void SimContext::swap_cell(int x_a, int y_a, int x_b, int y_b) {
	int lxa, lya;
	Chunk *ta = resolve_target(x_a, y_a, lxa, lya);
	int lxb, lyb;
	Chunk *tb = resolve_target(x_b, y_b, lxb, lyb);

	Cell ca = EMPTY_CELL;
	Cell cb = EMPTY_CELL;
	if (ta) ca = ta->cells[lya * Chunk::CHUNK_SIZE + lxa];
	if (tb) cb = tb->cells[lyb * Chunk::CHUNK_SIZE + lxb];

	if (ta) {
		ta->cells[lya * Chunk::CHUNK_SIZE + lxa] = cb;
		ta->extend_next_dirty_rect(lxa, lya, lxa + 1, lya + 1);
		wake(ta, lxa, lya);
	}
	if (tb) {
		tb->cells[lyb * Chunk::CHUNK_SIZE + lxb] = ca;
		tb->extend_next_dirty_rect(lxb, lyb, lxb + 1, lyb + 1);
		wake(tb, lxb, lyb);
	}
}

bool SimContext::is_solid(int x, int y) const {
	const Cell *c = cell_at(x, y);
	if (!c) return true; // out of world bounds = solid (containment)
	if (c->material == static_cast<uint8_t>(air_id)) return false;
	if (c->material == static_cast<uint8_t>(gas_id)) return false;
	if (c->material == static_cast<uint8_t>(lava_id)) return false;
	if (c->material == static_cast<uint8_t>(water_id)) return false;
	return true;
}

void SimContext::wake(Chunk *target, int x, int y) {
	if (!target) return;
	target->set_sleeping(false);
}

void SimContext::pack_velocity(uint8_t &flags, int8_t vx, int8_t vy) {
	uint8_t packed_vx = static_cast<uint8_t>(vx + 8) & 0x0F;
	uint8_t packed_vy = static_cast<uint8_t>(vy + 8) & 0x0F;
	flags = (packed_vx << 4) | packed_vy;
}

void SimContext::unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy) {
	vx = static_cast<int8_t>((flags >> 4) & 0x0F) - 8;
	vy = static_cast<int8_t>(flags & 0x0F) - 8;
}

} // namespace toprogue
