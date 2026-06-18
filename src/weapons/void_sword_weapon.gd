class_name VoidSwordWeapon
extends AdvancedMeleeWeapon

const PULL_RADIUS := 120.0
const PULL_SPEED := 70.0
const ATTACKABLE_LAYER := 1 << 7

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.7
	charged_flurry_max = 1
	light_moves = [_slash()]
	var sweep := _slash(0.0, 1.2)
	sweep.arc = PI            # wide finishing arc
	charged_moves = [sweep]

func _on_charge_tick(user, delta: float, ratio: float) -> void:
	if user == null or not (user is Node2D):
		return
	var origin: Vector2 = user.global_position
	var space_state: PhysicsDirectSpaceState2D = user.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = PULL_RADIUS
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, origin)
	params.collision_mask = ATTACKABLE_LAYER
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits := space_state.intersect_shape(params, 32)
	for hit in hits:
		var node = hit.get("collider", null)
		if node == null or node == user or not (node is Node2D):
			continue
		var to_origin: Vector2 = origin - node.global_position
		if to_origin.length() < 4.0:
			continue
		node.global_position += to_origin.normalized() * PULL_SPEED * ratio * delta
