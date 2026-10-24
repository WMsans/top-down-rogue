extends GdUnitTestSuite

const _PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")

# Stub world_manager for ForestProp: nav grid via nav_field.grid. get_chunk_container
# and chunks_generated satisfy the SpawnDispatcher/CompositionDispatcher autoloads,
# which adopt any node in the "world_manager" group.
class StubNavField extends RefCounted:
	var grid

class StubWM extends Node:
	var nav_field

	signal chunks_generated(new_coords: Array[Vector2i])

	func get_chunk_container() -> Node2D:
		return null

# Records dig hits so Weapon.resolve_hit dispatch can be asserted.
class DigTarget extends Node2D:
	var dig_calls: Array = []
	var impact_called: bool = false

	func take_dig_hit(pos: Vector2, dir: Vector2, power: float) -> void:
		dig_calls.append({"pos": pos, "dir": dir, "power": power})

	func on_hit_impact(_pos: Vector2, _dir: Vector2) -> void:
		impact_called = true


# 16x32 opaque texture whose bottom 3 rows are fully transparent.
func _make_def() -> ForestPropDef:
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.4, 0.2, 1.0))
	for y in range(29, 32):
		for x in range(16):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	var def := ForestPropDef.new()
	def.texture = ImageTexture.create_from_image(img)
	return def


func test_setup_layers_and_groups() -> void:
	var def := _make_def()
	def.kind = "rock"
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(def, "1:0:0:0")
	assert_int(prop.collision_layer).is_equal(144)
	assert_int(prop.collision_mask).is_equal(0)
	assert_bool(prop.is_in_group("destructible")).is_true()
	assert_bool(prop.is_in_group("attackable")).is_false()
	assert_int(prop.z_index).is_equal(2)
	assert_bool(prop.z_as_relative).is_false()
	var shape_node := prop.get_node("CollisionShape2D") as CollisionShape2D
	assert_object(shape_node).is_not_null()
	var circle := shape_node.shape as CircleShape2D
	assert_object(circle).is_not_null()
	assert_float(circle.radius).is_equal(def.trunk_radius)


func test_sprite_bottom_at_origin() -> void:
	var def := _make_def()
	assert_int(def.base_inset()).is_equal(3)
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(def, "1:0:0:1")
	var sprite := prop.get_node("Sprite2D") as Sprite2D
	assert_object(sprite).is_not_null()
	assert_bool(sprite.centered).is_true()
	var bottom: float = sprite.offset.y + float(def.texture.get_height()) / 2.0 - float(def.base_inset())
	assert_float(bottom).is_equal(0.0)


func test_destroyed_in_one_hit() -> void:
	var prop: ForestProp = auto_free(ForestProp.new())
	var id := ForestProp.make_id(1, Vector2i(3, 4), 0)
	prop.setup(_make_def(), id)
	prop.on_hit_impact(Vector2(2, 2), Vector2.RIGHT)
	assert_bool(prop.is_queued_for_deletion()).is_true()
	assert_bool(ForestProp.is_destroyed(id)).is_true()


func test_destroyed_registry_is_per_seed() -> void:
	var id_seed1 := ForestProp.make_id(1, Vector2i(5, 5), 0)
	var id_seed2 := ForestProp.make_id(2, Vector2i(5, 5), 0)
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(), id_seed1)
	prop.on_hit_impact(Vector2(2, 2), Vector2.RIGHT)
	assert_bool(ForestProp.is_destroyed(id_seed1)).is_true()
	assert_bool(ForestProp.is_destroyed(id_seed2)).is_false()


func test_free_releases_nav_blocker() -> void:
	var wm: StubWM = auto_free(StubWM.new())
	wm.nav_field = StubNavField.new()
	wm.nav_field.grid = _PassabilityGrid.new(8, 256, PackedByteArray())
	wm.add_to_group("world_manager")
	add_child(wm)
	var rock_def := _make_def()
	rock_def.kind = "rock"
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(rock_def, "1:0:0:5")
	prop.global_position = Vector2(100, 100)
	add_child(prop)
	assert_bool(wm.nav_field.grid.is_solid_world(Vector2(100, 100))).is_true()
	prop.free()
	assert_bool(wm.nav_field.grid.is_solid_world(Vector2(100, 100))).is_false()
	# Trees never block: hittable only, not a body or nav obstacle.
	var tree: ForestProp = auto_free(ForestProp.new())
	tree.setup(_make_def(), "1:0:0:6")
	tree.global_position = Vector2(100, 100)
	add_child(tree)
	assert_int(tree.collision_layer).is_equal(128)
	assert_bool(wm.nav_field.grid.is_solid_world(Vector2(100, 100))).is_false()


func test_resolve_hit_passes_dig_power() -> void:
	var weapon: Weapon = Weapon.new()
	weapon.dig_power = 3.0
	var user: Node2D = auto_free(Node2D.new())
	user.global_position = Vector2.ZERO
	var target: DigTarget = auto_free(DigTarget.new())
	target.global_position = Vector2(20, 0)
	weapon.resolve_hit(user, target)
	assert_that(target.dig_calls.size()).is_equal(1)
	assert_float(target.dig_calls[0]["power"]).is_equal(3.0)
	assert_bool(target.impact_called).is_false()


func _make_tree() -> ForestProp:
	var tree: ForestProp = auto_free(ForestProp.new())
	tree.setup(_make_def(), "1:0:0:10")
	return tree


func test_canopy_area_only_on_trees() -> void:
	var area := _make_tree().get_node("CanopyArea") as Area2D
	assert_object(area).is_not_null()
	assert_int(area.collision_layer).is_equal(0)
	assert_int(area.collision_mask).is_equal(128)
	assert_bool(area.monitorable).is_false()
	var rock_def := _make_def()
	rock_def.kind = "rock"
	var rock: ForestProp = auto_free(ForestProp.new())
	rock.setup(rock_def, "1:0:0:11")
	assert_object(rock.get_node_or_null("CanopyArea")).is_null()


func test_fade_counts_occluders() -> void:
	var tree := _make_tree()
	var a: CharacterBody2D = auto_free(CharacterBody2D.new())
	var b: CharacterBody2D = auto_free(CharacterBody2D.new())
	tree._on_canopy_body_entered(a)
	tree._on_canopy_body_entered(b)
	assert_bool(tree.is_faded()).is_true()
	assert_float(tree.get_node("Sprite2D").self_modulate.a).is_equal_approx(ForestProp.FADE_ALPHA, 0.001)
	tree._on_canopy_body_exited(a)
	assert_bool(tree.is_faded()).is_true()
	tree._on_canopy_body_exited(b)
	assert_bool(tree.is_faded()).is_false()
	assert_float(tree.get_node("Sprite2D").self_modulate.a).is_equal(1.0)


func test_fade_ignores_props() -> void:
	var tree := _make_tree()
	var other: ForestProp = auto_free(ForestProp.new())
	other.setup(_make_def(), "1:0:0:12")
	tree._on_canopy_body_entered(other)
	assert_bool(tree.is_faded()).is_false()


func test_hit_flash_keeps_fade() -> void:
	var tree := _make_tree()
	tree._on_canopy_body_entered(auto_free(CharacterBody2D.new()))
	tree.take_dig_hit(Vector2(4, 4), Vector2.RIGHT, 0.0)
	assert_float(tree.get_node("Sprite2D").self_modulate.a).is_equal_approx(ForestProp.FADE_ALPHA, 0.001)
