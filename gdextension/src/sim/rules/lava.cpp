#include "lava.h"

#include "../../sim/material_table.h"
#include "../../terrain/chunk.h"

#include <algorithm>

namespace toprogue {

static constexpr int V_MAX_OUTFLOW = 8;
static constexpr int THRESHOLD_BECOME_LAVA = 1;
static constexpr int THRESHOLD_DISSIPATE = 1;

static int stochastic_div_amount(int numerator, int divisor, int x, int y, uint32_t salt, SimContext &ctx) {
	if (divisor <= 0) return 0;
	int base = numerator / divisor;
	int rem = numerator - base * divisor;
	if (rem <= 0) return base;
	uint32_t rng = ctx.hash3(x, y, salt);
	return base + ((rng % static_cast<uint32_t>(divisor)) < static_cast<uint32_t>(rem) ? 1 : 0);
}

static bool is_solid_for_lava(int mat, int air_id) {
	return mat != air_id && mat != -1; // lava itself is not solid for lava
	// Actually: mat != MAT_AIR && mat != MAT_LAVA
	// But we don't have lava_id here directly, so we need it from the caller
}

static bool is_hot_lava(Cell c, int target_material, int lava_id) {
	if (static_cast<int>(c.material) != lava_id) return false;
	int temp = static_cast<int>(c.temperature);
	return temp > MaterialTable::get_singleton()->get_ignition_temp(target_material);
}

void run_lava(SimContext &ctx) {
	Chunk *chunk = ctx.chunk;
	if (!chunk) return;

	godot::Rect2i dr = chunk->dirty_rect;
	if (dr.size.x <= 0 || dr.size.y <= 0) return;

	int air_id = static_cast<int>(ctx.air_id);
	int lava_id = static_cast<int>(ctx.lava_id);

	int x0 = dr.position.x;
	int y0 = dr.position.y;
	int x1 = x0 + dr.size.x;
	int y1 = y0 + dr.size.y;

	for (int y = y0; y < y1; y++) {
		for (int x = x0; x < x1; x++) {
			const Cell *self = ctx.cell_at(x, y);
			if (!self) continue;
			int material = static_cast<int>(self->material);
			if (material != lava_id && material != air_id) continue;

			Cell n_up_cell, n_down_cell, n_left_cell, n_right_cell;
			const Cell *n_up_ptr = ctx.cell_at(x, y - 1);
			const Cell *n_down_ptr = ctx.cell_at(x, y + 1);
			const Cell *n_left_ptr = ctx.cell_at(x - 1, y);
			const Cell *n_right_ptr = ctx.cell_at(x + 1, y);
			n_up_cell = n_up_ptr ? *n_up_ptr : Cell{0, 0, 0, 0};
			n_down_cell = n_down_ptr ? *n_down_ptr : Cell{0, 0, 0, 0};
			n_left_cell = n_left_ptr ? *n_left_ptr : Cell{0, 0, 0, 0};
			n_right_cell = n_right_ptr ? *n_right_ptr : Cell{0, 0, 0, 0};

			int n_mat_up = static_cast<int>(n_up_cell.material);
			int n_mat_down = static_cast<int>(n_down_cell.material);
			int n_mat_left = static_cast<int>(n_left_cell.material);
			int n_mat_right = static_cast<int>(n_right_cell.material);

			bool any_lava_neighbor =
				n_mat_up == lava_id || n_mat_down == lava_id ||
				n_mat_left == lava_id || n_mat_right == lava_id;

			if (material == air_id && !any_lava_neighbor) {
				continue;
			}

			int density = (material == lava_id) ? static_cast<int>(self->health) : 0;
			int temperature = (material == lava_id) ? static_cast<int>(self->temperature) : 0;
			int8_t vx = 0, vy = 0;
			if (material == lava_id) {
				ctx.unpack_velocity(self->flags, vx, vy);
			}

			int comp_up = std::max(0, -static_cast<int>(vy));
			int comp_down = std::max(0, static_cast<int>(vy));
			int comp_left = std::max(0, -static_cast<int>(vx));
			int comp_right = std::max(0, static_cast<int>(vx));

			auto is_solid_lava = [air_id, lava_id](int mat) {
				return mat != air_id && mat != lava_id;
			};

			if (is_solid_lava(n_mat_up)) comp_up = 0;
			if (is_solid_lava(n_mat_down)) comp_down = 0;
			if (is_solid_lava(n_mat_left)) comp_left = 0;
			if (is_solid_lava(n_mat_right)) comp_right = 0;

			int out_up = stochastic_div_amount(density * comp_up, V_MAX_OUTFLOW, x, y, 1u, ctx);
			int out_down = stochastic_div_amount(density * comp_down, V_MAX_OUTFLOW, x, y, 2u, ctx);
			int out_left = stochastic_div_amount(density * comp_left, V_MAX_OUTFLOW, x, y, 3u, ctx);
			int out_right = stochastic_div_amount(density * comp_right, V_MAX_OUTFLOW, x, y, 4u, ctx);

			int total_out = out_up + out_down + out_left + out_right;
			int max_outflow = std::min(density, std::max(1, density / 2));
			if (total_out > max_outflow) {
				out_up = out_up * max_outflow / std::max(1, total_out);
				out_down = out_down * max_outflow / std::max(1, total_out);
				out_left = out_left * max_outflow / std::max(1, total_out);
				out_right = out_right * max_outflow / std::max(1, total_out);
				total_out = out_up + out_down + out_left + out_right;
			}

			int in_up = 0, in_down = 0, in_left = 0, in_right = 0;
			int vin_up_x = 0, vin_up_y = 0;
			int vin_down_x = 0, vin_down_y = 0;
			int vin_left_x = 0, vin_left_y = 0;
			int vin_right_x = 0, vin_right_y = 0;

			if (n_mat_up == lava_id) {
				int dN = static_cast<int>(n_up_cell.health);
				int8_t vnx, vny;
				ctx.unpack_velocity(n_up_cell.flags, vnx, vny);
				in_up = stochastic_div_amount(dN * std::max(0, static_cast<int>(vny)), V_MAX_OUTFLOW, x, y, 5u, ctx);
				vin_up_x = static_cast<int>(vnx);
				vin_up_y = static_cast<int>(vny);
			}
			if (n_mat_down == lava_id) {
				int dN = static_cast<int>(n_down_cell.health);
				int8_t vnx, vny;
				ctx.unpack_velocity(n_down_cell.flags, vnx, vny);
				in_down = stochastic_div_amount(dN * std::max(0, -static_cast<int>(vny)), V_MAX_OUTFLOW, x, y, 6u, ctx);
				vin_down_x = static_cast<int>(vnx);
				vin_down_y = static_cast<int>(vny);
			}
			if (n_mat_left == lava_id) {
				int dN = static_cast<int>(n_left_cell.health);
				int8_t vnx, vny;
				ctx.unpack_velocity(n_left_cell.flags, vnx, vny);
				in_left = stochastic_div_amount(dN * std::max(0, static_cast<int>(vnx)), V_MAX_OUTFLOW, x, y, 7u, ctx);
				vin_left_x = static_cast<int>(vnx);
				vin_left_y = static_cast<int>(vny);
			}
			if (n_mat_right == lava_id) {
				int dN = static_cast<int>(n_right_cell.health);
				int8_t vnx, vny;
				ctx.unpack_velocity(n_right_cell.flags, vnx, vny);
				in_right = stochastic_div_amount(dN * std::max(0, -static_cast<int>(vnx)), V_MAX_OUTFLOW, x, y, 8u, ctx);
				vin_right_x = static_cast<int>(vnx);
				vin_right_y = static_cast<int>(vny);
			}

			int total_in = in_up + in_down + in_left + in_right;

			if (is_solid_lava(n_mat_up) && vy < 0) vy = -vy;
			if (is_solid_lava(n_mat_down) && vy > 0) vy = -vy;
			if (is_solid_lava(n_mat_left) && vx < 0) vx = -vx;
			if (is_solid_lava(n_mat_right) && vx > 0) vx = -vx;

			int new_density = std::clamp(density - total_out + total_in, 0, 255);

			int stayed = std::max(0, density - total_out);
			int weight = std::max(1, stayed + total_in);
			int vsum_x = static_cast<int>(vx) * stayed +
			             vin_up_x * in_up + vin_down_x * in_down +
			             vin_left_x * in_left + vin_right_x * in_right;
			int vsum_y = static_cast<int>(vy) * stayed +
			             vin_up_y * in_up + vin_down_y * in_down +
			             vin_left_y * in_left + vin_right_y * in_right;
			int new_vel_x = vsum_x / weight;
			int new_vel_y = vsum_y / weight;
			int new_vel_mag = std::max(std::abs(new_vel_x), std::abs(new_vel_y));
			if (new_vel_mag > 1) {
				new_vel_x = (new_vel_x * 15) / 16;
				new_vel_y = (new_vel_y * 15) / 16;
			}
			new_vel_x = std::clamp(new_vel_x, -8, 7);
			new_vel_y = std::clamp(new_vel_y, -8, 7);

			int temp_weight = stayed * temperature;
			if (n_mat_up == lava_id) temp_weight += static_cast<int>(n_up_cell.temperature) * in_up;
			if (n_mat_down == lava_id) temp_weight += static_cast<int>(n_down_cell.temperature) * in_down;
			if (n_mat_left == lava_id) temp_weight += static_cast<int>(n_left_cell.temperature) * in_left;
			if (n_mat_right == lava_id) temp_weight += static_cast<int>(n_right_cell.temperature) * in_right;
			int new_temp = temp_weight / std::max(1, stayed + total_in);

			if (material == air_id) {
				if (total_in >= THRESHOLD_BECOME_LAVA) {
					int inflow_vel_x = 0, inflow_vel_y = 0;
					if (total_in > 0) {
						inflow_vel_x = (vin_up_x * in_up + vin_down_x * in_down + vin_left_x * in_left + vin_right_x * in_right) / total_in;
						inflow_vel_y = (vin_up_y * in_up + vin_down_y * in_down + vin_left_y * in_left + vin_right_y * in_right) / total_in;
						inflow_vel_x = (inflow_vel_x * 15) / 16;
						inflow_vel_y = (inflow_vel_y * 15) / 16;
						inflow_vel_x = std::clamp(inflow_vel_x, -8, 7);
						inflow_vel_y = std::clamp(inflow_vel_y, -8, 7);
					}
					Cell c;
					c.material = static_cast<uint8_t>(lava_id);
					c.health = static_cast<uint8_t>(std::clamp(total_in, 0, 255));
					c.temperature = static_cast<uint8_t>(std::clamp(new_temp, 0, 255));
					ctx.pack_velocity(c.flags, static_cast<int8_t>(inflow_vel_x), static_cast<int8_t>(inflow_vel_y));
					ctx.write_cell(x, y, c);
				}
				continue;
			}

			if (new_density < THRESHOLD_DISSIPATE) {
				Cell c;
				c.material = static_cast<uint8_t>(air_id);
				c.health = 0;
				c.temperature = 0;
				c.flags = 0;
				ctx.write_cell(x, y, c);
				continue;
			}

			Cell c;
			c.material = static_cast<uint8_t>(lava_id);
			c.health = static_cast<uint8_t>(std::clamp(new_density, 0, 255));
			c.temperature = static_cast<uint8_t>(std::clamp(new_temp, 0, 255));
			ctx.pack_velocity(c.flags, static_cast<int8_t>(new_vel_x), static_cast<int8_t>(new_vel_y));
			ctx.write_cell(x, y, c);
		}
	}
}

} // namespace toprogue
