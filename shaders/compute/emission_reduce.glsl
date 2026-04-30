#[compute]
#version 450

#include "res://shaders/generated/materials.glslinc"

const int CELL_SIZE = 4;
const int TILE_SIZE = 64;
const int CHUNK_SIZE = 256;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) readonly uniform image2D chunk_tex;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D emission_tile;

void main() {
	ivec2 tile_pos = ivec2(gl_GlobalInvocationID.xy);
	if (tile_pos.x >= TILE_SIZE || tile_pos.y >= TILE_SIZE) return;

	vec3 sum = vec3(0.0);
	ivec2 base = tile_pos * CELL_SIZE;
	for (int dy = 0; dy < CELL_SIZE; ++dy) {
		for (int dx = 0; dx < CELL_SIZE; ++dx) {
			vec4 p = imageLoad(chunk_tex, base + ivec2(dx, dy));
			int m = int(round(p.r * 255.0));
			if (m < 0 || m >= MAT_COUNT) continue;
			float g = MATERIAL_GLOW[m];
			if (g <= 0.0) continue;
			sum += MATERIAL_TINT[m].rgb * g;
		}
	}
	imageStore(emission_tile, tile_pos, vec4(sum / 16.0, 1.0));
}
