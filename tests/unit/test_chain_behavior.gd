extends GdUnitTestSuite

class _RecWeapon extends Weapon:
	var hit_targets: Array = []
	func resolve_hit(_user, target, _dmg, _crit) -> void:
		hit_targets.append(target)

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
	p.damage = 4.0
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
