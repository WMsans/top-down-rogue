extends GdUnitTestSuite

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


class _HpUser extends Node2D:
	var health: float = 10.0
	var max_health: float = 10.0


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


func _row(overrides: Dictionary) -> Dictionary:
	var base := {
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "", "trigger": "", "condition": "", "effect": "",
		"element": "", "magnitude": "0", "magnitude2": "0", "suppresses_base_use": "No",
	}
	for k in overrides.keys():
		base[k] = overrides[k]
	return base


func test_last_stand_boosts_first_hit_after_damage() -> void:
	var u := _HpUser.new()
	add_child(u)
	var w := Weapon.new()
	var m := LastStandModifier.new()
	w.add_modifier(0, m)
	var t := Node.new()
	assert_float(m.modify_hit_damage(w, u, t, 10.0)).is_equal(10.0)
	u.health = 5.0
	assert_float(m.modify_hit_damage(w, u, t, 10.0)).is_equal(16.0)
	u.health = 5.0
	assert_float(m.modify_hit_damage(w, u, t, 10.0)).is_equal(10.0)


func test_overkill_carries_excess_to_next_target() -> void:
	var w := Weapon.new()
	var m := OverkillModifier.new()
	w.add_modifier(0, m)
	var a := _HpTarget.new(5.0)
	add_child(a)
	var b := _HpTarget.new(20.0)
	add_child(b)
	assert_float(m.modify_hit_damage(w, null, a, 10.0)).is_equal(10.0)
	m.on_kill(w, null, a)
	assert_float(m.modify_hit_damage(w, null, b, 4.0)).is_equal(9.0)


func test_evolving_edge_doubles_after_fifteen_hits() -> void:
	var m := EvolvingEdgeModifier.new()
	assert_float(m.get_stat_add("damage")).is_equal(2.0)
	for i in range(15):
		m.on_hit_target(null, null, null)
	assert_float(m.get_stat_add("damage")).is_equal(4.0)
	assert_float(m.get_stat_add("cooldown")).is_equal(0.0)


func test_slot_harmony_boosts_when_all_categories_distinct() -> void:
	var w := Weapon.new()
	var a := DataModifier.new(_row({"category": "stat"}))
	var b := DataModifier.new(_row({"category": "status"}))
	var h := SlotHarmonyModifier.new()
	w.add_modifier(0, a); w.add_modifier(1, b); w.add_modifier(2, h)
	var t := Node.new()
	assert_float(h.modify_hit_damage(w, null, t, 10.0)).is_equal(12.0)


func test_slot_harmony_no_boost_when_duplicate_category() -> void:
	var w := Weapon.new()
	var a := DataModifier.new(_row({"category": "stat"}))
	var b := DataModifier.new(_row({"category": "stat"}))
	var h := SlotHarmonyModifier.new()
	w.add_modifier(0, a); w.add_modifier(1, b); w.add_modifier(2, h)
	var t := Node.new()
	assert_float(h.modify_hit_damage(w, null, t, 10.0)).is_equal(10.0)


func test_slot_harmony_no_boost_when_slot_empty() -> void:
	var w := Weapon.new()
	var a := DataModifier.new(_row({"category": "stat"}))
	var h := SlotHarmonyModifier.new()
	w.add_modifier(0, a); w.add_modifier(2, h)
	var t := Node.new()
	assert_float(h.modify_hit_damage(w, null, t, 10.0)).is_equal(10.0)
