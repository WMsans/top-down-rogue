#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) readonly uniform image2D src;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D dst;

layout(push_constant, std430) uniform PushConstants {
	int width;
	int height;
	int dir_x;
	int dir_y;
} pc;

const float W[11] = float[11](
	0.009167, 0.020298, 0.039771, 0.069041, 0.105991,
	0.143464,
	0.105991, 0.069041, 0.039771, 0.020298, 0.009167
);

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= pc.width || p.y >= pc.height) return;
	ivec2 dir = ivec2(pc.dir_x, pc.dir_y);
	vec3 sum = vec3(0.0);
	for (int i = -5; i <= 5; ++i) {
		ivec2 q = p + dir * i;
		q.x = clamp(q.x, 0, pc.width - 1);
		q.y = clamp(q.y, 0, pc.height - 1);
		sum += imageLoad(src, q).rgb * W[i + 5];
	}
	imageStore(dst, p, vec4(sum, 1.0));
}
