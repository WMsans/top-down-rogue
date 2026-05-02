#include "gas.h"

#include "../../terrain/chunk.h"

#include <algorithm>

namespace toprogue {

static constexpr int V_MAX_OUTFLOW = 8;
static constexpr int DIFFUSION_RATE = 4;
static constexpr int HEAT_DISSIPATION = 2;
static constexpr int THRESHOLD_BECOME_GAS = 1;
static constexpr int THRESHOLD_DISSIPATE = 1;

static int stochastic_div_amount(int numerator, int divisor, int x, int y, uint32_t salt, ChunkView &v) {
	if (divisor <= 0) {
		return 0;
	}
	int base = numerator / divisor;
	int rem = numerator - base * divisor;
	if (rem <= 0) {
		return base;
	}
	uint32_t rng = v.hash3(x, y, salt);
	return base + ((rng % static_cast<uint32_t>(divisor)) < static_cast<uint32_t>(rem) ? 1 : 0);
}

void run_gas(ChunkView &v) {
	Chunk *chunk = v.center;
	if (!chunk) {
		return;
	}

	godot::Rect2i dr = chunk->dirty_rect;
	if (dr.size.x <= 0 || dr.size.y <= 0) {
		return;
	}

	int air_id = static_cast<int>(v.air_id);
	int gas_id = static_cast<int>(v.gas_id);

	int x0 = dr.position.x;
	int y0 = dr.position.y;
	int x1 = x0 + dr.size.x;
	int y1 = y0 + dr.size.y;

	for (int y = y0; y < y1; y++) {
		for (int x = x0; x < x1; x++) {
			Cell *self = v.at(x, y);
			if (!self) {
				continue;
			}
			int material = static_cast<int>(self->material);
			if (material != gas_id && material != air_id) {
				continue;
			}

			Cell n_up_cell, n_down_cell, n_left_cell, n_right_cell;
			Cell *n_up_ptr = v.at(x, y - 1);
			Cell *n_down_ptr = v.at(x, y + 1);
			Cell *n_left_ptr = v.at(x - 1, y);
			Cell *n_right_ptr = v.at(x + 1, y);
			n_up_cell = n_up_ptr ? *n_up_ptr : Cell{ 0, 0, 0, 0 };
			n_down_cell = n_down_ptr ? *n_down_ptr : Cell{ 0, 0, 0, 0 };
			n_left_cell = n_left_ptr ? *n_left_ptr : Cell{ 0, 0, 0, 0 };
			n_right_cell = n_right_ptr ? *n_right_ptr : Cell{ 0, 0, 0, 0 };

			int n_mat_up = static_cast<int>(n_up_cell.material);
			int n_mat_down = static_cast<int>(n_down_cell.material);
			int n_mat_left = static_cast<int>(n_left_cell.material);
			int n_mat_right = static_cast<int>(n_right_cell.material);

			bool any_gas_neighbor =
					n_mat_up == gas_id || n_mat_down == gas_id ||
					n_mat_left == gas_id || n_mat_right == gas_id;

			if (material == air_id && !any_gas_neighbor) {
				int temperature = std::max(0, static_cast<int>(self->temperature) - static_cast<int>(HEAT_DISSIPATION));
				Cell c;
				c.material = static_cast<uint8_t>(air_id);
				c.health = self->health;
				c.temperature = static_cast<uint8_t>(temperature);
				c.flags = 0;
				v.write_changed(x, y, c);
				continue;
			}

			int density = (material == gas_id) ? static_cast<int>(self->health) : 0;
			int8_t vx = 0, vy = 0;
			if (material == gas_id) {
				ChunkView::unpack_velocity(self->flags, vx, vy);
			}

			int comp_up = std::max(0, -static_cast<int>(vy));
			int comp_down = std::max(0, static_cast<int>(vy));
			int comp_left = std::max(0, -static_cast<int>(vx));
			int comp_right = std::max(0, static_cast<int>(vx));

			auto is_solid_gas = [air_id, gas_id](int mat) {
				return mat != air_id && mat != gas_id;
			};

			if (is_solid_gas(n_mat_up)) {
				comp_up = 0;
			}
			if (is_solid_gas(n_mat_down)) {
				comp_down = 0;
			}
			if (is_solid_gas(n_mat_left)) {
				comp_left = 0;
			}
			if (is_solid_gas(n_mat_right)) {
				comp_right = 0;
			}

			int out_up = stochastic_div_amount(density * comp_up, V_MAX_OUTFLOW, x, y, 1u, v);
			int out_down = stochastic_div_amount(density * comp_down, V_MAX_OUTFLOW, x, y, 2u, v);
			int out_left = stochastic_div_amount(density * comp_left, V_MAX_OUTFLOW, x, y, 3u, v);
			int out_right = stochastic_div_amount(density * comp_right, V_MAX_OUTFLOW, x, y, 4u, v);

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

			if (n_mat_up == gas_id) {
				int dN = static_cast<int>(n_up_cell.health);
				int8_t vnx, vny;
				ChunkView::unpack_velocity(n_up_cell.flags, vnx, vny);
				in_up = stochastic_div_amount(dN * std::max(0, static_cast<int>(vny)), V_MAX_OUTFLOW, x, y, 5u, v);
				vin_up_x = static_cast<int>(vnx);
				vin_up_y = static_cast<int>(vny);
			}
			if (n_mat_down == gas_id) {
				int dN = static_cast<int>(n_down_cell.health);
				int8_t vnx, vny;
				ChunkView::unpack_velocity(n_down_cell.flags, vnx, vny);
				in_down = stochastic_div_amount(dN * std::max(0, -static_cast<int>(vny)), V_MAX_OUTFLOW, x, y, 6u, v);
				vin_down_x = static_cast<int>(vnx);
				vin_down_y = static_cast<int>(vny);
			}
			if (n_mat_left == gas_id) {
				int dN = static_cast<int>(n_left_cell.health);
				int8_t vnx, vny;
				ChunkView::unpack_velocity(n_left_cell.flags, vnx, vny);
				in_left = stochastic_div_amount(dN * std::max(0, static_cast<int>(vnx)), V_MAX_OUTFLOW, x, y, 7u, v);
				vin_left_x = static_cast<int>(vnx);
				vin_left_y = static_cast<int>(vny);
			}
			if (n_mat_right == gas_id) {
				int dN = static_cast<int>(n_right_cell.health);
				int8_t vnx, vny;
				ChunkView::unpack_velocity(n_right_cell.flags, vnx, vny);
				in_right = stochastic_div_amount(dN * std::max(0, -static_cast<int>(vnx)), V_MAX_OUTFLOW, x, y, 8u, v);
				vin_right_x = static_cast<int>(vnx);
				vin_right_y = static_cast<int>(vny);
			}

			int total_in = in_up + in_down + in_left + in_right;

			if (is_solid_gas(n_mat_up) && vy < 0) {
				vy = -vy;
			}
			if (is_solid_gas(n_mat_down) && vy > 0) {
				vy = -vy;
			}
			if (is_solid_gas(n_mat_left) && vx < 0) {
				vx = -vx;
			}
			if (is_solid_gas(n_mat_right) && vx > 0) {
				vx = -vx;
			}

			int diff_out = 0;
			if (density > 0) {
				int dens_up = (n_mat_up == gas_id) ? static_cast<int>(n_up_cell.health) : 0;
				int dens_down = (n_mat_down == gas_id) ? static_cast<int>(n_down_cell.health) : 0;
				int dens_left = (n_mat_left == gas_id) ? static_cast<int>(n_left_cell.health) : 0;
				int dens_right = (n_mat_right == gas_id) ? static_cast<int>(n_right_cell.health) : 0;

				if (!is_solid_gas(n_mat_up) && dens_up < density) {
					diff_out += (density - dens_up) / static_cast<int>(DIFFUSION_RATE);
				}
				if (!is_solid_gas(n_mat_down) && dens_down < density) {
					diff_out += (density - dens_down) / static_cast<int>(DIFFUSION_RATE);
				}
				if (!is_solid_gas(n_mat_left) && dens_left < density) {
					diff_out += (density - dens_left) / static_cast<int>(DIFFUSION_RATE);
				}
				if (!is_solid_gas(n_mat_right) && dens_right < density) {
					diff_out += (density - dens_right) / static_cast<int>(DIFFUSION_RATE);
				}
			}

			int diff_in = 0;
			if (n_mat_up == gas_id && static_cast<int>(n_up_cell.health) > density && !is_solid_gas(material)) {
				diff_in += (static_cast<int>(n_up_cell.health) - density) / static_cast<int>(DIFFUSION_RATE);
			}
			if (n_mat_down == gas_id && static_cast<int>(n_down_cell.health) > density && !is_solid_gas(material)) {
				diff_in += (static_cast<int>(n_down_cell.health) - density) / static_cast<int>(DIFFUSION_RATE);
			}
			if (n_mat_left == gas_id && static_cast<int>(n_left_cell.health) > density && !is_solid_gas(material)) {
				diff_in += (static_cast<int>(n_left_cell.health) - density) / static_cast<int>(DIFFUSION_RATE);
			}
			if (n_mat_right == gas_id && static_cast<int>(n_right_cell.health) > density && !is_solid_gas(material)) {
				diff_in += (static_cast<int>(n_right_cell.health) - density) / static_cast<int>(DIFFUSION_RATE);
			}

			int new_density = density - total_out + total_in - diff_out + diff_in;
			new_density = std::clamp(new_density, 0, 255);

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

			if (material == air_id) {
				int air_total_in = total_in + diff_in;
				if (air_total_in >= THRESHOLD_BECOME_GAS) {
					int w = std::max(1, total_in + diff_in);
					int inflow_vel_x = (vin_up_x * in_up + vin_down_x * in_down + vin_left_x * in_left + vin_right_x * in_right);
					int inflow_vel_y = (vin_up_y * in_up + vin_down_y * in_down + vin_left_y * in_left + vin_right_y * in_right);
					if (w > 0) {
						inflow_vel_x /= w;
						inflow_vel_y /= w;
					}
					inflow_vel_x = (inflow_vel_x * 15) / 16;
					inflow_vel_y = (inflow_vel_y * 15) / 16;
					inflow_vel_x = std::clamp(inflow_vel_x, -8, 7);
					inflow_vel_y = std::clamp(inflow_vel_y, -8, 7);
					Cell c;
					c.material = static_cast<uint8_t>(gas_id);
					c.health = static_cast<uint8_t>(std::clamp(air_total_in, 0, 255));
					c.temperature = 0;
					ChunkView::pack_velocity(c.flags, static_cast<int8_t>(inflow_vel_x), static_cast<int8_t>(inflow_vel_y));
					*v.at(x, y) = c;
					chunk->extend_next_dirty_rect(x, y, x + 1, y + 1);
					chunk->set_sleeping(false);
					continue;
				}
				int temperature = std::max(0, static_cast<int>(self->temperature) - static_cast<int>(HEAT_DISSIPATION));
				Cell c;
				c.material = static_cast<uint8_t>(air_id);
				c.health = self->health;
				c.temperature = static_cast<uint8_t>(temperature);
				c.flags = 0;
				v.write_changed(x, y, c);
				continue;
			}

			if (new_density < THRESHOLD_DISSIPATE) {
				Cell c;
				c.material = static_cast<uint8_t>(air_id);
				c.health = 0;
				c.temperature = 0;
				c.flags = 0;
				v.write_changed(x, y, c);
				continue;
			}

			Cell c;
			c.material = static_cast<uint8_t>(gas_id);
			c.health = static_cast<uint8_t>(std::clamp(new_density, 0, 255));
			c.temperature = 0;
			ChunkView::pack_velocity(c.flags, static_cast<int8_t>(new_vel_x), static_cast<int8_t>(new_vel_y));
			*v.at(x, y) = c;
			chunk->extend_next_dirty_rect(x, y, x + 1, y + 1);
			chunk->set_sleeping(false);
		}
	}
}

} // namespace toprogue
