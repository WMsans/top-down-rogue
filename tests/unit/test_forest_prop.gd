extends GdUnitTestSuite

const _PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")

# Stub world_manager for ForestProp: nav grid via nav_field.grid. get_chunk_container
# and chunks_generated satisfy the SpawnDispatcher/CompositionDispatcher autoloads,
# which adopt any node in the "world_manager" group.
class StubNavField extends RefCounted:
	var grid

class StubWM extends Node:
	var nav_field
	var entity_layer: Node2D = null

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


# 16 x height opaque texture whose bottom 3 rows are fully transparent.
func _make_def(height: int = 32) -> ForestPropDef:
	var img := Image.create(16, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.4, 0.2, 1.0))
	for y in range(height - 3, height):
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
	tree.setup(_make_def(64), "1:0:0:10")
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


func test_canopy_and_band_split_at_trunk_band() -> void:
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(64), "1:0:0:20")
	var canopy := prop.get_node("Sprite2D") as Sprite2D
	assert_bool(canopy.region_enabled).is_true()
	assert_that(canopy.region_rect).is_equal(Rect2(0, 0, 16, 29))
	assert_float(canopy.offset.y + canopy.region_rect.size.y).is_equal(-float(ForestProp.TRUNK_BAND))
	var band := prop.get_node("TrunkBand") as Sprite2D
	assert_that(band.region_rect).is_equal(Rect2(0, 29, 16, 32))
	assert_float(band.offset.y + band.region_rect.size.y).is_equal(0.0)
	assert_float(band.offset.x).is_equal(-8.0)
	assert_bool(band.z_as_relative).is_false()
	assert_int(band.z_index).is_equal(0)


func test_short_prop_has_band_only() -> void:
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(), "1:0:0:21")
	assert_object(prop.get_node_or_null("Sprite2D")).is_null()
	var band := prop.get_node("TrunkBand") as Sprite2D
	assert_that(band.region_rect).is_equal(Rect2(0, 0, 16, 29))


func test_shadow_child() -> void:
	var def := _make_def()
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(def, "1:0:0:22")
	var shadow := prop.get_node("Shadow") as Sprite2D
	assert_bool(shadow.z_as_relative).is_false()
	assert_int(shadow.z_index).is_equal(-9)
	var drawn := Vector2(shadow.texture.get_size()) * shadow.scale
	assert_that(drawn).is_equal(ForestProp.shadow_size(def))


func test_shadow_darkness() -> void:
	var def := _make_def()  # trunk_radius 6 -> 24x12 oval
	assert_that(ForestProp.shadow_size(def)).is_equal(Vector2(24, 12))
	assert_float(ForestProp.shadow_darkness(def, Vector2.ZERO)).is_equal_approx(0.6, 0.001)
	assert_float(ForestProp.shadow_darkness(def, Vector2(12, 0))).is_equal_approx(0.0, 0.001)
	assert_float(ForestProp.shadow_darkness(def, Vector2(6, 0))).is_equal_approx(0.3, 0.001)
	assert_float(ForestProp.shadow_darkness(def, Vector2(0, 30))).is_equal(0.0)


func test_is_in_front() -> void:
	var def := _make_def()  # 16 px wide
	assert_bool(ForestProp.is_in_front(def, Vector2(0, 4), 8.0)).is_true()
	assert_bool(ForestProp.is_in_front(def, Vector2(0, -2), 8.0)).is_false()
	assert_bool(ForestProp.is_in_front(def, Vector2(0, 12), 8.0)).is_false()
	assert_bool(ForestProp.is_in_front(def, Vector2(9, 4), 8.0)).is_false()


func _wm_with_layer() -> StubWM:
	var wm: StubWM = auto_free(StubWM.new())
	wm.entity_layer = Node2D.new()
	wm.entity_layer.y_sort_enabled = true
	wm.add_child(wm.entity_layer)
	wm.add_to_group("world_manager")
	add_child(wm)
	return wm


func test_band_in_entity_layer_and_freed_with_prop() -> void:
	var wm := _wm_with_layer()
	var prop := ForestProp.new()
	prop.setup(_make_def(64), "1:0:0:23")
	prop.position = Vector2(100, 100)
	add_child(prop)
	assert_int(wm.entity_layer.get_child_count()).is_equal(1)
	var band := wm.entity_layer.get_child(0) as Sprite2D
	assert_str(band.name).is_equal("TrunkBand")
	assert_that(band.global_position).is_equal(Vector2(100, 100))
	prop.free()
	await await_idle_frame()
	assert_int(wm.entity_layer.get_child_count()).is_equal(0)
	wm.remove_from_group("world_manager")


func test_band_freed_on_destroy() -> void:
	var wm := _wm_with_layer()
	var prop := ForestProp.new()
	prop.setup(_make_def(64), "1:0:0:24")
	# Impact particles parent to the prop's parent, which must be a Node2D.
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	host.add_child(prop)
	prop.on_hit_impact(Vector2(2, 2), Vector2.RIGHT)
	await await_millis(int(ForestProp.POP_TIME * 1000) + 150)
	assert_int(wm.entity_layer.get_child_count()).is_equal(0)
	wm.remove_from_group("world_manager")


func test_band_follows_fade() -> void:
	var tree := _make_tree()
	tree._on_canopy_body_entered(auto_free(CharacterBody2D.new()))
	assert_float(tree.get_node("TrunkBand").self_modulate.a).is_equal_approx(ForestProp.FADE_ALPHA, 0.001)
