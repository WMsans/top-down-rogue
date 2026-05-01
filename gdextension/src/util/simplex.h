#pragma once

#include <cstdint>

namespace toprogue::simplex {

uint32_t hash_uint(uint32_t x);
uint32_t hash_combine(uint32_t a, uint32_t b);

float snoise(float x, float y);
float snoise_seeded(float x, float y, uint32_t seed);
float snoise01(float x, float y, uint32_t seed);

float simplex_fbm(float x, float y, uint32_t seed, int octaves);
float simplex_ridge(float x, float y, uint32_t seed, int octaves);

} // namespace toprogue::simplex
