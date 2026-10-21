extends GdUnitTestSuite

class _Target extends Node2D:
	var hits_remaining: int = 1
	var hit_count: int = 0
	var invulnerable: bool = false
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func is_hit_invulnerable() -> bool:
		return invulnerable
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hit_count += 1
		hits_remaining -= 1

class _EdgeMod extends Modifier:
	func on_hit_target(_w, _u, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("poisoned", 2.0)

class _KillCounter extends Modifier:
	var kills: int = 0
	func on_kill(_w, _u, _t) -> void:
		kills += 1

func _target() -> _Target:
	var t := _Target.new()
	add_child(t)
	return auto_free(t)

func test_resolve_hit_lands_exactly_one_hit() -> void:
	var w := Weapon.new()
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t)
	assert_int(t.hit_count).is_equal(1)
	assert_int(t.hits_remaining).is_equal(1)

func test_status_edge_applies() -> void:
	var w := Weapon.new()
	w.modifiers = [_EdgeMod.new(), null, null]
	var t := _target()
	w.resolve_hit(null, t)
	assert_that(t.get_node("StatusComponent").get_stain("poisoned")).is_greater(0.0)

func test_on_kill_fires_once_when_target_dies() -> void:
	var w := Weapon.new()
	var km := _KillCounter.new()
	w.modifiers = [km, null, null]
	var t := _target()
	t.hits_remaining = 1
	w.resolve_hit(null, t)   # kills
	w.resolve_hit(null, t)   # already dead -> no second kill
	assert_int(km.kills).is_equal(1)

func test_hit_count_advances() -> void:
	var w := Weapon.new()
	var t := _target()
	w.resolve_hit(null, t)
	w.resolve_hit(null, t)
	assert_int(w._hit_count).is_equal(2)

func test_hit_status_applied_on_every_hit() -> void:
	var w := Weapon.new()
	w.hit_status = "on_fire"
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal_approx(Weapon.HIT_STATUS_STAIN, 0.001)

func test_no_hit_status_by_default() -> void:
	var w := Weapon.new()
	var t := _target()
	t.hits_remaining = 2
	w.resolve_hit(null, t)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)

func test_resolve_hit_during_invuln_applies_no_status() -> void:
	var w := Weapon.new()
	w.hit_status = "on_fire"
	var kills := _KillCounter.new()
	w.add_modifier(0, kills)
	var t := _target()
	t.invulnerable = true
	w.resolve_hit(null, t)
	assert_int(t.hit_count).is_equal(0)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)
	assert_int(kills.kills).is_equal(0)
