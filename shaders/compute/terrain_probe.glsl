#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 1, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) readonly uniform image2D chunk_tex;

layout(set = 0, binding = 1, std430) readonly buffer ProbeInput {
	ivec2 local_coords[];
} probe_input;

layout(set = 0, binding = 2, std430) buffer ProbeOutput {
	uint mat_ids[];
} probe_output;

layout(push_constant, std430) uniform PushConstants {
	uint probe_start;
	uint probe_count;
} pc;

void main() {
	uint gid = gl_GlobalInvocationID.x;
	if (gid >= pc.probe_count) {
		return;
	}
	uint slot = pc.probe_start + gid;
	ivec2 c = probe_input.local_coords[slot];
	vec4 px = imageLoad(chunk_tex, c);
	probe_output.mat_ids[slot] = uint(px.r * 255.0 + 0.5);
}
