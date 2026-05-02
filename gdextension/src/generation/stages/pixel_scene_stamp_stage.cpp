#include "../../resources/room_template.h"
#include "../../resources/template_pack.h"
#include "../../terrain/chunk.h"
#include "../stage_context.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/color.hpp>

#include <algorithm>
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

inline void rotate_local(float lx, float ly, int rot, float size, float &ox, float &oy) {
	if (rot == 0) {
		ox = lx;
		oy = ly;
		return;
	}
	if (rot == 1) {
		ox = ly;
		oy = size - 1.0f - lx;
		return;
	}
	if (rot == 2) {
		ox = size - 1.0f - lx;
		oy = size - 1.0f - ly;
		return;
	}
	ox = size - 1.0f - ly;
	oy = lx;
}

} //namespace

void stage_pixel_scene_stamp(Chunk *chunk, const StageContext &ctx) {
	if (ctx.stamp_bytes.size() < 16) {
		return;
	}
	int n = stamp_count(ctx.stamp_bytes);
	if (n <= 0) {
		return;
	}

	int bg_mat = ctx.biome.is_valid() ? ctx.biome->background_material : ctx.stone_id;

	TemplatePack *tp = TemplatePack::get_singleton();
	if (tp == nullptr) {
		return;
	}

	for (int s = 0; s < n; s++) {
		Stamp st = stamp_at(ctx.stamp_bytes, s);
		int meta = static_cast<int>(std::round(st.meta_f));
		int size_class = meta & 0xFF;
		int rot_steps = (meta >> 8) & 0xFF;
		if (size_class <= 0) {
			continue;
		}

		int tidx = static_cast<int>(std::round(st.idx));
		Ref<Image> img = tp->get_image(size_class, tidx);
		if (img.is_null()) {
			continue;
		}

		float half = static_cast<float>(size_class) * 0.5f;
		float chunk_origin_x = static_cast<float>(ctx.chunk_coord.x * Chunk::CHUNK_SIZE);
		float chunk_origin_y = static_cast<float>(ctx.chunk_coord.y * Chunk::CHUNK_SIZE);

		int x_min = std::max(0, static_cast<int>(std::floor(st.cx - half - chunk_origin_x)));
		int x_max = std::min(Chunk::CHUNK_SIZE - 1,
				static_cast<int>(std::ceil(st.cx + half - chunk_origin_x)) - 1);
		int y_min = std::max(0, static_cast<int>(std::floor(st.cy - half - chunk_origin_y)));
		int y_max = std::min(Chunk::CHUNK_SIZE - 1,
				static_cast<int>(std::ceil(st.cy + half - chunk_origin_y)) - 1);
		if (x_min > x_max || y_min > y_max) {
			continue;
		}

		for (int y = y_min; y <= y_max; y++) {
			for (int x = x_min; x <= x_max; x++) {
				float wx = chunk_origin_x + x;
				float wy = chunk_origin_y + y;
				float dx = wx - st.cx;
				float dy = wy - st.cy;
				if (std::fabs(dx) >= half || std::fabs(dy) >= half) {
					continue;
				}

				float lx = dx + half;
				float ly = dy + half;
				float sx, sy;
				rotate_local(lx, ly, rot_steps, static_cast<float>(size_class), sx, sy);

				int ix = std::clamp(static_cast<int>(sx), 0, size_class - 1);
				int iy = std::clamp(static_cast<int>(sy), 0, size_class - 1);
				Color px = img->get_pixel(ix, iy);
				if (px.a < 0.5f) {
					continue;
				}

				int r = static_cast<int>(std::round(px.r * 255.0f));
				int mat = (r == 255) ? bg_mat : r;
				chunk->set_cell_material(y * Chunk::CHUNK_SIZE + x, static_cast<uint8_t>(mat));
			}
		}
	}
}

} // namespace toprogue
