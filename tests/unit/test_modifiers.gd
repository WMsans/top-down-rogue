extends GdUnitTestSuite

# A minimal attackable target with a StatusComponent, used across the suite.
class _StubTarget extends Node2D:
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_point: Vector2, _dir: Vector2, dmg: int) -> void:
		hits.append(dmg)


func test_projectile_hit_status_applies_on_non_crit_hit() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _StubTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()  # frees itself on hit
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.crit_chance = 0.0
	p.hit_status = "on_fire"
	parent.add_child(p)
	p._handle_hit(target)
	var sc: StatusComponent = target.get_node("StatusComponent")
	assert_that(sc.get_stain("on_fire")).is_greater(0.0)


func test_projectile_no_hit_status_applies_nothing() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _StubTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.crit_chance = 0.0
	parent.add_child(p)
	p._handle_hit(target)
	var sc: StatusComponent = target.get_node("StatusComponent")
	assert_that(sc.get_stain("on_fire")).is_equal(0.0)


# Records on_attack calls.
class _RecordMod extends Modifier:
	var attacks: int = 0
	var last_ctx: Dictionary = {}
	func on_attack(_weapon: Weapon, _user: Node, ctx: Dictionary) -> void:
		attacks += 1
		last_ctx = ctx


func test_notify_attack_dispatches_to_all_modifiers() -> void:
	var w: Weapon = Weapon.new()
	var m1 := _RecordMod.new()
	var m2 := _RecordMod.new()
	w.modifiers = [m1, null, m2]
	var ctx := { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": true, "charge_ratio": 1.0 }
	w.notify_attack(null, ctx)
	assert_int(m1.attacks).is_equal(1)
	assert_int(m2.attacks).is_equal(1)
	assert_that(m1.last_ctx["charged"]).is_true()


func test_base_modifier_on_attack_is_noop() -> void:
	var m: Modifier = Modifier.new()
	m.on_attack(null, null, {})  # must not error


# Advanced melee weapon that skips terrain/visual side-effects so _play_move
# can run headless; the base _play_move (with notify_attack) is NOT overridden.
class _NoHitAdvanced extends AdvancedMeleeWeapon:
	func _setup_moves() -> void:
		combo_mode = ComboMode.TAP_CHAIN
		combo_reset_time = 0.5
		light_moves = [_slash(), _slash(), _thrust()]
	func _apply_move_hit(_move, _user, _pos, _dir) -> void:
		pass
	func _start_move_anim(_move, _dir) -> void:
		pass


func test_advanced_play_move_notifies_per_step() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	var w := _NoHitAdvanced.new()
	w.weapon_reach = 30.0
	w.arc_angle = PI / 2.0
	w.cooldown = 0.0
	var m := _RecordMod.new()
	w.modifiers = [m, null, null]
	w.on_press(user)  # step 0
	w.on_press(user)  # step 1
	assert_int(m.attacks).is_equal(2)
	assert_that(m.last_ctx["charged"]).is_false()


func _count_projectiles(parent: Node) -> int:
	var n := 0
	for c in parent.get_children():
		if c is Projectile:
			n += 1
	return n


func test_modifier_projectile_spawn_one_under_user_parent() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	var p: Projectile = ModifierProjectile.spawn_one(user, Vector2.ZERO, Vector2.RIGHT, 4.0,
		{ "hit_status": "on_fire" })
	assert_that(p).is_not_null()
	assert_bool(p.get_parent() == parent).is_true()
	assert_that(p.damage).is_equal(4.0)
	assert_str(p.hit_status).is_equal("on_fire")
	assert_that(p.is_enemy_projectile).is_false()


func test_modifier_projectile_spawn_fan_count() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	ModifierProjectile.spawn_fan(user, Vector2.ZERO, Vector2.RIGHT, 2.0, 5, 30.0, {})
	assert_int(_count_projectiles(parent)).is_equal(5)


func test_modifier_projectile_fan_makes_fresh_behaviors() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	ModifierProjectile.spawn_fan(user, Vector2.ZERO, Vector2.RIGHT, 3.0, 3, 20.0,
		{ "make_behaviors": func() -> Array: return [BounceBehavior.new()] })
	var seen: Array = []
	for c in parent.get_children():
		if c is Projectile:
			assert_int(c.behaviors.size()).is_equal(1)
			assert_that(c.behaviors[0] is BounceBehavior).is_true()
			assert_that(seen.has(c.behaviors[0])).is_false()
			seen.append(c.behaviors[0])


class _CountingMod extends ProjectileModifier:
	var fires: int = 0
	func _fire(_weapon, _user, _ctx) -> void:
		fires += 1


func test_cadence_every_hit_by_default() -> void:
	var m := _CountingMod.new()
	for i in range(4):
		m.on_attack(null, null, {})
	assert_int(m.fires).is_equal(4)


func test_cadence_period_three_fire_on_zero_and_one() -> void:
	var m := _CountingMod.new()
	m.period = 3
	m.fire_on = [0, 1]
	for i in range(5):
		m.on_attack(null, null, {})
	assert_int(m.fires).is_equal(4)


func test_cadence_period_three_fire_on_last_only() -> void:
	var m := _CountingMod.new()
	m.period = 3
	m.fire_on = [2]
	for i in range(6):
		m.on_attack(null, null, {})
	assert_int(m.fires).is_equal(2)


func _spawn_parent_and_user() -> Array:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	return [parent, user]

func _ctx(charged: bool = false, ratio: float = 0.0) -> Dictionary:
	return { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": charged, "charge_ratio": ratio }


func test_fireball_fan_spawns_five_burning() -> void:
	var pu := _spawn_parent_and_user()
	FireballFanModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(5)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_str(c.hit_status).is_equal("on_fire")


func test_icicle_volley_spawns_five_chilly() -> void:
	var pu := _spawn_parent_and_user()
	IcicleVolleyModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(5)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_str(c.hit_status).is_equal("chilly")


func test_gleaming_projectile_has_clear_behavior() -> void:
	var pu := _spawn_parent_and_user()
	GleamingProjectileModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is ClearBulletsBehavior).is_true()


func test_green_crescent_has_penetrate_behavior() -> void:
	var pu := _spawn_parent_and_user()
	GreenCrescentModifier.new().on_attack(null, pu[1], _ctx())
	assert_int(_count_projectiles(pu[0])).is_equal(1)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is PenetrateBehavior).is_true()


