struct Context {
    ivec2 chunk_coord;
    uint world_seed;
};

void stage_wood_fill(Context ctx, layout(rgba8, set = 0, binding = 0) image2D chunk_tex) {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= 256 || pos.y >= 256) return;

    // Wood: material=1, health=255, temperature=0, reserved=0
    vec4 pixel = vec4(1.0 / 255.0, 1.0, 0.0, 0.0);
    imageStore(chunk_tex, pos, pixel);
}