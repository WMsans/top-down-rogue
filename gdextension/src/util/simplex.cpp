#include "simplex.h"

#include <cmath>

namespace toprogue::simplex {

// --- Internal helpers (ported line-by-line from simplex_2d.glslinc) ---

static inline float _mod289(float x) {
	return x - std::floor(x * (1.0f / 289.0f)) * 289.0f;
}

// Permute a scalar: _mod289(((x * 34.0) + 1.0) * x)
static inline float _permute1(float x) {
	return _mod289((x * 34.0f + 1.0f) * x);
}

// --- Public functions ---

uint32_t hash_uint(uint32_t x) {
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	return x;
}

uint32_t hash_combine(uint32_t a, uint32_t b) {
	return hash_uint(a ^ (b * 0x9e3779b9u + 0x9e3779b9u + (a << 6u) + (a >> 2u)));
}

// Port of Ashima simplex-2D snoise (returns [-1, 1]).
float snoise(float x, float y) {
	constexpr float Cx = 0.211324865405187f;
	constexpr float Cy = 0.366025403784439f;
	constexpr float Cz = -0.577350269189626f;
	constexpr float Cw = 0.024390243902439f;

	// Skew to simplex grid
	float s = (x + y) * Cy;
	float i_x = std::floor(x + s);
	float i_y = std::floor(y + s);

	// Unskew back to original grid
	float t = (i_x + i_y) * Cx;
	float x0_x = x - i_x + t;
	float x0_y = y - i_y + t;

	// Determine which simplex we are in
	float i1_x = (x0_x > x0_y) ? 1.0f : 0.0f;
	float i1_y = (x0_x > x0_y) ? 0.0f : 1.0f;

	// Offsets for the other two corners
	float x12_x = x0_x + Cx;
	float x12_y = x0_y + Cx;
	float x12_z = x0_x + Cz;
	float x12_w = x0_y + Cz;

	x12_x -= i1_x;
	x12_y -= i1_y;

	// Wrap integer coordinates
	i_x = _mod289(i_x);
	i_y = _mod289(i_y);

	// Compute permutation for each corner
	float p0 = _permute1(_permute1(i_y) + i_x);
	float p1 = _permute1(_permute1(i_y + i1_y) + i_x + i1_x);
	float p2 = _permute1(_permute1(i_y + 1.0f) + i_x + 1.0f);

	// Gradient contributions
	// m = max(0.5 - dot(x, x), 0)^4 for each corner
	float d0 = x0_x * x0_x + x0_y * x0_y;
	float d1 = x12_x * x12_x + x12_y * x12_y;
	float d2 = x12_z * x12_z + x12_w * x12_w;

	float m0 = 0.5f - d0;
	if (m0 < 0.0f) m0 = 0.0f;
	m0 *= m0;
	m0 *= m0;

	float m1 = 0.5f - d1;
	if (m1 < 0.0f) m1 = 0.0f;
	m1 *= m1;
	m1 *= m1;

	float m2 = 0.5f - d2;
	if (m2 < 0.0f) m2 = 0.0f;
	m2 *= m2;
	m2 *= m2;

	// Pseudo-random gradients: x = 2*fract(p * Cw) - 1
	float fx0 = p0 * Cw;
	fx0 = 2.0f * (fx0 - std::floor(fx0)) - 1.0f;
	float fx1 = p1 * Cw;
	fx1 = 2.0f * (fx1 - std::floor(fx1)) - 1.0f;
	float fx2 = p2 * Cw;
	fx2 = 2.0f * (fx2 - std::floor(fx2)) - 1.0f;

	float h0 = std::fabs(fx0) - 0.5f;
	float h1 = std::fabs(fx1) - 0.5f;
	float h2 = std::fabs(fx2) - 0.5f;

	float a0_x = fx0 - std::floor(fx0 + 0.5f);
	float a1_x = fx1 - std::floor(fx1 + 0.5f);
	float a2_x = fx2 - std::floor(fx2 + 0.5f);

	// Normalization (poly approx of inversesqrt)
	m0 *= 1.79284291400159f - 0.85373472095314f * (a0_x * a0_x + h0 * h0);
	m1 *= 1.79284291400159f - 0.85373472095314f * (a1_x * a1_x + h1 * h1);
	m2 *= 1.79284291400159f - 0.85373472095314f * (a2_x * a2_x + h2 * h2);

	// Dot products (g components use the same scalar; g.x applied to x0, g.y applied to y)
	// In GLSL: g.x = a0.x * x0.x + h.x * x0.y   g.y = a0.y * x12.xz + h.y * x12.yw
	// Here each corner gets one gradient scalar; the "vec3 g" is three floats.
	float g0 = a0_x * x0_x + h0 * x0_y;
	float g1 = a1_x * x12_x + h1 * x12_y;
	float g2 = a2_x * x12_z + h2 * x12_w;

	return 130.0f * (m0 * g0 + m1 * g1 + m2 * g2);
}

// Simple hash for deterministic coordinate offset
static uint32_t _simple_hash(uint32_t x) {
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	return x;
}

float snoise_seeded(float x, float y, uint32_t seed) {
	float offset_x = float(_simple_hash(seed)) / 4294967295.0f * 1000.0f;
	float offset_y = float(_simple_hash(seed ^ 0x9e3779b9u)) / 4294967295.0f * 1000.0f;
	return snoise(x + offset_x, y + offset_y);
}

float snoise01(float x, float y, uint32_t seed) {
	return snoise_seeded(x, y, seed) * 0.5f + 0.5f;
}

float simplex_fbm(float x, float y, uint32_t seed, int octaves) {
	float value = 0.0f;
	float amplitude = 0.5f;
	float frequency = 1.0f;
	float max_value = 0.0f;

	for (int i = 0; i < octaves; i++) {
		value += amplitude * snoise01(x * frequency, y * frequency, hash_combine(seed, uint32_t(i)));
		max_value += amplitude;
		amplitude *= 0.5f;
		frequency *= 2.0f;
	}

	return value / max_value;
}

float simplex_ridge(float x, float y, uint32_t seed, int octaves) {
	float value = 0.0f;
	float amplitude = 0.5f;
	float frequency = 1.0f;
	float max_value = 0.0f;

	for (int i = 0; i < octaves; i++) {
		float n = snoise_seeded(x * frequency, y * frequency, hash_combine(seed, uint32_t(i)));
		n = 1.0f - std::fabs(n);
		n = n * n;
		value += amplitude * n;
		max_value += amplitude;
		amplitude *= 0.5f;
		frequency *= 2.0f;
	}

	return value / max_value;
}

} // namespace toprogue::simplex
