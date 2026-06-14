extends GdUnitTestSuite

const OilBarrelScript := preload("res://src/props/oil_barrel.gd")

func test_barrel_in_destructible_group() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._ready()
	assert_that(barrel.is_in_group("destructible")).is_true()

func test_barrel_starts_with_max_hp() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	assert_that(barrel._hp).is_equal(3)

func test_barrel_hit_reduces_hp() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._hp = 3
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	assert_that(barrel._hp).is_equal(2)
	assert_that(barrel._dead).is_false()

func test_barrel_third_hit_kills() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._hp = 3
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	barrel.on_hit_impact(Vector2(10.0, 20.0), Vector2.RIGHT, 1)
	assert_that(barrel._hp).is_equal(0)
	assert_that(barrel._dead).is_true()

func test_barrel_no_hit_after_death() -> void:
	var barrel := auto_free(OilBarrelScript.new())
	barrel._hp = 1
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_that(barrel._dead).is_true()
	barrel.on_hit_impact(Vector2.ZERO, Vector2.RIGHT, 1)
	assert_that(barrel._hp).is_equal(0)