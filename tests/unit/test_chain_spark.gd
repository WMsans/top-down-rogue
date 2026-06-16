extends GdUnitTestSuite

class _SparkEnemy extends Node2D:
	var hit_dmg: int = -1
	func _init() -> void:
		add_to_group("attackable")
		var sc := StatusComponent.new()
		sc.name = "StatusComponent"
		add_child(sc)
	func on_hit_impact(_p: Vector2, _d: Vector2, dmg: int) -> void:
		hit_dmg = dmg

func test_chain_spark_hits_up_to_three_nearest() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var enemies: Array = []
	for i in range(5):
		var e: _SparkEnemy = auto_free(_SparkEnemy.new())
		add_child(e)
		e.global_position = Vector2(10.0 * float(i + 1), 0.0)   # x = 10..50, all within RANGE
		enemies.append(e)
	var m := ChainSparkModifier.new()
	m.on_crit(null, user, null)
	var hits := 0
	for e in enemies:
		if e.hit_dmg >= 0:
			hits += 1
	assert_int(hits).is_equal(3)
	# nearest three got lightning status
	assert_that(enemies[0].get_node("StatusComponent").get_timed_remaining("lightning")).is_greater(0.0)

func test_chain_spark_respects_range() -> void:
	var user: Node2D = auto_free(Node2D.new())
	add_child(user)
	var near: _SparkEnemy = auto_free(_SparkEnemy.new())
	add_child(near)
	near.global_position = Vector2(20.0, 0.0)
	var far: _SparkEnemy = auto_free(_SparkEnemy.new())
	add_child(far)
	far.global_position = Vector2(500.0, 0.0)   # outside RANGE 160
	var m := ChainSparkModifier.new()
	m.on_crit(null, user, null)
	assert_bool(near.hit_dmg >= 0).is_true()
	assert_bool(far.hit_dmg >= 0).is_false()
