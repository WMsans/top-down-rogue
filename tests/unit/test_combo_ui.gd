extends GdUnitTestSuite

class _HitCounter extends Modifier:
	var on_hit_calls: int = 0
	var dmg_seen: float = 0.0
	func _init() -> void:
		category = "trigger"
	func on_hit_target(_w, _u, _t) -> void:
		on_hit_calls += 1
	func modify_hit_damage(_w, _u, _t, dmg: float) -> float:
		dmg_seen = dmg
		return dmg


func test_modifier_state_tag_reflects_disabled_and_retrigger() -> void:
	var c := _HitCounter.new()
	assert_str(c.get_state_tag()).is_equal("")
	c.is_disabled = true
	assert_str(c.get_state_tag()).is_equal("disabled")
	c.is_disabled = false
	c.is_retrigger_modifier = true
	assert_str(c.get_state_tag()).is_equal("retrigger")


func test_catalyst_bond_state_tag_is_linked() -> void:
	var m := CatalystBondModifier.new()
	assert_str(m.get_state_tag()).is_equal("linked")
