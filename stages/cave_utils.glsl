// ----- Hash utilities -----

const int CHUNK_SIZE = 256;

const int TYPE_CAVE = 0;
const int TYPE_MULTI_PRIMARY = 1;
const int TYPE_MULTI_SECONDARY = 2;
const int TYPE_TUNNEL = 3;

// Direction constants: 0=left, 1=right, 2=up, 3=down
const int DIR_LEFT = 0;
const int DIR_RIGHT = 1;
const int DIR_UP = 2;
const int DIR_DOWN = 3;

const ivec2 DIR_OFFSETS[4] = ivec2[4](
    ivec2(-1, 0),  // left
    ivec2(1, 0),   // right
    ivec2(0, -1),  // up
    ivec2(0, 1)    // down
);

// Opposite direction lookup: left<->right, up<->down
const int DIR_OPPOSITE[4] = int[4](1, 0, 3, 2);

uint hash_uint(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

uint hash_combine(uint a, uint b) {
    return hash_uint(a ^ (b * 0x9e3779b9u + 0x9e3779b9u + (a << 6u) + (a >> 2u)));
}

uint hash_ivec2(ivec2 v, uint seed) {
    uint hx = hash_uint(uint(v.x) + 0x10000u);
    uint hy = hash_uint(uint(v.y) + 0x10000u);
    return hash_combine(hash_combine(hx, hy), seed);
}

// Hash 4 ints + seed into a single uint
uint hash_edge(int a, int b, int c, int d, uint seed) {
    uint h = hash_uint(uint(a) + 0x10000u);
    h = hash_combine(h, uint(b) + 0x10000u);
    h = hash_combine(h, uint(c) + 0x10000u);
    h = hash_combine(h, uint(d) + 0x10000u);
    return hash_combine(h, seed);
}

// Returns a float in [0, 1] from a hash
float hash_to_float(uint h) {
    return float(h & 0xFFFFu) / 65535.0;
}

// ----- 2D Value Noise -----

// Lattice-based value noise: hash at integer corners, bilinear interpolate
float value_noise_2d(vec2 p, uint seed) {
    ivec2 i = ivec2(floor(p));
    vec2 f = fract(p);

    // Smoothstep interpolation (Hermite)
    vec2 u = f * f * (3.0 - 2.0 * f);

    float c00 = hash_to_float(hash_combine(hash_ivec2(i, seed), 0u));
    float c10 = hash_to_float(hash_combine(hash_ivec2(i + ivec2(1, 0), seed), 0u));
    float c01 = hash_to_float(hash_combine(hash_ivec2(i + ivec2(0, 1), seed), 0u));
    float c11 = hash_to_float(hash_combine(hash_ivec2(i + ivec2(1, 1), seed), 0u));

    return mix(mix(c00, c10, u.x), mix(c01, c11, u.x), u.y);
}

// Fractal Brownian Motion — 3 octaves for organic shapes
float fbm_2d(vec2 p, uint seed) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 3; i++) {
        value += amplitude * value_noise_2d(p * frequency, hash_combine(seed, uint(i)));
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}
