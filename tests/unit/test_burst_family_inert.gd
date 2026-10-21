extends GdUnitTestSuite

# The burst modifier family (necrosis, combustion, frostshatter, rupture) is
# inert until Plan 3. Their old shape consumed a status and then burst a hit
# on the target (and, for frostshatter, on nearby enemies) - a real hit that
# the hit-count model no longer has a use for.

class _Target extends Node2D:
	var hits: int = 0
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hits += 1


func _target(stain_id: String, amount: float = 5.0) -> _Target:
	var t := _Target.new()
	add_child(t)
	t.get_node("StatusComponent").add_stain(stain_id, amount)
	return t


func test_weapon_has_no_burst_helper() -> void:
	assert_bool(Weapon.new().has_method("_apply_burst")).is_false()


func test_detonator_does_not_consume_status_or_hit() -> void:
	var t := _target("frozen")
	var m := DetonatorModifier.new()
	m.consumed_status = "frozen"
	m.on_hit_target(Weapon.new(), null, t)
	assert_int(t.hits).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("frozen")).is_greater(0.0)


func test_frostshatter_does_not_burst_target_or_neighbours() -> void:
	var t := _target("frozen")
	var neighbour := _target("frozen")
	neighbour.global_position = Vector2(20.0, 0.0)
	FrostshatterModifier.new().on_hit_target(Weapon.new(), null, t)
	assert_int(t.hits).is_equal(0)
	assert_int(neighbour.hits).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("frozen")).is_greater(0.0)


func test_rupture_does_not_burst() -> void:
	var t := _target("bloody")
	var m := RuptureModifier.new()
	for _i in range(5):  # the old bleed counter bursted on the 5th hit
		m.on_hit_target(Weapon.new(), null, t)
	assert_int(t.hits).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("bloody")).is_greater(0.0)


func test_necrosis_does_not_consume_poison() -> void:
	var t := _target("poisoned")
	NecrosisModifier.new().on_hit_target(Weapon.new(), null, t)
	assert_int(t.hits).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("poisoned")).is_greater(0.0)


func test_combustion_does_not_consume_fire() -> void:
	var t := _target("on_fire")
	CombustionModifier.new().on_hit_target(Weapon.new(), null, t)
	assert_int(t.hits).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_greater(0.0)
