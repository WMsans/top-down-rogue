#include "gas_injector.h"

#include <godot_cpp/classes/capsule_shape2d.hpp>
#include <godot_cpp/classes/character_body2d.hpp>
#include <godot_cpp/classes/circle_shape2d.hpp>
#include <godot_cpp/classes/collision_object2d.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/rectangle_shape2d.hpp>
#include <godot_cpp/classes/rigid_body2d.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/shape2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cmath>

using namespace godot;

namespace toprogue {
namespace {

static Transform2D shape_owner_get_transform(CollisionObject2D *co, int owner_id) {
	uint32_t oid = static_cast<uint32_t>(owner_id);
	return co->shape_owner_get_transform(oid);
}

static Ref<Shape2D> shape_owner_get_shape(CollisionObject2D *co, int owner_id, int shape_idx) {
	uint32_t oid = static_cast<uint32_t>(owner_id);
	return co->shape_owner_get_shape(oid, shape_idx);
}

static int shape_owner_get_shape_count(CollisionObject2D *co, int owner_id) {
	uint32_t oid = static_cast<uint32_t>(owner_id);
	return co->shape_owner_get_shape_count(oid);
}

static Rect2 _shape_aabb(const Ref<Shape2D> &shape, const Transform2D &xform) {
	Ref<RectangleShape2D> rect = shape;
	if (rect.is_valid()) {
		Vector2 half = rect->get_size() * 0.5;
		Rect2 local(-half, half * 2.0);
		return xform.xform(local);
	}
	Ref<CircleShape2D> circle = shape;
	if (circle.is_valid()) {
		double r = circle->get_radius();
		Rect2 local(Vector2(-r, -r), Vector2(r * 2.0, r * 2.0));
		return xform.xform(local);
	}
	Ref<CapsuleShape2D> capsule = shape;
	if (capsule.is_valid()) {
		double h = capsule->get_height() * 0.5 + capsule->get_radius();
		Rect2 local(Vector2(-capsule->get_radius(), -h), Vector2(capsule->get_radius() * 2.0, h * 2.0));
		return xform.xform(local);
	}
	return xform.xform(Rect2(Vector2(-1, -1), Vector2(2, 2)));
}

static Rect2 _world_aabb_of(Node2D *node) {
	CollisionObject2D *co = Object::cast_to<CollisionObject2D>(node);
	if (co) {
		PackedInt32Array owners = co->get_shape_owners();
		Rect2 rect;
		bool first = true;
		for (int i = 0; i < owners.size(); i++) {
			int owner_id = owners[i];
			Transform2D transform = shape_owner_get_transform(co, owner_id);
			for (int j = 0; j < shape_owner_get_shape_count(co, owner_id); j++) {
				Ref<Shape2D> shape = shape_owner_get_shape(co, owner_id, j);
				Rect2 shape_rect = _shape_aabb(shape, transform);
				if (first) {
					rect = shape_rect;
					first = false;
				} else {
					rect = rect.merge(shape_rect);
				}
			}
		}
		if (!first) {
			rect.position += node->get_global_position();
			return rect;
		}
	}
	return Rect2(node->get_global_position() - Vector2(0.5, 0.5), Vector2(1, 1));
}

static Vector2 _get_node_velocity(Node2D *node) {
	CharacterBody2D *char_body = Object::cast_to<CharacterBody2D>(node);
	if (char_body) return char_body->get_velocity();
	RigidBody2D *rigid = Object::cast_to<RigidBody2D>(node);
	if (rigid) return rigid->get_linear_velocity();
	Variant v = node->get(StringName("velocity"));
	if (v.get_type() == Variant::VECTOR2) return Vector2(v);
	return Vector2(0, 0);
}

} // anonymous namespace

PackedByteArray GasInjector::build_payload(SceneTree *scene, const Vector2i &coord) {
	PackedByteArray out;
	out.resize(BUFFER_BYTES);
	out.fill(0);

	Rect2 chunk_world_rect(Vector2(coord) * CHUNK_SIZE, Vector2(CHUNK_SIZE, CHUNK_SIZE));

	TypedArray<Node> gas_nodes = scene->get_nodes_in_group(StringName("gas_interactors"));
	int count = 0;

	for (int i = 0; i < gas_nodes.size() && count < MAX_INJECTIONS_PER_CHUNK; i++) {
		Node2D *node = Object::cast_to<Node2D>(gas_nodes[i].operator Object *());
		if (!node) continue;

		Vector2 linvel = _get_node_velocity(node);
		if (linvel.length_squared() < MIN_SPEED_SQ) continue;

		Rect2 aabb_world = _world_aabb_of(node);
		if (!chunk_world_rect.intersects(aabb_world)) continue;

		Vector2i min_local(
			static_cast<int>(std::floor(aabb_world.position.x - chunk_world_rect.position.x)),
			static_cast<int>(std::floor(aabb_world.position.y - chunk_world_rect.position.y))
		);
		Vector2i max_local(
			static_cast<int>(std::ceil(aabb_world.get_end().x - chunk_world_rect.position.x)),
			static_cast<int>(std::ceil(aabb_world.get_end().y - chunk_world_rect.position.y))
		);
		min_local = min_local.clamp(Vector2i(0, 0), Vector2i(CHUNK_SIZE, CHUNK_SIZE));
		max_local = max_local.clamp(Vector2i(0, 0), Vector2i(CHUNK_SIZE, CHUNK_SIZE));
		if (max_local.x <= min_local.x || max_local.y <= min_local.y) continue;

		int vx = CLAMP(static_cast<int>(std::round(linvel.x * VELOCITY_SCALE)), -8, 7);
		int vy = CLAMP(static_cast<int>(std::round(linvel.y * VELOCITY_SCALE)), -8, 7);
		if (vx == 0 && vy == 0) continue;

		int offset = HEADER_BYTES + count * BODY_BYTES;
		out.encode_s32(offset + 0, min_local.x);
		out.encode_s32(offset + 4, min_local.y);
		out.encode_s32(offset + 8, max_local.x);
		out.encode_s32(offset + 12, max_local.y);
		out.encode_s32(offset + 16, vx);
		out.encode_s32(offset + 20, vy);
		count++;
	}

	out.encode_s32(0, count);
	return out;
}

void GasInjector::_bind_methods() {
	ClassDB::bind_static_method("GasInjector",
			D_METHOD("build_payload", "scene", "coord"),
			&GasInjector::build_payload);
}

} // namespace toprogue
