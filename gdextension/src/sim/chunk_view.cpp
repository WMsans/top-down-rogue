#include "chunk_view.h"

namespace toprogue {

Cell ChunkView::read(int x, int y) {
	if (x >= 0 && x < SZ && y >= 0 && y < SZ) {
		int i = y * SZ + x;
		return Cell{ mat[i], health[i], temperature[i], flags[i] };
	}
	if (y < 0 && up) {
		int i = (SZ + y) * SZ + x;
		return Cell{ mat_up[i], health_up[i], temperature_up[i], flags_up[i] };
	}
	if (y >= SZ && down) {
		int i = (y - SZ) * SZ + x;
		return Cell{ mat_down[i], health_down[i], temperature_down[i], flags_down[i] };
	}
	if (x < 0 && left) {
		int i = y * SZ + (SZ + x);
		return Cell{ mat_left[i], health_left[i], temperature_left[i], flags_left[i] };
	}
	if (x >= SZ && right) {
		int i = y * SZ + (x - SZ);
		return Cell{ mat_right[i], health_right[i], temperature_right[i], flags_right[i] };
	}
	return Cell{ 0, 0, 0, 0 };
}

bool ChunkView::write_changed(int x, int y, const Cell &nv) {
	auto try_write = [&](Chunk *target, uint8_t *m, uint8_t *hh,
			uint8_t *tt, uint8_t *ff, int lx, int ly) -> bool {
		if (!target) return false;
		int i = ly * SZ + lx;
		if (m[i] == nv.material && hh[i] == nv.health &&
				tt[i] == nv.temperature && ff[i] == nv.flags) return false;
		m[i] = nv.material; hh[i] = nv.health;
		tt[i] = nv.temperature; ff[i] = nv.flags;
		target->extend_next_dirty_rect(lx, ly, lx + 1, ly + 1);
		if (target != center)
			target->wake_pending.store(true, std::memory_order_relaxed);
		return true;
	};
	if (x >= 0 && x < SZ && y >= 0 && y < SZ)
		return try_write(center, mat, health, temperature, flags, x, y);
	if (y < 0)    return try_write(up,    mat_up,    health_up,    temperature_up,    flags_up,    x, SZ + y);
	if (y >= SZ)  return try_write(down,  mat_down,  health_down,  temperature_down,  flags_down,  x, y - SZ);
	if (x < 0)    return try_write(left,  mat_left,  health_left,  temperature_left,  flags_left,  SZ + x, y);
	return         try_write(right, mat_right, health_right, temperature_right, flags_right, x - SZ, y);
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

} // namespace toprogue
