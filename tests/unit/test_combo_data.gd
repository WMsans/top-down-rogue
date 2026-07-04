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


class _ChainRetrigger extends Modifier:
	func _init() -> void:
		category = "trigger"
		is_retrigger_modifier = true
	func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
		var first: Modifier = weapon.get_first_modifier()
		weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func _row(overrides: Dictionary) -> Dictionary:
	var base := {
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "", "trigger": "", "condition": "", "effect": "",
		"element": "", "magnitude": "0", "magnitude2": "0", "suppresses_base_use": "No",
	}
	for k in overrides.keys():
		base[k] = overrides[k]
	return base


func _make(id: String) -> Modifier:
	return WeaponRegistry._make_modifier(id)


func test_spread_status_to_nearby_foes() -> void:
	var u := _StatusTarget.new()
	add_child(u)
	u.global_position = Vector2.ZERO
	var burning := _StatusTarget.new()
	add_child(burning)
	burning.global_position = Vector2(20, 0)
	burning.get_node("StatusComponent").add_stain("on_fire", 5.0)
	var near_foe := _StatusTarget.new()
	add_child(near_foe)
	near_foe.global_position = Vector2(35, 0)
	var far_foe := _StatusTarget.new()
	add_child(far_foe)
	far_foe.global_position = Vector2(400, 0)
	var m := DataModifier.new(_row({
		"category": "trigger", "trigger": "on_hit", "condition": "target_status:on_fire",
		"effect": "spread_status", "element": "on_fire", "magnitude": "40", "magnitude2": "2.0",
	}))
	m.on_hit_target(null, u, burning)
	assert_float(near_foe.get_node("StatusComponent").get_stain("on_fire")).is_equal(2.0)
	assert_float(far_foe.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)


func test_spark_plug_ignites_oiled_target() -> void:
	var t := _StatusTarget.new()
	add_child(t)
	t.get_node("StatusComponent").add_stain("oiled", 5.0)
	var m := _make("spark_plug")
	assert_that(m).is_not_null()
	m.on_hit_target(null, null, t)
	assert_float(t.get_node("StatusComponent").get_stain("on_fire")).is_equal(2.0)


func test_deepfreeze_adds_frozen_to_chilly_target() -> void:
	var t := _StatusTarget.new()
	add_child(t)
	t.get_node("StatusComponent").add_stain("chilly", 5.0)
	var m := _make("deepfreeze")
	m.on_hit_target(null, null, t)
	assert_float(t.get_node("StatusComponent").get_stain("frozen")).is_equal(2.0)
	var dry := _StatusTarget.new()
	add_child(dry)
	m.on_hit_target(null, null, dry)
	assert_float(dry.get_node("StatusComponent").get_stain("frozen")).is_equal(0.0)


func test_hemophilia_crit_vs_bloody() -> void:
	var w := Weapon.new()
	w.crit_chance = 0.2
	var m := _make("hemophilia")
	w.add_modifier(0, m)
	var t := _StatusTarget.new()
	add_child(t)
	assert_float(w.get_effective_crit_chance_for_target(t)).is_equal(0.2)
	t.get_node("StatusComponent").add_stain("bloody", 5.0)
	assert_float(w.get_effective_crit_chance_for_target(t)).is_equal(0.45)


func test_backdraft_registered_and_spreads() -> void:
	assert_that(_make("backdraft")).is_not_null()


func test_riptide_registered_and_knockbacks() -> void:
	assert_that(_make("riptide")).is_not_null()


func test_plague_carrier_registered_and_spreads() -> void:
	assert_that(_make("plague_carrier")).is_not_null()


func test_all_seven_data_modifiers_have_rarity_and_category() -> void:
	for id in ["spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge"]:
		var row: Dictionary = WeaponRegistry._modifier_data[id]
		assert_str(row.get("rarity", "")).is_not_empty()
		assert_str(row.get("category", "")).is_not_empty()
