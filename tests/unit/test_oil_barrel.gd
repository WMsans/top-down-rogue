extends GdUnitTestSuite

const OilBarrelScript := preload("res://src/props/oil_barrel.gd")


func test_barrel_in_destructible_group() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._ready()
	assert_true(barrel.is_in_group("destructible"))


func test_barrel_starts_with_max_hp() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	assert_eq(barrel._hp, 3)


func test_barrel_hit_reduces_hp() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._hp = 3
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	assert_eq(barrel._hp, 2)
	assert_false(barrel._dead)


func test_barrel_third_hit_kills() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._hp = 3
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	assert_eq(barrel._hp, 0)
	assert_true(barrel._dead)


func test_barrel_no_hit_after_death() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._hp = 1
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_true(barrel._dead)
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_eq(barrel._hp, 0)