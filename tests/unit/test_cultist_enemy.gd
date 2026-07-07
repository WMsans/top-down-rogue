extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var nav_field = null

class WoundedAlly extends Node2D:
	var health: int = 5
	var max_health: int = 20
	signal health_changed(current: int, maximum: int)


func _cultist_with_world() -> Dictionary:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: CultistEnemy = auto_free(CultistEnemy.new())
	add_child(e)
	e._world_manager = world
	e.global_position = Vector2.ZERO
	return {"world": world, "cultist": e}


func test_cultist_has_reduced_health() -> void:
	var e: CultistEnemy = auto_free(CultistEnemy.new())
	add_child(e)
	assert_int(e.max_health).is_equal(12)


func test_cultist_does_not_wander_independently() -> void:
	var e: CultistEnemy = auto_free(CultistEnemy.new())
	add_child(e)
	assert_bool(e.wander_enabled).is_false()


func test_cultist_heals_wounded_ally_in_radius() -> void:
	var ctx := _cultist_with_world()
	var world: FakeWorld = ctx["world"]
	var e: CultistEnemy = ctx["cultist"]
	var ally: WoundedAlly = auto_free(WoundedAlly.new())
	add_child(ally)
	ally.global_position = Vector2(50, 0)
	world.swarm_grid.rebuild([e, ally])
	e._heal_timer = 0.0
	e._process_idle(0.016)
	assert_int(ally.health).is_equal(9)


func test_cultist_ignores_full_health_ally() -> void:
	var ctx := _cultist_with_world()
	var world: FakeWorld = ctx["world"]
	var e: CultistEnemy = ctx["cultist"]
	var ally: WoundedAlly = auto_free(WoundedAlly.new())
	add_child(ally)
	ally.global_position = Vector2(50, 0)
	ally.health = 20
	world.swarm_grid.rebuild([e, ally])
	e._heal_timer = 0.0
	e._process_idle(0.016)
	assert_int(ally.health).is_equal(20)


func test_cultist_respects_cooldown() -> void:
	var ctx := _cultist_with_world()
	var world: FakeWorld = ctx["world"]
	var e: CultistEnemy = ctx["cultist"]
	var ally: WoundedAlly = auto_free(WoundedAlly.new())
	add_child(ally)
	ally.global_position = Vector2(50, 0)
	world.swarm_grid.rebuild([e, ally])
	e._heal_timer = 0.0
	e._process_idle(0.016)
	var healed_once: int = ally.health
	e._process_idle(0.016)
	assert_int(ally.health).is_equal(healed_once)


func test_scene_instantiates_as_cultist_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/cultist_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is CultistEnemy).is_true()
