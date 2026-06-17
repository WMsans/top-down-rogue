extends GdUnitTestSuite

const QuakeHammer = preload("res://src/weapons/quake_hammer_weapon.gd")

class _Foe extends Node2D:
	var knocked: bool = false
	func _init() -> void:
		add_to_group("attackable")
	func apply_knockback(_dir: Vector2, _strength: float) -> void:
		knocked = true

class Probe extends QuakeHammer:
	var shockwaves: int = 0
	func _play_move(_move, _user) -> void:
		pass                       # skip physics/animation
	func _emit_shockwave(_user) -> void:
		shockwaves += 1

func test_shockwave_knocks_back_nearby_attackables() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var foe: _Foe = _Foe.new()
	user.add_child(foe)
	foe.global_position = Vector2(20, 0)
	var w: QuakeHammer = QuakeHammer.new()
	w._emit_shockwave(user)
	assert_bool(foe.knocked).is_true()

func test_charged_release_emits_shockwave_tap_does_not() -> void:
	var w := Probe.new()
	w.on_press(null)
	w._tick_impl(2.0)              # full charge
	w.on_release(null)
	assert_int(w.shockwaves).is_equal(1)

	var w2 := Probe.new()
	w2.on_press(null)
	w2._tick_impl(0.05)           # tap
	w2.on_release(null)
	assert_int(w2.shockwaves).is_equal(0)
