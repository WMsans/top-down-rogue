#include "burning.h"

#include "../../sim/material_table.h"
#include "../../terrain/chunk.h"

#include <algorithm>

namespace toprogue {

static constexpr int HEAT_SPREAD = 10;
static constexpr int HEAT_DISSIPATION = 2;
static constexpr float SPREAD_PROB_MAX = 0.7f;
static constexpr int FIRE_TEMP = 255;

static bool is_burning_cell(Cell c, MaterialTable *mt) {
	int mat = static_cast<int>(c.material);
	if (!mt->is_flammable(mat)) {
		return false;
	}
	return static_cast<int>(c.temperature) > mt->get_ignition_temp(mat);
}

static bool is_hot_lava_for_mat(Cell c, int target_material, int lava_id, MaterialTable *mt) {
	if (static_cast<int>(c.material) != lava_id) {
		return false;
	}
	int temp = static_cast<int>(c.temperature);
	return temp > mt->get_ignition_temp(target_material);
}

void run_burning(ChunkView &v) {
	Chunk *chunk = v.center;
	if (!chunk) {
		return;
	}

	godot::Rect2i dr = chunk->dirty_rect;
	if (dr.size.x <= 0 || dr.size.y <= 0) {
		return;
	}

	MaterialTable *mt = MaterialTable::get_singleton();
	if (!mt) {
		return;
	}

	int air_id = static_cast<int>(v.air_id);
	int lava_id = static_cast<int>(v.lava_id);

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

			Cell c = *self;
			int material = static_cast<int>(c.material);
			int health = static_cast<int>(c.health);
			int temperature = static_cast<int>(c.temperature);

			uint32_t base_rng = ChunkView::hash_u32(
					static_cast<uint32_t>(x) ^ ChunkView::hash_u32(static_cast<uint32_t>(y) ^ v.frame_seed));

			int heat_gain = 0;

			Cell *n_up_ptr = v.at(x, y - 1);
			Cell *n_down_ptr = v.at(x, y + 1);
			Cell *n_left_ptr = v.at(x - 1, y);
			Cell *n_right_ptr = v.at(x + 1, y);

			Cell n_up = n_up_ptr ? *n_up_ptr : Cell{ 0, 0, 0, 0 };
			Cell n_down = n_down_ptr ? *n_down_ptr : Cell{ 0, 0, 0, 0 };
			Cell n_left = n_left_ptr ? *n_left_ptr : Cell{ 0, 0, 0, 0 };
			Cell n_right = n_right_ptr ? *n_right_ptr : Cell{ 0, 0, 0, 0 };

			if (is_burning_cell(n_up, mt)) {
				int n_mat = static_cast<int>(n_up.material);
				int n_temp = static_cast<int>(n_up.temperature);
				float prob = static_cast<float>(n_temp - mt->get_ignition_temp(n_mat)) /
						static_cast<float>(FIRE_TEMP - mt->get_ignition_temp(n_mat)) * SPREAD_PROB_MAX;
				uint32_t rng = ChunkView::hash_u32(base_rng ^ 1u);
				if ((rng % 100u) < static_cast<uint32_t>(prob * 100.0f)) {
					heat_gain += static_cast<int>(HEAT_SPREAD) / 2 + static_cast<int>(rng % static_cast<uint32_t>(HEAT_SPREAD));
				}
			}
			if (is_burning_cell(n_down, mt)) {
				int n_mat = static_cast<int>(n_down.material);
				int n_temp = static_cast<int>(n_down.temperature);
				float prob = static_cast<float>(n_temp - mt->get_ignition_temp(n_mat)) /
						static_cast<float>(FIRE_TEMP - mt->get_ignition_temp(n_mat)) * SPREAD_PROB_MAX;
				uint32_t rng = ChunkView::hash_u32(base_rng ^ 2u);
				if ((rng % 100u) < static_cast<uint32_t>(prob * 100.0f)) {
					heat_gain += static_cast<int>(HEAT_SPREAD) / 4 + static_cast<int>(rng % static_cast<uint32_t>(HEAT_SPREAD));
				}
			}
			if (is_burning_cell(n_left, mt)) {
				int n_mat = static_cast<int>(n_left.material);
				int n_temp = static_cast<int>(n_left.temperature);
				float prob = static_cast<float>(n_temp - mt->get_ignition_temp(n_mat)) /
						static_cast<float>(FIRE_TEMP - mt->get_ignition_temp(n_mat)) * SPREAD_PROB_MAX;
				uint32_t rng = ChunkView::hash_u32(base_rng ^ 3u);
				if ((rng % 100u) < static_cast<uint32_t>(prob * 100.0f)) {
					heat_gain += static_cast<int>(HEAT_SPREAD) / 4 + static_cast<int>(rng % static_cast<uint32_t>(HEAT_SPREAD));
				}
			}
			if (is_burning_cell(n_right, mt)) {
				int n_mat = static_cast<int>(n_right.material);
				int n_temp = static_cast<int>(n_right.temperature);
				float prob = static_cast<float>(n_temp - mt->get_ignition_temp(n_mat)) /
						static_cast<float>(FIRE_TEMP - mt->get_ignition_temp(n_mat)) * SPREAD_PROB_MAX;
				uint32_t rng = ChunkView::hash_u32(base_rng ^ 4u);
				if ((rng % 100u) < static_cast<uint32_t>(prob * 100.0f)) {
					heat_gain += static_cast<int>(HEAT_SPREAD) / 2 + static_cast<int>(rng % static_cast<uint32_t>(HEAT_SPREAD));
				}
			}

			if (is_hot_lava_for_mat(n_up, material, lava_id, mt)) {
				heat_gain += static_cast<int>(n_up.temperature) / 4;
			}
			if (is_hot_lava_for_mat(n_down, material, lava_id, mt)) {
				heat_gain += static_cast<int>(n_down.temperature) / 4;
			}
			if (is_hot_lava_for_mat(n_left, material, lava_id, mt)) {
				heat_gain += static_cast<int>(n_left.temperature) / 4;
			}
			if (is_hot_lava_for_mat(n_right, material, lava_id, mt)) {
				heat_gain += static_cast<int>(n_right.temperature) / 4;
			}

			if (mt->is_flammable(material)) {
				temperature = std::min(255, temperature + heat_gain);
				temperature = std::max(0, temperature - static_cast<int>(HEAT_DISSIPATION));
				if (temperature > mt->get_ignition_temp(material)) {
					health = health - 1;
					temperature = static_cast<int>(FIRE_TEMP);
					if (health <= 0) {
						material = air_id;
						health = 0;
						temperature = 0;
					}
				}
			}

			if (material != static_cast<int>(c.material) ||
					health != static_cast<int>(c.health) ||
					temperature != static_cast<int>(c.temperature)) {
				c.material = static_cast<uint8_t>(material);
				c.health = static_cast<uint8_t>(health);
				c.temperature = static_cast<uint8_t>(temperature);
				*v.at(x, y) = c;
				chunk->extend_next_dirty_rect(x, y, x + 1, y + 1);
				chunk->set_sleeping(false);
			}
		}
	}
}

} // namespace toprogue
