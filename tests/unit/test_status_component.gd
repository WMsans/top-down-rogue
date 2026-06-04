extends GdUnitTestSuite

const StatusComponentScript = preload("res://src/status/status_component.gd")

class FakeOwner extends Node:
	var taken: int = 0
	func apply_status_damage(amount: int) -> void:
		taken += amount

func _make_comp(owner: Node) -> StatusComponent:
	var c: StatusComponent = StatusComponentScript.new()
	owner.add_child(c)
	return c

func test_add_and_get_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 2.5)
	assert_float(c.get_stain("wet")).is_equal_approx(2.5, 0.001)

func test_has_status_threshold() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 0.5)
	assert_that(c.has_status("on_fire")).is_false()
	c.add_stain("on_fire", 1.0)  # total 1.5 >= 1.0
	assert_that(c.has_status("on_fire")).is_true()

func test_decay_reduces_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 5.0)  # decay_rate 0.5
	c.tick(1.0)
	assert_float(c.get_stain("wet")).is_equal_approx(4.5, 0.001)

func test_frozen_blocks_movement() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("frozen", 5.0)
	assert_that(c.is_movement_blocked()).is_true()
	assert_float(c.get_move_speed_multiplier()).is_equal_approx(0.0, 0.001)

func test_chilly_slows_movement() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("chilly", 2.0)
	assert_that(c.is_movement_blocked()).is_false()
	assert_float(c.get_move_speed_multiplier()).is_equal_approx(0.6, 0.001)

func test_burn_calls_owner_damage() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 5.0)  # burn_dps 4
	c.tick(1.0)  # decay -1 -> 4 (still active); burn 4*1=4 delivered
	assert_that(owner.taken).is_equal(4)

func test_active_ids_lists_active_only() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 2.0)
	c.add_stain("on_fire", 0.2)  # below threshold
	var ids: Array = c.get_active_ids()
	assert_that(ids.has("wet")).is_true()
	assert_that(ids.has("on_fire")).is_false()
