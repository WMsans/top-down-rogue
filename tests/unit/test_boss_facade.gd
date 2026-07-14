extends GdUnitTestSuite

class FacadeBoss extends BossEnemy:
	var stamps: Array = []
	var rings: Array = []
	var statuses: Array = []
	var minions: Array = []
	var props: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
		rings.append({"pos": pos, "inner": inner, "outer": outer, "mat": mat_id})
	func _apply_status(target: Node, status_id: String, amount: float) -> void:
		statuses.append({"target": target, "id": status_id, "amount": amount})
	func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void:
		minions.append({"scene": scene, "pos": world_pos, "elite": is_elite})
	func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
		props.append({"scene": scene, "pos": world_pos})


func test_facade_overrides_capture_calls_not_singletons() -> void:
	var b : FacadeBoss = auto_free(FacadeBoss.new())
	b._stamp_material(Vector2(10, 10), 8.0, 4)
	b._stamp_material_ring(Vector2.ZERO, 4.0, 12.0, 4)
	b._apply_status(null, "chilly", 1.5)
	b._spawn_minion(null, Vector2(20, 20), true)
	b._spawn_prop(null, Vector2(30, 30))
	assert_int(b.stamps.size()).is_equal(1)
	assert_int(b.rings.size()).is_equal(1)
	assert_int(b.statuses.size()).is_equal(1)
	assert_int(b.minions.size()).is_equal(1)
	assert_int(b.props.size()).is_equal(1)
	assert_float(b.stamps[0]["radius"]).is_equal(8.0)