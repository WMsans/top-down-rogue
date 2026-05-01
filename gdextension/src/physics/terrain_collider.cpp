#include "terrain_collider.h"

#include "_marching_squares.inl"
#include "collider_builder.h"

#include <godot_cpp/classes/concave_polygon_shape2d.hpp>
#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/classes/light_occluder2d.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <vector>

using namespace godot;

namespace toprogue {

CollisionShape2D *TerrainCollider::build_collision(
		const PackedByteArray &data, int size, StaticBody2D *static_body,
		const Vector2i &world_offset) {
	PackedVector2Array segs = ColliderBuilder::build_segments(data, size);
	if (segs.size() < 4) {
		return nullptr;
	}
	return build_from_segments(segs, static_body, world_offset);
}

CollisionShape2D *TerrainCollider::build_from_segments(
		const PackedVector2Array &segments, StaticBody2D *static_body,
		const Vector2i &world_offset) {
	if (segments.size() % 2 != 0) {
		return nullptr;
	}
	if (segments.size() < 4) {
		return nullptr;
	}

	Ref<ConcavePolygonShape2D> shape;
	shape.instantiate();
	shape->set_segments(segments);

	CollisionShape2D *cs = memnew(CollisionShape2D);
	cs->set_shape(shape);
	static_body->set_position(Vector2(world_offset.x, world_offset.y));
	return cs;
}

PackedVector2Array TerrainCollider::shrink_polygon(const PackedVector2Array &points, double distance) {
	if (points.size() < 3) {
		return PackedVector2Array();
	}
	double sa = signed_area(points);
	double inward = (sa > 0.0) ? 1.0 : -1.0;
	PackedVector2Array out;
	out.resize(points.size());
	for (int i = 0; i < points.size(); i++) {
		int prev_i = (i - 1 + points.size()) % points.size();
		int next_i = (i + 1) % points.size();
		Vector2 e1 = points[i] - points[prev_i];
		Vector2 e2 = points[next_i] - points[i];
		Vector2 p1(-e1.y, e1.x);
		Vector2 p2(-e2.y, e2.x);
		Vector2 normal = (p1.normalized() + p2.normalized()).normalized();
		out[i] = points[i] + normal * distance * inward;
	}
	return out;
}

TypedArray<OccluderPolygon2D> TerrainCollider::create_occluder_polygons(const PackedVector2Array &segments) {
	TypedArray<OccluderPolygon2D> result;
	if (segments.size() < 4) {
		return result;
	}

	HashMap<Vector2, std::vector<Vector2>> adj;
	for (int i = 0; i < segments.size(); i += 2) {
		adj[segments[i]].push_back(segments[i + 1]);
		adj[segments[i + 1]].push_back(segments[i]);
	}

	HashMap<Vector2, bool> visited;
	Geometry2D *g2d = Geometry2D::get_singleton();

	for (const KeyValue<Vector2, std::vector<Vector2>> &kv : adj) {
		Vector2 start = kv.key;
		if (visited.has(start)) {
			continue;
		}
		if (kv.value.empty()) {
			continue;
		}

		PackedVector2Array chain;
		Vector2 current = start;
		Vector2 prev(-1e9, -1e9);
		bool closed = false;

		while (true) {
			visited[current] = true;
			chain.push_back(current);
			const std::vector<Vector2> &nbrs = adj[current];
			Vector2 next(-1e9, -1e9);
			for (const Vector2 &n : nbrs) {
				if (n == prev) {
					continue;
				}
				if (n == start && chain.size() >= 3) {
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
			if (next == Vector2(-1e9, -1e9)) {
				break;
			}
			prev = current;
			current = next;
		}

		if (chain.size() >= 3 && closed) {
			if (signed_area(chain) < 0.0) {
				continue;
			}
			TypedArray<PackedVector2Array> shrunk = g2d->offset_polygon(chain, -OCCLUDER_INSET, Geometry2D::JOIN_MITER);
			for (int i = 0; i < shrunk.size(); i++) {
				PackedVector2Array s = shrunk[i];
				if (s.size() >= 3 && polygon_area(s) >= MIN_OCCLUDER_AREA) {
					Ref<OccluderPolygon2D> poly;
					poly.instantiate();
					poly->set_polygon(s);
					result.push_back(poly);
				}
			}
		}
	}

	return result;
}

void TerrainCollider::_bind_methods() {
	ClassDB::bind_static_method("TerrainCollider",
			D_METHOD("build_collision", "data", "size", "static_body", "world_offset"),
			&TerrainCollider::build_collision);
	ClassDB::bind_static_method("TerrainCollider",
			D_METHOD("build_from_segments", "segments", "static_body", "world_offset"),
			&TerrainCollider::build_from_segments);
	ClassDB::bind_static_method("TerrainCollider",
			D_METHOD("create_occluder_polygons", "segments"),
			&TerrainCollider::create_occluder_polygons);
	ClassDB::bind_static_method("TerrainCollider",
			D_METHOD("shrink_polygon", "points", "distance"),
			&TerrainCollider::shrink_polygon);
}

} // namespace toprogue
