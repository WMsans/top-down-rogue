extends GdUnitTestSuite

# A hit landing during an elite's/boss's 0.3s invulnerability must do nothing at
# all: no impact, no on-hit status. These paths bypass Weapon.resolve_hit, so
# they carry the guard themselves.
class _InvTarget extends Node2D:
	var hits: Array = []
	var invulnerable: bool = false
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func is_hit_invulnerable() -> bool:
		return invulnerable
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hits.append(1)


func _parent_with(target: Node2D) -> Node2D:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	parent.add_child(target)
	return parent


func _ctx() -> Dictionary:
	return { "direction": Vector2.RIGHT, "origin": Vector2.ZERO, "charged": false, "charge_ratio": 0.0 }


func test_legacy_projectile_hit_stains_vulnerable_target() -> void:
	var target := _InvTarget.new()
	var parent := _parent_with(target)
	var p: Projectile = Projectile.new()  # frees itself on hit
	p.is_enemy_projectile = false
	p.dig_power = 4.0
	p.hit_status = "on_fire"
	parent.add_child(p)
	p._handle_hit(target)
	assert_int(target.hits.size()).is_equal(1)
	assert_that(target.get_node("StatusComponent").get_stain("on_fire")).is_greater(0.0)


func test_legacy_projectile_hit_on_invulnerable_target_does_nothing() -> void:
	var target := _InvTarget.new()
	target.invulnerable = true
	var parent := _parent_with(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.dig_power = 4.0
	p.hit_status = "on_fire"
	parent.add_child(p)
	p._handle_hit(target)
	assert_int(target.hits.size()).is_equal(0)
	assert_that(target.get_node("StatusComponent").get_stain("on_fire")).is_equal(0.0)


func _user_with(target: Node2D) -> Array:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var user: Node2D = Node2D.new()
	parent.add_child(user)
	parent.add_child(target)
	target.global_position = Vector2(20, 0)
	return [parent, user]


func test_lightning_bolt_freezes_vulnerable_target() -> void:
	var target := _InvTarget.new()
	var pu := _user_with(target)
	var m := LightningBoltModifier.new()
	m.proc_chance = 1.0
	m.on_attack(null, pu[1], _ctx())
	assert_int(target.hits.size()).is_equal(1)
	assert_that(target.get_node("StatusComponent").get_stain("frozen")).is_greater(0.0)


func test_lightning_bolt_on_invulnerable_target_does_nothing() -> void:
	var target := _InvTarget.new()
	target.invulnerable = true
	var pu := _user_with(target)
	var m := LightningBoltModifier.new()
	m.proc_chance = 1.0
	m.on_attack(null, pu[1], _ctx())
	assert_int(target.hits.size()).is_equal(0)
	assert_that(target.get_node("StatusComponent").get_stain("frozen")).is_equal(0.0)


# A chain spark proc that reaches an invulnerable target: the target takes
# nothing, and the other targets in the proc still get hit.
func test_chain_spark_on_invulnerable_target_does_nothing() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var shielded: _InvTarget = auto_free(_InvTarget.new())
	add_child(shielded)
	shielded.global_position = Vector2(20.0, 0.0)
	shielded.invulnerable = true
	var normal: _InvTarget = auto_free(_InvTarget.new())
	add_child(normal)
	normal.global_position = Vector2(40.0, 0.0)
	var m := ChainSparkModifier.new()
	m.proc_chance = 1.0
	m.on_kill(null, user, null)
	assert_int(shielded.hits.size()).is_equal(0)
	assert_float(shielded.get_node("StatusComponent").get_timed_remaining("lightning")).is_equal(0.0)
	assert_int(normal.hits.size()).is_equal(1)
	assert_float(normal.get_node("StatusComponent").get_timed_remaining("lightning")).is_greater(0.0)


# A projectile chain that reaches an invulnerable target: the target takes
# nothing, and the chain still moves on to the next one.
func test_chain_behavior_on_invulnerable_target_does_nothing() -> void:
	var first: _InvTarget = auto_free(_InvTarget.new())
	add_child(first)
	first.global_position = Vector2(100.0, 0.0)
	var shielded: _InvTarget = auto_free(_InvTarget.new())
	add_child(shielded)
	shielded.global_position = Vector2(110.0, 0.0)
	shielded.invulnerable = true
	var normal: _InvTarget = auto_free(_InvTarget.new())
	add_child(normal)
	normal.global_position = Vector2(120.0, 0.0)
	var p: Projectile = auto_free(Projectile.new())
	add_child(p)
	p.global_position = Vector2.ZERO
	p.source_weapon = Weapon.new()
	var b := ChainBehavior.new()
	b.jumps = 3
	b.range_px = 200.0
	b.on_enemy_hit(p, first)
	assert_int(shielded.hits.size()).is_equal(0)
	assert_float(shielded.get_node("StatusComponent").get_timed_remaining("lightning")).is_equal(0.0)
	assert_int(normal.hits.size()).is_equal(1)
	assert_float(normal.get_node("StatusComponent").get_timed_remaining("lightning")).is_greater(0.0)
