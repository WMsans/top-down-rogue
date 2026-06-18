extends GdUnitTestSuite


class _AddMod extends Modifier:
	var stat: String
	var amount: float
	func _init(s: String, a: float) -> void:
		stat = s; amount = a
	func get_stat_add(s: String) -> float:
		return amount if s == stat else 0.0


class _MultMod extends Modifier:
	var stat: String
	var factor: float
	func _init(s: String, f: float) -> void:
		stat = s; factor = f
	func get_stat_mult(s: String) -> float:
		return factor if s == stat else 1.0


func test_add_then_mult_order() -> void:
	var w: Weapon = Weapon.new()
	w.damage = 10.0
	w.modifiers = [_AddMod.new("damage", 3.0), _MultMod.new("damage", 2.0), null]
	assert_that(w.get_effective_stats()["damage"]).is_equal(26.0)


func test_cooldown_floor() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 0.2
	w.modifiers = [_MultMod.new("cooldown", 0.1), null, null]
	assert_that(w.get_effective_stats()["cooldown"]).is_equal(0.1)


func test_cache_invalidates_on_modifier_change() -> void:
	var w: Weapon = Weapon.new()
	w.damage = 5.0
	assert_that(w.get_effective_stats()["damage"]).is_equal(5.0)
	w.add_modifier(0, _AddMod.new("damage", 4.0))
	assert_that(w.get_effective_stats()["damage"]).is_equal(9.0)


func test_use_sets_cooldown_from_effective() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 1.0
	w.modifiers = [_MultMod.new("cooldown", 0.8), null, null]
	w.use(null)               # base use_impl is a no-op; only the timer matters
	assert_that(w.is_ready()).is_false()    # 0.8s pending, > 0
	w.tick(0.79)
	assert_that(w.is_ready()).is_false()
	w.tick(0.02)
	assert_that(w.is_ready()).is_true()


func test_melee_seeds_reach_and_arc() -> void:
	var m: MeleeWeapon = MeleeWeapon.new()
	m.weapon_reach = 30.0
	m.arc_angle = PI / 2.0
	var s := m.get_effective_stats()
	assert_that(s["reach"]).is_equal(30.0)
	assert_that(s["arc"]).is_equal(PI / 2.0)
