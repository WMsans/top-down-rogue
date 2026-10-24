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

# ForestProp with an injectable clock and a counting dust hook, so the
# rate-limit can be tested without real time or the terrain surface.
class DustProp extends ForestProp:
	var dust_calls: int = 0
	var fake_now: float = 0.0

	func _emit_dust(_pos: Vector2, _dir: Vector2) -> void:
		dust_calls += 1

	func _now() -> float:
		return fake_now

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


func test_dig_scales_damage() -> void:
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(), "1:0:0:2")
	assert_float(prop.hp).is_equal(10.0)
	prop.take_dig_hit(Vector2(4, 4), Vector2.RIGHT, 3.0)
	assert_float(prop.hp).is_equal(7.5)
	prop.on_hit_impact(Vector2(4, 4), Vector2.RIGHT)
	assert_float(prop.hp).is_equal(6.5)


func test_free_carve_dig_is_capped() -> void:
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(), "1:0:0:3")
	prop.take_dig_hit(Vector2(4, 4), Vector2.RIGHT, 1.0e9)
	# DIG_CAP 6.0 * DIG_WEIGHT 0.5 + base 1.0 == exactly 4.0 damage dealt.
	assert_float(prop.hp).is_equal(6.0)


func test_destroyed_when_hp_depleted() -> void:
	var prop: ForestProp = auto_free(ForestProp.new())
	var id := ForestProp.make_id(1, Vector2i(3, 4), 0)
	prop.setup(_make_def(), id)
	prop.hp = 2.0
	prop.take_dig_hit(Vector2(2, 2), Vector2.RIGHT, 6.0)
	assert_bool(prop.is_queued_for_deletion()).is_true()
	assert_bool(ForestProp.is_destroyed(id)).is_true()


func test_destroyed_registry_is_per_seed() -> void:
	var id_seed1 := ForestProp.make_id(1, Vector2i(5, 5), 0)
	var id_seed2 := ForestProp.make_id(2, Vector2i(5, 5), 0)
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(), id_seed1)
	prop.hp = 2.0
	prop.take_dig_hit(Vector2(2, 2), Vector2.RIGHT, 6.0)
	assert_bool(ForestProp.is_destroyed(id_seed1)).is_true()
	assert_bool(ForestProp.is_destroyed(id_seed2)).is_false()


func test_dust_rate_limited() -> void:
	var prop: DustProp = auto_free(DustProp.new())
	prop.setup(_make_def(), "1:0:0:4")
	prop.take_dig_hit(Vector2(2, 2), Vector2.RIGHT, 0.0)
	prop.take_dig_hit(Vector2(2, 2), Vector2.RIGHT, 0.0)
	assert_that(prop.dust_calls).is_equal(1)
	prop.fake_now = prop.DUST_COOLDOWN
	prop.take_dig_hit(Vector2(2, 2), Vector2.RIGHT, 0.0)
	assert_that(prop.dust_calls).is_equal(2)


func test_free_releases_nav_blocker() -> void:
	var wm: StubWM = auto_free(StubWM.new())
	wm.nav_field = StubNavField.new()
	wm.nav_field.grid = _PassabilityGrid.new(8, 256, PackedByteArray())
	wm.add_to_group("world_manager")
	add_child(wm)
	var prop: ForestProp = auto_free(ForestProp.new())
	prop.setup(_make_def(), "1:0:0:5")
	prop.global_position = Vector2(100, 100)
	add_child(prop)
	assert_bool(wm.nav_field.grid.is_solid_world(Vector2(100, 100))).is_true()
	prop.free()
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
