extends GdUnitTestSuite

class _RecWeapon extends Weapon:
	var hit_targets: Array = []
	func resolve_hit(_user, target) -> void:
		hit_targets.append(target)

class _ChainEnemy extends Node2D:
	var invulnerable: bool = false
	var hits: int = 0
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func is_hit_invulnerable() -> bool:
		return invulnerable
	func on_hit_impact(_p: Vector2, _d: Vector2) -> void:
		hits += 1

func _chain_enemy(at: Vector2) -> _ChainEnemy:
	var n: _ChainEnemy = auto_free(_ChainEnemy.new())
	add_child(n)
	n.global_position = at
	return n

func _enemy(at: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	n.add_to_group("attackable")
	add_child(n)
	n.global_position = at
	return n

func _proj(weapon: Weapon) -> Projectile:
	var p: Projectile = auto_free(Projectile.new())
	add_child(p)
	p.global_position = Vector2.ZERO
	p.source_weapon = weapon
	p.source_node = null
	p.dig_power = 4.0
	return p

func test_forks_to_jumps_nearest_via_resolve_hit() -> void:
	var w := _RecWeapon.new()
	var first := _enemy(Vector2(10, 0))
	_enemy(Vector2(20, 0))
	_enemy(Vector2(30, 0))
	var p := _proj(w)
	var b := ChainBehavior.new()
	b.jumps = 3
	b.range_px = 200.0
	var keep := b.on_enemy_hit(p, first)
	assert_bool(keep).is_false()
	assert_int(w.hit_targets.size()).is_equal(2)
	assert_array(w.hit_targets).not_contains([first])

func test_stops_when_no_unvisited_target() -> void:
	var w := _RecWeapon.new()
	var only := _enemy(Vector2(10, 0))
	var p := _proj(w)
	var b := ChainBehavior.new()
	b.jumps = 5
	b.range_px = 200.0
	b.on_enemy_hit(p, only)
	assert_int(w.hit_targets.size()).is_equal(0)

func test_chain_skips_invulnerable_target_but_keeps_going() -> void:
	var w := _RecWeapon.new()
	var first := _chain_enemy(Vector2(100, 0))
	var shielded := _chain_enemy(Vector2(110, 0))
	shielded.invulnerable = true
	var normal := _chain_enemy(Vector2(120, 0))
	var p := _proj(w)
	var b := ChainBehavior.new()
	b.jumps = 3
	b.range_px = 200.0
	b.on_enemy_hit(p, first)
	# the invulnerable target takes nothing at all
	assert_array(w.hit_targets).not_contains([shielded])
	assert_int(shielded.hits).is_equal(0)
	assert_float(shielded.get_node("StatusComponent").get_timed_remaining("lightning")).is_equal(0.0)
	# the chain moves on to the next target
	assert_array(w.hit_targets).contains([normal])
	assert_float(normal.get_node("StatusComponent").get_timed_remaining("lightning")).is_greater(0.0)