func test_arc_volley_fires_seven_on_first_two_of_three() -> void:
	var pu := _spawn_parent_and_user()
	var m := ArcVolleyModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> fire 7
	assert_int(_count_projectiles(pu[0])).is_equal(7)
	m.on_attack(null, pu[1], _ctx())  # pos 1 -> fire 7
	assert_int(_count_projectiles(pu[0])).is_equal(14)
	m.on_attack(null, pu[1], _ctx())  # pos 2 -> none
	assert_int(_count_projectiles(pu[0])).is_equal(14)
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> fire 7
	assert_int(_count_projectiles(pu[0])).is_equal(21)


func test_triangular_volley_fires_thirteen_on_third() -> void:
	var pu := _spawn_parent_and_user()
	var m := TriangularVolleyModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> none
	m.on_attack(null, pu[1], _ctx())  # pos 1 -> none
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx())  # pos 2 -> fire 13
	assert_int(_count_projectiles(pu[0])).is_equal(13)


func test_splitting_rounds_fires_three_with_split_on_second() -> void:
	var pu := _spawn_parent_and_user()
	var m := SplittingRoundsModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0 -> none
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx())  # pos 1 -> fire 3
	assert_int(_count_projectiles(pu[0])).is_equal(3)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is SplitBehavior).is_true()


func test_bouncing_bullets_fires_four_with_bounce_on_third() -> void:
	var pu := _spawn_parent_and_user()
	var m := BouncingBulletsModifier.new()
	m.on_attack(null, pu[1], _ctx())  # pos 0
	m.on_attack(null, pu[1], _ctx())  # pos 1
	assert_int(_count_projectiles(pu[0])).is_equal(0)
	m.on_attack(null, pu[1], _ctx())  # pos 2 -> fire 4
	assert_int(_count_projectiles(pu[0])).is_equal(4)
	for c in pu[0].get_children():
		if c is Projectile:
			assert_that(c.behaviors[0] is BounceBehavior).is_true()
