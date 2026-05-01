#include "../../resources/biome_def.h"
#include "../../terrain/chunk.h"
#include "../stage_context.h"

#include <godot_cpp/variant/packed_byte_array.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {

namespace {

struct Stamp {
	float cx, cy, idx, meta_f;
};

inline int stamp_count(const PackedByteArray &b) {
	return static_cast<int>(b.decode_s32(0));
}

inline Stamp stamp_at(const PackedByteArray &b, int i) {
	int off = 16 + i * 16;
	return Stamp{ static_cast<float>(b.decode_float(off + 0)),
		static_cast<float>(b.decode_float(off + 4)),
		static_cast<float>(b.decode_float(off + 8)),
		static_cast<float>(b.decode_float(off + 12)) };
}

} //namespace

void stage_secret_ring(Chunk *chunk, const StageContext &ctx) {
	if (ctx.stamp_bytes.size() < 16) {
		return;
	}
	int n = stamp_count(ctx.stamp_bytes);
	if (n <= 0) {
		return;
	}
	Ref<BiomeDef> b = ctx.biome;
	if (b.is_null()) {
		return;
	}
	int bg_mat = b->background_material;
	int thickness = b->secret_ring_thickness;

	for (int s = 0; s < n; s++) {
		Stamp st = stamp_at(ctx.stamp_bytes, s);
		int meta = static_cast<int>(std::round(st.meta_f));
		int flags = (meta >> 16) & 0xFF;
		if ((flags & 1) == 0) {
			continue;
		}
		int size_class = meta & 0xFF;

		float inner = static_cast<float>(size_class) * 0.45f;
		float outer = inner + static_cast<float>(thickness);

		float chunk_origin_x = static_cast<float>(ctx.chunk_coord.x * Chunk::CHUNK_SIZE);
		float chunk_origin_y = static_cast<float>(ctx.chunk_coord.y * Chunk::CHUNK_SIZE);
		int x_min = std::max(0, static_cast<int>(std::floor(st.cx - outer - chunk_origin_x)));
		int x_max = std::min(Chunk::CHUNK_SIZE - 1,
				static_cast<int>(std::ceil(st.cx + outer - chunk_origin_x)) - 1);
		int y_min = std::max(0, static_cast<int>(std::floor(st.cy - outer - chunk_origin_y)));
		int y_max = std::min(Chunk::CHUNK_SIZE - 1,
				static_cast<int>(std::ceil(st.cy + outer - chunk_origin_y)) - 1);
		if (x_min > x_max || y_min > y_max) {
			continue;
		}

		for (int y = y_min; y <= y_max; y++) {
			for (int x = x_min; x <= x_max; x++) {
				float wx = chunk_origin_x + x;
				float wy = chunk_origin_y + y;
				float dx = wx - st.cx;
				float dy = wy - st.cy;
				float d = std::sqrt(dx * dx + dy * dy);
				if (d >= inner && d < outer) {
					chunk->cells[y * Chunk::CHUNK_SIZE + x].material = static_cast<uint8_t>(bg_mat);
				}
			}
		}
	}
}

} // namespace toprogue
