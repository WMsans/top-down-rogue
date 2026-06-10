extends GdUnitTestSuite

# Mock enemy with controllable line-of-sight, matching the MockEnemy pattern in
# test_enemy_state_machine.gd.
class MockEnemy extends Enemy:
	var can_see: bool = true
	func _can_see_player() -> bool:
		return can_see

# Stub nav field: fixed sample direction, and solid when x >= solid_x.
class StubFlow:
	var dir: Vector2 = Vector2.ZERO
	var solid_x: float = 1.0e9
	func sample_direction(_p: Vector2) -> Vector2:
		return dir
	func is_solid_world(p: Vector2) -> bool:
		return p.x >= solid_x

# Stub world manager Node holding a nav_field and a null swarm_grid (so
# _apply_separation passes the direction through unchanged).
class StubWM extends Node:
	var nav_field
	var swarm_grid = null

func _make_enemy() -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	return e

func _make_player(e: MockEnemy, pos: Vector2) -> void:
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = pos

func test_follows_field_when_los_blocked() -> void:
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e._aggroed = true
	e.can_see = false
	_make_player(e, Vector2(50, 0))          # within leash, but unseen
	var flow := StubFlow.new()
	flow.dir = Vector2(0, 1)                  # field says go down (around a wall)
	var wm: StubWM = auto_free(StubWM.new())
	wm.nav_field = flow
	add_child(wm)
	e._world_manager = wm
	e._process_chase(0.1)
	assert_bool(e.velocity.y > 0.0).is_true()
	assert_float(absf(e.velocity.x)).is_less(1.0)

func test_direct_steer_when_seen() -> void:
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e.can_see = true
	_make_player(e, Vector2(100, 0))          # straight to the right
	e._world_manager = null                    # field unused when seen
	e._process_chase(0.1)
	assert_bool(e.velocity.x > 0.0).is_true()
	assert_float(absf(e.velocity.y)).is_less(1.0)

func test_persistent_aggro_past_leash() -> void:
	# Once aggroed, the enemy pursues forever — leash radius no longer applies.
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e._aggroed = true
	e.can_see = false
	e.leash_radius = 280.0
	_make_player(e, Vector2(400, 0))          # beyond old leash
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(e._aggroed).is_true()

func test_unseen_and_unaggroed_reverts() -> void:
	# Sight-to-acquire: a target never seen and currently blocked does not commit.
	var e := _make_enemy()
	e._state = Enemy.State.CHASE
	e._aggroed = false
	e.can_see = false
	_make_player(e, Vector2(50, 0))           # within leash but unseen, not aggroed
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WANDER)

func test_clamp_blocks_into_wall_allows_slide() -> void:
	var e := _make_enemy()
	e.global_position = Vector2(0, 0)
	e.velocity = Vector2(100, 100)            # heads into +x wall, +y open
	var flow := StubFlow.new()
	flow.solid_x = 8.0                         # anything x >= 8 is solid
	var wm: StubWM = auto_free(StubWM.new())
	wm.nav_field = flow
	add_child(wm)
	e._world_manager = wm
	e._move_with_clamp(0.1)                    # target (10,10): x blocked, y allowed
	assert_float(e.global_position.x).is_equal(0.0)
	assert_float(e.global_position.y).is_equal(10.0)
