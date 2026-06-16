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


class _StatusTarget extends Node2D:
	func _init() -> void:
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)

func test_status_edge_stains_target_on_hit() -> void:
	var t: _StatusTarget = auto_free(_StatusTarget.new())
	add_child(t)
	var m: DataModifier = DataModifier.new(_row({
		"category": "status", "trigger": "on_hit", "effect": "apply_status",
		"element": "poisoned", "magnitude": "2",
	}))
	m.on_hit_target(null, null, t)
	assert_that(t.get_node("StatusComponent").get_stain("poisoned")).is_equal(2.0)

func test_stat_add_affix() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "trigger": "passive", "effect": "stat_add", "element": "damage", "magnitude": "3" }))
	assert_that(m.get_stat_add("damage")).is_equal(3.0)
	assert_that(m.get_stat_add("cooldown")).is_equal(0.0)

func test_stat_mult_affix() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "trigger": "passive", "effect": "stat_mult", "element": "cooldown", "magnitude": "0.8" }))
	assert_that(m.get_stat_mult("cooldown")).is_equal(0.8)
	assert_that(m.get_stat_mult("damage")).is_equal(1.0)

func test_heavy_head_dual_stat() -> void:
	var m := DataModifier.new(_row({ "category": "stat", "trigger": "passive", "effect": "stat_add", "element": "damage", "magnitude": "5", "magnitude2": "1.25" }))
	assert_that(m.get_stat_add("damage")).is_equal(5.0)
	assert_that(m.get_stat_mult("cooldown")).is_equal(1.25)


class _HpTarget extends Node2D:
	var health: float = 3.0
	var max_health: float = 10.0
	func _init() -> void:
		var sc := StatusComponent.new(); sc.name = "StatusComponent"; add_child(sc)

func test_pyroclast_multiplies_only_when_target_burning() -> void:
	var t: _HpTarget = auto_free(_HpTarget.new()); add_child(t)
	var m: DataModifier = DataModifier.new(_row({ "category": "trigger", "trigger": "on_hit", "condition": "target_status:on_fire", "effect": "stat_mult", "element": "damage", "magnitude": "1.5" }))
	assert_that(m.modify_hit_damage(null, null, t, 10.0)).is_equal(10.0)
	t.get_node("StatusComponent").add_stain("on_fire", 2.0)
	assert_that(m.modify_hit_damage(null, null, t, 10.0)).is_equal(15.0)

func test_gold_drop_joins_pickup_group() -> void:
	var g: GoldDrop = auto_free(preload("res://scenes/gold_drop.tscn").instantiate())
	add_child(g)
	assert_bool(g.is_in_group("pickup")).is_true()

func test_coup_de_grace_executes_low_hp() -> void:
	var t: _HpTarget = auto_free(_HpTarget.new()); add_child(t)
	var m: DataModifier = DataModifier.new(_row({ "category": "trigger", "trigger": "on_hit", "condition": "target_low_hp", "effect": "stat_mult", "element": "damage", "magnitude": "2.0", "magnitude2": "0.3" }))
	assert_that(m.modify_hit_damage(null, null, t, 10.0)).is_equal(20.0)

func test_bloodlust_stacks_on_kill_capped() -> void:
	var m: DataModifier = DataModifier.new(_row({ "category": "trigger", "trigger": "on_kill", "effect": "stat_add", "element": "damage", "magnitude": "1", "magnitude2": "8" }))
	for i in range(10):
		m.on_kill(null, null, null)
	assert_that(m.get_stat_add("damage")).is_equal(8.0)

func test_combo_keeper_forces_crit_on_fifth() -> void:
	var w: Weapon = Weapon.new()
	var m: DataModifier = DataModifier.new(_row({ "category": "trigger", "trigger": "every_n_hits", "effect": "stat_add", "element": "crit_chance", "magnitude": "1.0", "magnitude2": "5" }))
	w.modifiers = [m, null, null]
	w._hit_count = 4
	assert_that(w.get_effective_crit_chance()).is_equal(1.0)
	w._hit_count = 2
	assert_that(w.get_effective_crit_chance()).is_equal(0.0)


class _KnockTarget extends Node2D:
	var knocks: Array = []
	func _init() -> void:
		add_to_group("attackable")
	func apply_knockback(dir: Vector2, strength: float) -> void:
		knocks.append({ "dir": dir, "strength": strength })

func test_shockwave_stomp_knocks_in_range_on_swing() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var near: _KnockTarget = auto_free(_KnockTarget.new())
	add_child(near)
	near.global_position = Vector2(30, 0)   # within 40*1.8=72
	var far: _KnockTarget = auto_free(_KnockTarget.new())
	add_child(far)
	far.global_position = Vector2(300, 0)   # outside
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_swing", "effect": "knockback", "magnitude": "40",
	}))
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": false, "charge_ratio": 0.0 })
	assert_int(near.knocks.size()).is_equal(1)
	assert_that(near.knocks[0]["strength"]).is_equal(40.0)
	assert_int(far.knocks.size()).is_equal(0)

func test_repulsor_nova_only_on_full_charge() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var near: _KnockTarget = auto_free(_KnockTarget.new())
	add_child(near)
	near.global_position = Vector2(50, 0)   # within 80*1.8=144
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_charge", "effect": "knockback", "magnitude": "80",
	}))
	# partial charge: no knockback
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": true, "charge_ratio": 0.5 })
	assert_int(near.knocks.size()).is_equal(0)
	# full charge: knockback
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": true, "charge_ratio": 1.0 })
	assert_int(near.knocks.size()).is_equal(1)
	assert_that(near.knocks[0]["strength"]).is_equal(80.0)


class _FakeGold extends Node2D:
	var _velocity: Vector2 = Vector2.ZERO
	func _init() -> void:
		add_to_group("pickup")

func test_magnet_field_pulls_pickup_in_range() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	user.global_position = Vector2.ZERO
	var near: _FakeGold = auto_free(_FakeGold.new())
	add_child(near)
	near.global_position = Vector2(20, 0)    # within 48
	var far: _FakeGold = auto_free(_FakeGold.new())
	add_child(far)
	far.global_position = Vector2(200, 0)    # outside 48
	var m := DataModifier.new(_row({
		"category": "utility", "trigger": "on_swing", "effect": "pull", "magnitude": "48",
	}))
	m.on_attack(null, user, { "origin": Vector2.ZERO, "direction": Vector2.RIGHT, "charged": false, "charge_ratio": 0.0 })
	# near pulled toward user (negative x), far untouched
	assert_that(near._velocity.x).is_less(0.0)
	assert_that(far._velocity).is_equal(Vector2.ZERO)
