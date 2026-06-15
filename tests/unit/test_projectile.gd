extends GdUnitTestSuite

func test_projectile_moves_in_direction() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.direction = Vector2.RIGHT
	p.speed = 100.0
	p.lifetime = 10.0
	p.global_position = Vector2.ZERO
	p._process(0.1)
	assert_that(p.global_position.x).is_greater(5.0)

func test_projectile_expires() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.lifetime = 0.05
	p._process(0.1)
	assert_that(is_instance_valid(p)).is_false()

func test_enemy_projectile_hits_player() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = true
	p.damage = 10.0
	p.direction = Vector2.RIGHT
	var player := Node2D.new()
	player.add_to_group("player", true)
	p._handle_hit(player)
	assert_that(is_instance_valid(p)).is_false()

func test_projectile_ignores_self() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 10.0
	p.source_node = p
	var target: Enemy = auto_free(Enemy.new())
	p._handle_hit(target)
	assert_that(is_instance_valid(p)).is_true()

func test_projectile_hits_attackable() -> void:
	var p: Projectile = auto_free(Projectile.new())
	p.is_enemy_projectile = false
	p.damage = 10.0
	p.source_node = null
	var target: Enemy = auto_free(Enemy.new())
	p._handle_hit(target)
	assert_that(is_instance_valid(p)).is_false()

func test_projectile_registers_in_group() -> void:
	var p: Projectile = auto_free(Projectile.new())
	add_child(p)
	assert_that(p.is_in_group("projectile")).is_true()


class _RhTarget extends Node2D:
	var health: float = 100.0
	var hits: Array = []
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hits.append(dmg)
		health -= dmg

class _EdgeWeapon extends Weapon:
	func _init() -> void:
		var m := _PoisonEdge.new()
		modifiers = [m, null, null]
class _PoisonEdge extends Modifier:
	func on_hit_target(_w, _u, t: Node) -> void:
		t.get_node("StatusComponent").add_stain("poisoned", 2.0)

func test_projectile_routes_player_hit_through_source_weapon() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _RhTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 5.0
	p.crit_chance = 0.0
	p.source_weapon = _EdgeWeapon.new()
	parent.add_child(p)
	p._handle_hit(target)
	assert_int(target.hits[0]).is_equal(5)
	assert_that(target.get_node("StatusComponent").get_stain("poisoned")).is_greater(0.0)

func test_projectile_without_source_weapon_still_hits() -> void:
	var parent: Node2D = auto_free(Node2D.new())
	add_child(parent)
	var target := _RhTarget.new()
	parent.add_child(target)
	var p: Projectile = Projectile.new()
	p.is_enemy_projectile = false
	p.damage = 4.0
	p.crit_chance = 0.0
	parent.add_child(p)
	p._handle_hit(target)
	assert_int(target.hits[0]).is_equal(4)
