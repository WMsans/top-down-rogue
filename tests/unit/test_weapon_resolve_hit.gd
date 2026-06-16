extends GdUnitTestSuite

class _Target extends Node2D:
	var health: float = 10.0
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		health -= dmg

class _DoubleDmg extends Modifier:
	func modify_hit_damage(_w, _u, _t, dmg: float) -> float:
		return dmg * 2.0

class _EdgeMod extends Modifier:
	func on_hit_target(_w, _u, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("poisoned", 2.0)

class _KillCounter extends Modifier:
	var kills: int = 0
	func on_kill(_w, _u, _t) -> void:
		kills += 1

class _CritCounter extends Modifier:
	var crits: int = 0
	func on_crit(_w, _u, _t) -> void:
		crits += 1

func _target() -> _Target:
	var t := _Target.new()
	add_child(t)
	return auto_free(t)

func test_crit_multiplier_applied() -> void:
	var w := Weapon.new()
	w.crit_multiplier = 2.0
	var t := _target()
	w.resolve_hit(null, t, 5.0, true)
	assert_int(t.hits[0]).is_equal(10)

func test_conditional_multiplier_folds() -> void:
	var w := Weapon.new()
	w.modifiers = [_DoubleDmg.new(), null, null]
	var t := _target()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(t.hits[0]).is_equal(10)

func test_status_edge_applies() -> void:
	var w := Weapon.new()
	w.modifiers = [_EdgeMod.new(), null, null]
	var t := _target()
	w.resolve_hit(null, t, 1.0, false)
	assert_that(t.get_node("StatusComponent").get_stain("poisoned")).is_greater(0.0)

func test_on_kill_fires_once_when_target_dies() -> void:
	var w := Weapon.new()
	var km := _KillCounter.new()
	w.modifiers = [km, null, null]
	var t := _target()
	t.health = 4.0
	w.resolve_hit(null, t, 5.0, false)   # kills
	w.resolve_hit(null, t, 5.0, false)   # already dead -> no second kill
	assert_int(km.kills).is_equal(1)

func test_hit_count_advances() -> void:
	var w := Weapon.new()
	var t := _target()
	w.resolve_hit(null, t, 1.0, false)
	w.resolve_hit(null, t, 1.0, false)
	assert_int(w._hit_count).is_equal(2)

func test_on_crit_hook_fires_on_crit() -> void:
	var w := Weapon.new()
	var cm := _CritCounter.new()
	w.modifiers = [cm, null, null]
	var t := _target()
	w.resolve_hit(null, t, 5.0, true)
	assert_int(cm.crits).is_equal(1)

func test_on_crit_hook_silent_on_non_crit() -> void:
	var w := Weapon.new()
	var cm := _CritCounter.new()
	w.modifiers = [cm, null, null]
	var t := _target()
	w.resolve_hit(null, t, 5.0, false)
	assert_int(cm.crits).is_equal(0)
