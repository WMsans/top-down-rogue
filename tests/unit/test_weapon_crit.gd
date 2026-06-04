extends GdUnitTestSuite

const WeaponScript = preload("res://src/weapons/weapon.gd")
const ModifierScript = preload("res://src/weapons/modifier.gd")

class PlusCritModifier extends Modifier:
	func modify_crit_chance(_weapon, base: float) -> float:
		return base + 0.2

func test_default_crit_fields() -> void:
	var w: Weapon = WeaponScript.new()
	assert_float(w.crit_chance).is_equal_approx(0.0, 0.001)
	assert_float(w.crit_multiplier).is_equal_approx(2.0, 0.001)
	assert_that(w.crit_status).is_equal("")

func test_effective_crit_chance_base() -> void:
	var w: Weapon = WeaponScript.new()
	w.crit_chance = 0.3
	assert_float(w.get_effective_crit_chance()).is_equal_approx(0.3, 0.001)

func test_modifier_adjusts_crit_chance() -> void:
	var w: Weapon = WeaponScript.new()
	w.modifier_slot_count = 1
	w.modifiers.resize(1)
	w.crit_chance = 0.1
	w.add_modifier(0, PlusCritModifier.new())
	assert_float(w.get_effective_crit_chance()).is_equal_approx(0.3, 0.001)

func test_effective_crit_chance_clamped() -> void:
	var w: Weapon = WeaponScript.new()
	w.crit_chance = 2.0
	assert_float(w.get_effective_crit_chance()).is_equal_approx(1.0, 0.001)

func test_roll_crit_zero_and_one() -> void:
	var w: Weapon = WeaponScript.new()
	w.crit_chance = 0.0
	assert_that(w.roll_crit()).is_false()
	w.crit_chance = 1.0
	assert_that(w.roll_crit()).is_true()
