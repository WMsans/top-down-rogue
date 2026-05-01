#include "injection.h"

#include "../../terrain/chunk.h"

#include <godot_cpp/templates/vector.hpp>

#include <algorithm>

namespace toprogue {

static constexpr int MAX_INJECTIONS_PER_CHUNK = 32;

void run_injection(SimContext &ctx) {
	Chunk *chunk = ctx.chunk;
	if (!chunk) {
		return;
	}

	godot::Rect2i dr = chunk->dirty_rect;
	if (dr.size.x <= 0 || dr.size.y <= 0) {
		return;
	}

	godot::Vector<InjectionAABB> injections = chunk->take_injections();
	int n = injections.size();
	if (n <= 0) {
		return;
	}
	if (n > MAX_INJECTIONS_PER_CHUNK) {
		n = MAX_INJECTIONS_PER_CHUNK;
	}

	int air_id = static_cast<int>(ctx.air_id);
	int gas_id = static_cast<int>(ctx.gas_id);
	int lava_id = static_cast<int>(ctx.lava_id);

	int x0 = dr.position.x;
	int y0 = dr.position.y;
	int x1 = x0 + dr.size.x;
	int y1 = y0 + dr.size.y;

	for (int y = y0; y < y1; y++) {
		for (int x = x0; x < x1; x++) {
			Cell *cptr = ctx.cell_at(x, y);
			if (!cptr) {
				continue;
			}

			int material = static_cast<int>(cptr->material);
			if (material != gas_id && material != lava_id) {
				continue;
			}

			bool wrote = false;
			Cell c = *cptr;

			for (int i = 0; i < n; i++) {
				const InjectionAABB &b = injections[i];

				if (material == gas_id && !(b.target_kind & 1)) {
					continue;
				}
				if (material == lava_id && !(b.target_kind & 2)) {
					continue;
				}

				if (x < b.min_x || x >= b.max_x) {
					continue;
				}
				if (y < b.min_y || y >= b.max_y) {
					continue;
				}

				if (material == gas_id) {
					int8_t vx, vy;
					ctx.unpack_velocity(c.flags, vx, vy);

					int center_x = (b.min_x + b.max_x) / 2;
					int center_y = (b.min_y + b.max_y) / 2;
					int diff_x = x - center_x;
					int diff_y = y - center_y;

					int push_x = 0, push_y = 0;
					if (diff_x == 0 && diff_y == 0) {
						push_x = static_cast<int>(b.vel_x);
						push_y = static_cast<int>(b.vel_y);
					} else {
						int dist_x = std::abs(diff_x);
						int dist_y = std::abs(diff_y);
						if (dist_x >= dist_y) {
							push_x = (diff_x >= 0) ? 7 : -7;
						} else {
							push_y = (diff_y >= 0) ? 7 : -7;
						}
					}

					int new_vx = std::clamp(static_cast<int>(vx) + push_x, -8, 7);
					int new_vy = std::clamp(static_cast<int>(vy) + push_y, -8, 7);

					int dens = static_cast<int>(c.health);

					bool in_front = (b.vel_x > 0 && diff_x > 0) || (b.vel_x < 0 && diff_x < 0) ||
							(b.vel_y > 0 && diff_y > 0) || (b.vel_y < 0 && diff_y < 0);
					if (in_front && (b.vel_x != 0 || b.vel_y != 0)) {
						dens = dens * 3 / 4;
					}

					c.material = static_cast<uint8_t>(gas_id);
					c.health = static_cast<uint8_t>(std::clamp(dens, 0, 255));
					c.temperature = 0;
					ctx.pack_velocity(c.flags, static_cast<int8_t>(new_vx), static_cast<int8_t>(new_vy));
				} else {
					int8_t vx, vy;
					ctx.unpack_velocity(c.flags, vx, vy);

					int center_x = (b.min_x + b.max_x) / 2;
					int center_y = (b.min_y + b.max_y) / 2;
					int diff_x = x - center_x;
					int diff_y = y - center_y;

					int dist_x = std::abs(diff_x);
					int dist_y = std::abs(diff_y);
					int push_x = 0, push_y = 0;
					if (dist_x >= dist_y) {
						push_x = (diff_x >= 0) ? 7 : -7;
					} else {
						push_y = (diff_y >= 0) ? 7 : -7;
					}

					int new_vx = std::clamp(static_cast<int>(vx) + push_x, -8, 7);
					int new_vy = std::clamp(static_cast<int>(vy) + push_y, -8, 7);

					int dens = static_cast<int>(c.health);
					int temp = static_cast<int>(c.temperature);

					bool in_front = (b.vel_x > 0 && diff_x > 0) || (b.vel_x < 0 && diff_x < 0) ||
							(b.vel_y > 0 && diff_y > 0) || (b.vel_y < 0 && diff_y < 0);
					if (in_front && (b.vel_x != 0 || b.vel_y != 0)) {
						dens = dens * 3 / 4;
					}

					c.material = static_cast<uint8_t>(lava_id);
					c.health = static_cast<uint8_t>(std::clamp(dens, 0, 255));
					c.temperature = static_cast<uint8_t>(std::clamp(temp, 0, 255));
					ctx.pack_velocity(c.flags, static_cast<int8_t>(new_vx), static_cast<int8_t>(new_vy));
				}
				wrote = true;
			}

			if (wrote) {
				ctx.write_cell(x, y, c);
			}
		}
	}
}

} // namespace toprogue
