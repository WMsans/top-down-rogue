#include "collider_builder.h"

#include "_marching_squares.inl"
#include "terrain_collider.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <vector>

using namespace godot;

namespace toprogue {

PackedVector2Array ColliderBuilder::build_segments(const PackedByteArray &data, int size) {
	int samples_w = size / TerrainCollider::CELL_SIZE + 1;
	int samples_h = size / TerrainCollider::CELL_SIZE + 1;
	std::vector<uint8_t> samples(samples_w * samples_h, 0);

	for (int sy = 0; sy < samples_h; sy++) {
		for (int sx = 0; sx < samples_w; sx++) {
			if (sx == 0 || sx == samples_w - 1 || sy == 0 || sy == samples_h - 1) {
				continue;
			}
			int gx = MIN(sx * TerrainCollider::CELL_SIZE, size - 1);
			int gy = MIN(sy * TerrainCollider::CELL_SIZE, size - 1);
			samples[sy * samples_w + sx] = (data[gy * size + gx] != 0) ? 1 : 0;
		}
	}

	int cells_w = samples_w - 1;
	int cells_h = samples_h - 1;

	HashMap<Vector2i, std::vector<Vector2i>> adj;
	auto add_edge = [&](const Vector2i &a, const Vector2i &b) {
		adj[a].push_back(b);
		adj[b].push_back(a);
	};

	for (int cy = 0; cy < cells_h; cy++) {
		for (int cx = 0; cx < cells_w; cx++) {
			int tl = samples[cy * samples_w + cx];
			int tr = samples[cy * samples_w + cx + 1];
			int br = samples[(cy + 1) * samples_w + cx + 1];
			int bl = samples[(cy + 1) * samples_w + cx];
			int idx = (tl << 3) | (tr << 2) | (br << 1) | bl;
			for (int k = 0; k < MS_TABLE[idx].count; k++) {
				Vector2i p1 = edge_point(cx, cy, MS_TABLE[idx].seg[k][0]);
				Vector2i p2 = edge_point(cx, cy, MS_TABLE[idx].seg[k][1]);
				add_edge(p1, p2);
			}
		}
	}

	PackedVector2Array all_segments;
	HashMap<Vector2i, bool> visited;

	for (const KeyValue<Vector2i, std::vector<Vector2i>> &kv : adj) {
		Vector2i start = kv.key;
		if (visited.has(start)) {
			continue;
		}
		if (kv.value.empty()) {
			continue;
		}

		PackedVector2Array poly;
		Vector2i current = start;
		Vector2i prev = Vector2i(-999999, -999999);
		bool closed = false;

		while (true) {
			visited[current] = true;
			poly.push_back(Vector2(current.x, current.y));

			const std::vector<Vector2i> &nbrs = adj[current];
			Vector2i next = Vector2i(-999999, -999999);
			for (const Vector2i &n : nbrs) {
				if (n == prev) {
					continue;
				}
				if (n == start && poly.size() >= 3) {
					next = start;
					break;
				}
				if (!visited.has(n)) {
					next = n;
					break;
				}
			}
			if (next == start) {
				closed = true;
				break;
			}
			if (next == Vector2i(-999999, -999999)) {
				break;
			}
			prev = current;
			current = next;
		}

		if (poly.size() >= 3 && closed) {
			poly = simplify_closed_polygon(poly, TerrainCollider::DP_EPSILON);
			for (int i = 0; i < poly.size(); i++) {
				all_segments.push_back(poly[i]);
				all_segments.push_back(poly[(i + 1) % poly.size()]);
			}
		}
	}

	return all_segments;
}

void ColliderBuilder::_bind_methods() {
	ClassDB::bind_static_method("ColliderBuilder",
			D_METHOD("build_segments", "data", "size"),
			&ColliderBuilder::build_segments);
}

} // namespace toprogue
