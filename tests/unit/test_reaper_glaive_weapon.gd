extends GdUnitTestSuite

const ReaperGlaive = preload("res://src/weapons/reaper_glaive_weapon.gd")

class _Inv extends Node:
	var healed: int = 0
	func _init() -> void:
		name = "PlayerInventory"
	func heal(amount: int) -> void:
		healed += amount

func test_kill_heals_player() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var inv := _Inv.new()
	user.add_child(inv)
	var w := ReaperGlaive.new()
	w._native_on_kill(user, null)
	assert_int(inv.healed).is_equal(ReaperGlaive.REAP_HEAL)

func test_long_reach() -> void:
	var w := ReaperGlaive.new()
	assert_float(w.weapon_reach).is_greater(40.0)
