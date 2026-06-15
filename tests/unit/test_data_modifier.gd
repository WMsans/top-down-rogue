extends GdUnitTestSuite

func test_base_modifier_new_hooks_are_noops() -> void:
	var m: Modifier = Modifier.new()
	assert_that(m.modify_stat("damage", 5.0)).is_equal(5.0)
	assert_that(m.modify_hit_damage(null, null, null, 7.0)).is_equal(7.0)
	m.on_hit_target(null, null, null)
	m.on_kill(null, null, null)

func test_weapon_cooldown_damage_survive_duplicate() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 0.42
	w.damage = 9.0
	var copy: Weapon = w.duplicate(true)
	assert_that(copy.cooldown).is_equal(0.42)
	assert_that(copy.damage).is_equal(9.0)


class _MatAdapter:
	var placed: Array = []
	func place_material(pos: Vector2, radius: float, mat: int) -> void:
		placed.append(mat)

func _row(overrides: Dictionary) -> Dictionary:
	var base := {
		"id": "x", "name": "X", "description": "", "rarity": "Common",
		"category": "", "trigger": "", "condition": "", "effect": "",
		"element": "", "magnitude": "0", "magnitude2": "0", "suppresses_base_use": "No",
	}
	for k in overrides.keys():
		base[k] = overrides[k]
	return base

func test_data_modifier_stores_columns() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "effect": "stat_add", "element": "damage", "magnitude": "3" }))
	assert_str(m.category).is_equal("stat")
	assert_str(m.effect).is_equal("stat_add")
	assert_that(m.magnitude).is_equal(3.0)

func test_emitter_places_material_on_swing() -> void:
	var rec := _MatAdapter.new()
	var prev: Variant = TerrainSurface.adapter
	TerrainSurface.register_adapter(rec)
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var m := DataModifier.new(_row({
		"category": "emitter", "trigger": "on_swing", "effect": "spawn_material",
		"element": "water", "magnitude": "16",
	}))
	m.on_attack(null, user, { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0 })
	TerrainSurface.register_adapter(prev)
	assert_int(rec.placed.size()).is_equal(1)
	assert_that(rec.placed[0]).is_equal(MaterialRegistry.MAT_WATER)
