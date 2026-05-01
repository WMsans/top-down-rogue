#pragma once

// Shared marching-squares helpers included by terrain_collider.cpp and
// collider_builder.cpp. Each TU gets its own copy to avoid link issues.

#include "terrain_collider.h"

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cmath>
#include <vector>

namespace toprogue {
namespace {

struct MsCase { int count; int seg[2][2]; };
static constexpr MsCase MS_TABLE[16] = {
	/*  0 */ {0, {{0,0},{0,0}}},
	/*  1 */ {1, {{3,2},{0,0}}},
	/*  2 */ {1, {{2,1},{0,0}}},
	/*  3 */ {1, {{3,1},{0,0}}},
	/*  4 */ {1, {{1,0},{0,0}}},
	/*  5 */ {2, {{0,1},{3,2}}},
	/*  6 */ {1, {{2,0},{0,0}}},
	/*  7 */ {1, {{3,0},{0,0}}},
	/*  8 */ {1, {{0,3},{0,0}}},
	/*  9 */ {1, {{0,2},{0,0}}},
	/* 10 */ {2, {{0,3},{1,2}}},
	/* 11 */ {1, {{0,1},{0,0}}},
	/* 12 */ {1, {{1,3},{0,0}}},
	/* 13 */ {1, {{1,2},{0,0}}},
	/* 14 */ {1, {{2,3},{0,0}}},
	/* 15 */ {0, {{0,0},{0,0}}},
};

static godot::Vector2i edge_point(int cx, int cy, int edge) {
	constexpr int half = TerrainCollider::CELL_SIZE / 2;
	switch (edge) {
		case 0: return godot::Vector2i(cx * TerrainCollider::CELL_SIZE + half, cy * TerrainCollider::CELL_SIZE);
		case 1: return godot::Vector2i((cx + 1) * TerrainCollider::CELL_SIZE, cy * TerrainCollider::CELL_SIZE + half);
		case 2: return godot::Vector2i(cx * TerrainCollider::CELL_SIZE + half, (cy + 1) * TerrainCollider::CELL_SIZE);
		case 3: return godot::Vector2i(cx * TerrainCollider::CELL_SIZE, cy * TerrainCollider::CELL_SIZE + half);
	}
	return godot::Vector2i(0, 0);
}

static double point_to_segment_distance(const godot::Vector2 &p, const godot::Vector2 &a, const godot::Vector2 &b) {
	godot::Vector2 line = b - a;
	double ls = line.length_squared();
	if (ls < 1e-4) return p.distance_to(a);
	double t = godot::Math::clamp((p - a).dot(line) / ls, 0.0, 1.0);
	godot::Vector2 proj = a + line * t;
	return p.distance_to(proj);
}

static godot::PackedVector2Array douglas_peucker(const godot::PackedVector2Array &pts, double eps) {
	if (pts.size() <= 2) return pts;
	double max_dist = 0.0;
	int max_idx = 0;
	godot::Vector2 first = pts[0];
	godot::Vector2 last = pts[pts.size() - 1];
	for (int i = 1; i < pts.size() - 1; i++) {
		double d = point_to_segment_distance(pts[i], first, last);
		if (d > max_dist) { max_dist = d; max_idx = i; }
	}
	godot::PackedVector2Array out;
	if (max_dist > eps) {
		godot::PackedVector2Array left = douglas_peucker(pts.slice(0, max_idx + 1), eps);
		godot::PackedVector2Array right = douglas_peucker(pts.slice(max_idx), eps);
		for (int i = 0; i < left.size() - 1; i++) out.push_back(left[i]);
		for (int i = 0; i < right.size(); i++) out.push_back(right[i]);
	} else {
		out.push_back(first);
		out.push_back(last);
	}
	return out;
}

static godot::PackedVector2Array simplify_closed_polygon(const godot::PackedVector2Array &pts, double eps) {
	int n = pts.size();
	if (n <= 4) return pts;
	int mid = n / 2;
	godot::PackedVector2Array c1, c2;
	for (int i = 0; i <= mid; i++) c1.push_back(pts[i]);
	for (int i = mid; i < n; i++) c2.push_back(pts[i]);
	c2.push_back(pts[0]);
	c1 = douglas_peucker(c1, eps);
	c2 = douglas_peucker(c2, eps);
	godot::PackedVector2Array out;
	for (int i = 0; i < c1.size(); i++) out.push_back(c1[i]);
	for (int i = 1; i < c2.size() - 1; i++) out.push_back(c2[i]);
	return out;
}

static double signed_area(const godot::PackedVector2Array &pts) {
	if (pts.size() < 3) return 0.0;
	double s = 0.0;
	for (int i = 0; i < pts.size(); i++) {
		int j = (i + 1) % pts.size();
		s += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
	}
	return s * 0.5;
}

static double polygon_area(const godot::PackedVector2Array &pts) { return std::abs(signed_area(pts)); }

} // anonymous namespace
} // namespace toprogue
