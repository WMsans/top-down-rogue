extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var nav_field = null

class FakeNavField extends RefCounted:
	var wall_x: float = 1.0e20
	func is_solid_world(pos: Vector2) -> bool:
		return pos.x >= wall_x


func test_separation_steers_away_from_dense_cluster() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.global_position = Vector2.ZERO
	e._world_manager = world
	e.separation_radius = 22.0
	var c1: MockEnemy = auto_free(MockEnemy.new())
	c1.global_position = Vector2(10, 0)
	var c2: MockEnemy = auto_free(MockEnemy.new())
	c2.global_position = Vector2(12, 3)
	var c3: MockEnemy = auto_free(MockEnemy.new())
	c3.global_position = Vector2(12, -3)
	world.swarm_grid.rebuild([e, c1, c2, c3])
	var result: Vector2 = e._apply_separation(Vector2.RIGHT)
	assert_bool(result.x < 0.0).is_true()


func test_depenetration_separates_stacked_enemies() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(2, 0)  # heavily overlapping (< 16px min spacing)
	for _i in range(80):
		world.swarm_grid.rebuild([a, b])
		a._resolve_crowd_overlap()
		b._resolve_crowd_overlap()
	# Two 8px-radius bodies converge toward 16px centre distance.
	var d := a.global_position.distance_to(b.global_position)
	assert_float(d).is_greater_equal(15.0)


func test_depenetration_splits_coincident_enemies() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a.global_position = Vector2.ZERO
	b.global_position = Vector2.ZERO  # exactly coincident
	for _i in range(80):
		world.swarm_grid.rebuild([a, b])
		a._resolve_crowd_overlap()
		b._resolve_crowd_overlap()
	var d := a.global_position.distance_to(b.global_position)
	assert_float(d).is_greater(1.0)


func test_depenetration_respects_walls() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	world.nav_field = FakeNavField.new()
	world.nav_field.wall_x = 10.0  # solid at x >= 10
	var a: MockEnemy = auto_free(MockEnemy.new())
	var b: MockEnemy = auto_free(MockEnemy.new())
	a._world_manager = world
	b._world_manager = world
	a.global_position = Vector2(0, 0)
	b.global_position = Vector2(-3, 0)  # pushes a toward the +X wall
	world.swarm_grid.rebuild([a, b])
	a._resolve_crowd_overlap()
	# a's leading edge (radius 8) + push would cross x=10, so the push is blocked.
	assert_float(a.global_position.x).is_less_equal(0.001)
