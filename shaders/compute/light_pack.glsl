#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) readonly uniform image2D chunk_tex;

layout(push_constant, std430) uniform PushConstants {
	ivec2 chunk_coord;
	int _pad0;
	int _pad1;
} pc;

const uint CELL_SIZE = 64u;
const uint CELLS_X = 4u;
const uint CELLS_Y = 4u;

struct LightCell {
	uint packed_count_glow;   // bits [15:0] = pixel_count, bits [31:16] = avg_glow_raw (glow × 1000)
	uint packed_pos;          // bits [15:0] = avg_x, bits [31:16] = avg_y
};

layout(set = 0, binding = 1, std430) buffer LightOutput {
	LightCell cells[];
} output_data;

shared uint s_counts[64];
shared uint s_sum_x[64];
shared uint s_sum_y[64];
shared uint s_sum_glow[64];

int get_material(vec4 pixel) {
	return int(pixel.r * 255.0 + 0.5);
}

void main() {
	uint thread_idx = gl_LocalInvocationIndex;
	uint cell_x = gl_WorkGroupID.x;
	uint cell_y = gl_WorkGroupID.y;
	uint cell_idx = cell_y * CELLS_X + cell_x;

	if (cell_x >= CELLS_X || cell_y >= CELLS_Y) return;

	uint local_count = 0u;
	uint local_sum_x = 0u;
	uint local_sum_y = 0u;
	uint local_sum_glow = 0u;

	uint base_x = cell_x * CELL_SIZE;
	uint base_y = cell_y * CELL_SIZE;

	for (uint dy = 0u; dy < 8u; dy++) {
		for (uint dx = 0u; dx < 8u; dx++) {
			uint px = base_x + gl_LocalInvocationID.x * 8u + dx;
			uint py = base_y + gl_LocalInvocationID.y * 8u + dy;

			vec4 pixel = imageLoad(chunk_tex, ivec2(px, py));
			int mat = get_material(pixel);

			if (mat >= 0 && mat < MAT_COUNT && MATERIAL_GLOW[mat] > 1.0) {
				local_count += 1u;
				local_sum_x += px;
				local_sum_y += py;
				local_sum_glow += uint(MATERIAL_GLOW[mat] * 1000.0 + 0.5);
			}
		}
	}

	s_counts[thread_idx] = local_count;
	s_sum_x[thread_idx] = local_sum_x;
	s_sum_y[thread_idx] = local_sum_y;
	s_sum_glow[thread_idx] = local_sum_glow;

	barrier();

	for (uint stride = 32u; stride > 0u; stride >>= 1) {
		if (thread_idx < stride) {
			s_counts[thread_idx] += s_counts[thread_idx + stride];
			s_sum_x[thread_idx] += s_sum_x[thread_idx + stride];
			s_sum_y[thread_idx] += s_sum_y[thread_idx + stride];
			s_sum_glow[thread_idx] += s_sum_glow[thread_idx + stride];
		}
		barrier();
	}

	if (thread_idx == 0u) {
		if (cell_idx >= CELLS_X * CELLS_Y) return;
		uint count = s_counts[0];
		if (count < 4u) {
			output_data.cells[cell_idx].packed_count_glow = 0u;
			output_data.cells[cell_idx].packed_pos = 0u;
		} else {
			uint avg_x = s_sum_x[0] / count;
			uint avg_y = s_sum_y[0] / count;
			uint avg_glow_raw = s_sum_glow[0] / count;
			output_data.cells[cell_idx].packed_count_glow = (avg_glow_raw << 16) | (count & 0xFFFFu);
			output_data.cells[cell_idx].packed_pos = (avg_y << 16) | (avg_x & 0xFFFFu);
		}
	}
}
