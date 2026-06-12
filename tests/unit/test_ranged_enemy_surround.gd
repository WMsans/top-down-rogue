extends GdUnitTestSuite

const _Director = preload("res://src/core/encounter_director.gd")

class MockRangedEnemy extends RangedEnemy:
	var can_see: bool = true
	func _can_see_player() -> bool:
		return can_see


func test_ranged_uses_ranged_token_pool() -> void:
	var e: RangedEnemy = auto_free(RangedEnemy.new())
	assert_bool(e._uses_ranged_token()).is_true()


func test_ranged_holds_when_no_ranged_token() -> void:
	var d: EncounterDirector = _Director.new()
	d.ranged_token_count = 1
	var holder: MockRangedEnemy = auto_free(MockRangedEnemy.new())
	add_child(holder)
	holder._director = d
	d._active = [holder]
	holder._try_claim_attack()
	var e: MockRangedEnemy = auto_free(MockRangedEnemy.new())
	add_child(e)
	e._director = d
	e._aggroed = true
	d._active = [holder, e]
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 200.0
	e.preferred_distance = 120.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._state = Enemy.State.CHASE
	e._player_in_range = true
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)


func test_ranged_attacks_with_ranged_token() -> void:
	var d: EncounterDirector = _Director.new()
	d.ranged_token_count = 1
	var e: MockRangedEnemy = auto_free(MockRangedEnemy.new())
	add_child(e)
	e._director = d
	e._aggroed = true
	d._active = [e]
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 200.0
	e.preferred_distance = 120.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._state = Enemy.State.CHASE
	e._player_in_range = true
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WINDUP)
