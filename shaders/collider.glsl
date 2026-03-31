#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8ui) uniform readonly uimage2D terrain_texture;
layout(std430, binding = 1) buffer SegmentBuffer {
	uint count;
	uint data[];
} segment_buffer;

const uint CELL_SIZE = 2u;
const uint CHUNK_SIZE = 256u;
const uint CELLS_PER_SIDE = CHUNK_SIZE / CELL_SIZE;
const uint MAX_SEGMENTS = 4096u;

void main() {
	uint cell_x = gl_GlobalInvocationID.x;
	uint cell_y = gl_GlobalInvocationID.y;

	if (cell_x >= CELLS_PER_SIDE || cell_y >= CELLS_PER_SIDE) {
		return;
	}

	// Sample 4 corners of the cell
	uint gx = cell_x * CELL_SIZE;
	uint gy = cell_y * CELL_SIZE;

	// Border cells are treated as air (outside chunk)
	if (gx == 0 || gy == 0 || gx >= CHUNK_SIZE - CELL_SIZE || gy >= CHUNK_SIZE - CELL_SIZE) {
		return;
	}

	uvec4 tl_sample = imageLoad(terrain_texture, ivec2(gx, gy));
	uvec4 tr_sample = imageLoad(terrain_texture, ivec2(gx + CELL_SIZE, gy));
	uvec4 br_sample = imageLoad(terrain_texture, ivec2(gx + CELL_SIZE, gy + CELL_SIZE));
	uvec4 bl_sample = imageLoad(terrain_texture, ivec2(gx, gy + CELL_SIZE));

	// Material is in R channel, check if solid (non-zero)
	uint tl = (tl_sample.r != 0u) ? 1u : 0u;
	uint tr = (tr_sample.r != 0u) ? 1u : 0u;
	uint br = (br_sample.r != 0u) ? 1u : 0u;
	uint bl = (bl_sample.r != 0u) ? 1u : 0u;

	// All air or all solid => no segment
	if (tl + tr + br + bl == 0u || tl + tr + br + bl == 4u) {
		return;
	}

	uint case_idx = (tl << 3u) | (tr << 2u) | (br << 1u) | bl;

	// Edge midpoints in cell coordinates
	uint half_cell = CELL_SIZE / 2u;
	uvec2 top_edge = uvec2(gx + half_cell, gy);
	uvec2 right_edge = uvec2(gx + CELL_SIZE, gy + half_cell);
	uvec2 bottom_edge = uvec2(gx + half_cell, gy + CELL_SIZE);
	uvec2 left_edge = uvec2(gx, gy + half_cell);

	// Get segments for this case
	// Each segment is [p1, p2] encoded as 4 uints
	uint segments[8];
	uint num_segments = 0u;

	switch (case_idx) {
		case 1u: // D
			segments[0] = left_edge.x; segments[1] = left_edge.y;
			segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
			num_segments = 1u;
			break;
		case 2u: // C
			segments[0] = bottom_edge.x; segments[1] = bottom_edge.y;
			segments[2] = right_edge.x; segments[3] = right_edge.y;
			num_segments = 1u;
			break;
		case 3u: // D+C
			segments[0] = left_edge.x; segments[1] = left_edge.y;
			segments[2] = right_edge.x; segments[3] = right_edge.y;
			num_segments = 1u;
			break;
		case 4u: // B
			segments[0] = right_edge.x; segments[1] = right_edge.y;
			segments[2] = top_edge.x; segments[3] = top_edge.y;
			num_segments = 1u;
			break;
		case 5u: // D+B (saddle)
			segments[0] = left_edge.x; segments[1] = left_edge.y;
			segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
			segments[4] = right_edge.x; segments[5] = right_edge.y;
			segments[6] = top_edge.x; segments[7] = top_edge.y;
			num_segments = 2u;
			break;
		case 6u: // C+B
			segments[0] = bottom_edge.x; segments[1] = bottom_edge.y;
			segments[2] = top_edge.x; segments[3] = top_edge.y;
			num_segments = 1u;
			break;
		case 7u: // D+C+B
			segments[0] = left_edge.x; segments[1] = left_edge.y;
			segments[2] = top_edge.x; segments[3] = top_edge.y;
			num_segments = 1u;
			break;
		case 8u: // A
			segments[0] = top_edge.x; segments[1] = top_edge.y;
			segments[2] = left_edge.x; segments[3] = left_edge.y;
			num_segments = 1u;
			break;
		case 9u: // A+D
			segments[0] = top_edge.x; segments[1] = top_edge.y;
			segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
			num_segments = 1u;
			break;
		case 10u: // A+C (saddle)
			segments[0] = top_edge.x; segments[1] = top_edge.y;
			segments[2] = left_edge.x; segments[3] = left_edge.y;
			segments[4] = bottom_edge.x; segments[5] = bottom_edge.y;
			segments[6] = right_edge.x; segments[7] = right_edge.y;
			num_segments = 2u;
			break;
		case 11u: // A+C+B
			segments[0] = top_edge.x; segments[1] = top_edge.y;
			segments[2] = right_edge.x; segments[3] = right_edge.y;
			num_segments = 1u;
			break;
		case 12u: // A+B
			segments[0] = right_edge.x; segments[1] = right_edge.y;
			segments[2] = left_edge.x; segments[3] = left_edge.y;
			num_segments = 1u;
			break;
		case 13u: // A+B+D
			segments[0] = bottom_edge.x; segments[1] = bottom_edge.y;
			segments[2] = left_edge.x; segments[3] = left_edge.y;
			num_segments = 1u;
			break;
		case 14u: // A+B+C
			segments[0] = right_edge.x; segments[1] = right_edge.y;
			segments[2] = bottom_edge.x; segments[3] = bottom_edge.y;
			num_segments = 1u;
			break;
		case 15u: // A+B+C+D
			// All solid, no segment
			num_segments = 0u;
			break;
	}

	// Atomically reserve space in the buffer and write segments
	for (uint s = 0u; s < num_segments; s++) {
		uint idx = atomicAdd(segment_buffer.count, 4u);
		if (idx + 4u > MAX_SEGMENTS * 4u) {
			return;
		}
		segment_buffer.data[idx + 0] = segments[s * 4 + 0];
		segment_buffer.data[idx + 1] = segments[s * 4 + 1];
		segment_buffer.data[idx + 2] = segments[s * 4 + 2];
		segment_buffer.data[idx + 3] = segments[s * 4 + 3];
	}
}