#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform image2D chunk_tex;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (pos.x >= 256 || pos.y >= 256) return;

	// Wood: material=1, health=255, temperature=0, reserved=0
	vec4 pixel = vec4(1.0 / 255.0, 1.0, 0.0, 0.0);
	imageStore(chunk_tex, pos, pixel);
}
