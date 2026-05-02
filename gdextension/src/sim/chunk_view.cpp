#include "chunk_view.h"

namespace toprogue {

Cell *ChunkView::at(int x, int y) {
	if (x >= 0 && x < SZ && y >= 0 && y < SZ)
		return &cells[y * SZ + x];
	return at_border(x, y);
}

Cell *ChunkView::at_border(int x, int y) {
	if (y < 0) { return up ? &cells_up[(SZ + y) * SZ + x] : nullptr; }
	if (y >= SZ) { return down ? &cells_down[(y - SZ) * SZ + x] : nullptr; }
	if (x < 0) { return left ? &cells_left[y * SZ + (SZ + x)] : nullptr; }
	return right ? &cells_right[y * SZ + (x - SZ)] : nullptr;
}

uint32_t ChunkView::hash_u32(uint32_t n) {
	n = (n >> 16) ^ n; n *= 0xed5ad0bb;
	n = (n >> 16) ^ n; n *= 0xac4c1b51;
	n = (n >> 16) ^ n; return n;
}

uint32_t ChunkView::hash3(int x, int y, uint32_t salt) const {
	return hash_u32(static_cast<uint32_t>(x) ^
			hash_u32(static_cast<uint32_t>(y) ^ frame_seed ^ salt));
}

bool ChunkView::stochastic_div(int x, int y, uint32_t salt, int divisor) const {
	if (divisor <= 0) return false;
	return (hash3(x, y, salt) % static_cast<uint32_t>(divisor)) == 0;
}

void ChunkView::pack_velocity(uint8_t &flags, int8_t vx, int8_t vy) {
	uint8_t pvx = static_cast<uint8_t>(vx + 8) & 0x0F;
	uint8_t pvy = static_cast<uint8_t>(vy + 8) & 0x0F;
	flags = static_cast<uint8_t>((pvx << 4) | pvy);
}

void ChunkView::unpack_velocity(uint8_t flags, int8_t &vx, int8_t &vy) {
	vx = static_cast<int8_t>((flags >> 4) & 0x0F) - 8;
	vy = static_cast<int8_t>(flags & 0x0F) - 8;
}

bool ChunkView::write_changed(int x, int y, const Cell &nv) {
	auto try_write = [&](Chunk *target, Cell *cells_arr, int lx, int ly) -> bool {
		if (!target) return false;
		int i = ly * SZ + lx;
		Cell &slot = cells_arr[i];
		if (slot.material == nv.material && slot.health == nv.health &&
				slot.temperature == nv.temperature && slot.flags == nv.flags) return false;
		slot = nv;
		target->extend_next_dirty_rect(lx, ly, lx + 1, ly + 1);
		return true;
	};
	if (x >= 0 && x < SZ && y >= 0 && y < SZ)
		return try_write(center, cells, x, y);
	if (y < 0)    return try_write(up,    cells_up,    x, SZ + y);
	if (y >= SZ)  return try_write(down,  cells_down,  x, y - SZ);
	if (x < 0)    return try_write(left,  cells_left,  SZ + x, y);
	return         try_write(right, cells_right, x - SZ, y);
}

} // namespace toprogue
