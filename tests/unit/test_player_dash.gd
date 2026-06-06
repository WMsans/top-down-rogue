extends GdUnitTestSuite

const PlayerScript = preload("res://src/player/player_controller.gd")

func test_request_dash_sets_decaying_velocity() -> void:
	var p: PlayerController = auto_free(PlayerScript.new())
	p.request_dash(Vector2.RIGHT, 90.0)
	assert_float(p._dash_velocity.length()).is_equal_approx(90.0, 0.01)
	# Decays toward zero over time.
	p._decay_dash(0.1)
	assert_float(p._dash_velocity.length()).is_less(90.0)

func test_request_dash_ignores_zero_direction() -> void:
	var p: PlayerController = auto_free(PlayerScript.new())
	p.request_dash(Vector2.ZERO, 90.0)
	assert_float(p._dash_velocity.length()).is_equal_approx(0.0, 0.01)
