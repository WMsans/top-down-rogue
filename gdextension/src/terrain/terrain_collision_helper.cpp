#include "terrain_collision_helper.h"

#include "../physics/collider_builder.h"
#include "../physics/terrain_collider.h"
#include "../sim/material_table.h"
#include "chunk.h"

#include <godot_cpp/classes/light_occluder2d.hpp>
#include <godot_cpp/classes/static_body2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;

namespace toprogue {

void TerrainCollisionHelper::rebuild_dirty(const Dictionary &chunks, double delta) {
	if (chunks.is_empty()) {
		return;
	}
	_collision_rebuild_timer += delta;
	if (_collision_rebuild_timer < COLLISION_REBUILD_INTERVAL) {
		return;
	}
	_collision_rebuild_timer = 0.0;

	Array coords = chunks.keys();
	int total = coords.size();
	int count = MIN(COLLISIONS_PER_FRAME, total);
	for (int i = 0; i < count; i++) {
		int idx = (_collision_rebuild_index + i) % total;
		Variant chunk_v = chunks[coords[idx]];
		rebuild_chunk_collision_cpu(chunk_v);
	}
	_collision_rebuild_index = (_collision_rebuild_index + count) % std::max(1, total);
}

void TerrainCollisionHelper::rebuild_chunk_collision_cpu(const Variant &chunk_v) {
	Ref<Chunk> chunk = chunk_v;
	if (chunk.is_null()) {
		return;
	}
	if (world_manager == nullptr) {
		return;
	}

	// Read material data directly from chunk's cells[] array.
	PackedByteArray material_data;
	material_data.resize(CHUNK_SIZE * CHUNK_SIZE);
	MaterialTable *mt = MaterialTable::get_singleton();
	const Cell *cells = chunk->cells_ptr();
	for (int y = 0; y < CHUNK_SIZE; y++) {
		for (int x = 0; x < CHUNK_SIZE; x++) {
			int mat = cells[y * CHUNK_SIZE + x].material;
			material_data[y * CHUNK_SIZE + x] = mt->has_collider(mat) ? static_cast<uint8_t>(mat) : 0;
		}
	}

	Vector2i world_offset = chunk->coord * CHUNK_SIZE;

	StaticBody2D *body = chunk->static_body;
	if (body && body->get_child_count() > 0) {
		TypedArray<Node> children = body->get_children();
		for (int i = 0; i < children.size(); i++) {
			Node *c = Object::cast_to<Node>(children[i]);
			if (c) {
				c->queue_free();
			}
		}
	}

	PackedVector2Array segs = ColliderBuilder::build_segments(material_data, CHUNK_SIZE);
	CollisionShape2D *shape = TerrainCollider::build_from_segments(segs, body, world_offset);
	if (shape) {
		body->add_child(shape);
	}

	Node *occluder_parent = Object::cast_to<Node>(world_manager->get("collision_container").operator Object *());
	TypedArray<LightOccluder2D> existing = chunk->occluder_instances;
	for (int i = 0; i < existing.size(); i++) {
		Object *o = existing[i];
		Node *n = Object::cast_to<Node>(o);
		if (n && n->is_inside_tree()) {
			n->queue_free();
		}
	}
	existing.clear();
	chunk->occluder_instances = existing;

	if (segs.size() >= 4 && occluder_parent) {
		TypedArray<OccluderPolygon2D> polys = TerrainCollider::create_occluder_polygons(segs);
		Vector2 chunk_pos(chunk->coord.x * CHUNK_SIZE, chunk->coord.y * CHUNK_SIZE);
		for (int i = 0; i < polys.size(); i++) {
			Ref<OccluderPolygon2D> p = polys[i];
			LightOccluder2D *occ = memnew(LightOccluder2D);
			occ->set_position(chunk_pos);
			occ->set_occluder_polygon(p);
			occluder_parent->add_child(occ);
			existing.push_back(occ);
		}
		chunk->occluder_instances = existing;
	}
}

void TerrainCollisionHelper::_bind_methods() {
	ClassDB::bind_method(D_METHOD("rebuild_dirty", "chunks", "delta"),
			&TerrainCollisionHelper::rebuild_dirty);
	ClassDB::bind_method(D_METHOD("rebuild_chunk_collision_cpu", "chunk"),
			&TerrainCollisionHelper::rebuild_chunk_collision_cpu);

	ClassDB::bind_method(D_METHOD("get_world_manager"), &TerrainCollisionHelper::get_world_manager);
	ClassDB::bind_method(D_METHOD("set_world_manager", "v"), &TerrainCollisionHelper::set_world_manager);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "world_manager",
						 PROPERTY_HINT_NODE_TYPE, "Node2D"),
			"set_world_manager", "get_world_manager");
}

} // namespace toprogue
