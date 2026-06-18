extends GdUnitTestSuite

const WeaponScript = preload("res://src/weapons/weapon.gd")

# Records whether the default on_press path fired the attack.
class RecordingWeapon extends Weapon:
	var used := 0
	func _use_impl(_user) -> void:
		used += 1

func test_on_press_default_calls_use() -> void:
	var w := RecordingWeapon.new()
	w.cooldown = 0.5
	w.on_press(null)
	assert_int(w.used).is_equal(1)

func test_on_release_default_is_noop() -> void:
	var w := RecordingWeapon.new()
	w.on_release(null)
	assert_int(w.used).is_equal(0)

func test_get_charge_ratio_default_zero() -> void:
	var w := WeaponScript.new()
	assert_float(w.get_charge_ratio()).is_equal_approx(0.0, 0.001)


func test_is_chargeable_default_false() -> void:
	var w := WeaponScript.new()
	assert_bool(w.is_chargeable()).is_false()


func test_is_charging_default_false() -> void:
	var w := WeaponScript.new()
	assert_bool(w.is_charging()).is_false()
