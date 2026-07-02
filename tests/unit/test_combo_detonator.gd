extends GdUnitTestSuite

class _StatusTarget extends Node2D:
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)


class _HpTarget extends Node2D:
	var health: float
	var max_health: float
	var impacts: Array = []
	func _init(h: float = 100.0) -> void:
		health = h
		max_health = h
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		health -= float(dmg)
		impacts.append(dmg)


func test_frostshatter_consumes_frozen_and_bursts() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	user.global_position = Vector2.ZERO
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.global_position = Vector2(30, 0)
	t.get_node("StatusComponent").add_stain("frozen", 5.0)
	var m := FrostshatterModifier.new()
	m.on_hit_target(Weapon.new(), user, t)
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(40)
	assert_float(t.get_node("StatusComponent").get_stain("frozen")).is_equal(0.0)


func test_frostshatter_no_burst_below_threshold() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("frozen", 1.0)
	var m := FrostshatterModifier.new()
	m.on_hit_target(Weapon.new(), user, t)
	assert_int(t.impacts.size()).is_equal(0)


func test_combustion_consumes_fire_and_bursts_x3() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("on_fire", 4.0)
	var m := CombustionModifier.new()
	m.on_hit_target(Weapon.new(), user, t)
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(12)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)


func test_necrosis_consumes_poison_and_bursts_x2() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var t := _HpTarget.new(100.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("poisoned", 3.0)
	var m := NecrosisModifier.new()
	m.on_hit_target(Weapon.new(), user, t)
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(6)
	assert_float(t.get_node("StatusComponent").get_stain("poisoned")).is_equal(0.0)


func test_rupture_bursts_after_five_bloody_hits() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var w := Weapon.new()
	w.damage = 6.0
	var t := _HpTarget.new(1000.0)
	add_child(t)
	t.get_node("StatusComponent").add_stain("bloody", 5.0)
	var m := RuptureModifier.new()
	w.add_modifier(0, m)
	for i in range(4):
		m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(0)
	m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(1)
	assert_int(t.impacts[0]).is_equal(30)
	m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(1)


func test_rupture_ignores_non_bloody_hits() -> void:
	var user := _StatusTarget.new()
	add_child(user)
	var w := Weapon.new()
	w.damage = 6.0
	var t := _HpTarget.new(1000.0)
	add_child(t)
	var m := RuptureModifier.new()
	w.add_modifier(0, m)
	for i in range(10):
		m.on_hit_target(w, user, t)
	assert_int(t.impacts.size()).is_equal(0)
