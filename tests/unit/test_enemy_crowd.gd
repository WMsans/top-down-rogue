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
