class_name PlayerController
extends CharacterBody2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0
@export var auto_face_range: float = 250.0
const TARGET_SWITCH_RATIO: float = 0.7

var _last_facing: Vector2 = Vector2.DOWN
var _facing_left: bool = false
var _original_collision_layer: int
var _original_collision_mask: int
var targeted_enemy: Node2D = null

@onready var _color_rect: ColorRect = $ColorRect

const KNOCKBACK_SPEED := 20.0
const KNOCKBACK_DECAY := 12.0
const ZOOM_PUNCH_THRESHOLD := 10.0
const ZOOM_PUNCH_AMOUNT := 0.92
const HIT_FLASH_COLOR := Color(2.5, 0.3, 0.1)
const MAX_RECOVERY_STEPS := 8
const RECOVERY_STEP := 2.0

var _knockback_velocity: Vector2 = Vector2.ZERO
var _flash_tween: Tween
var _squash_tween: Tween
var _zoom_tween: Tween
var _last_safe_position: Vector2 = Vector2.ZERO


func _enter_tree() -> void:
	var inventory := PlayerInventory.new()
	inventory.name = "PlayerInventory"
	add_child(inventory)

func _ready() -> void:
	_color_rect.pivot_offset = Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	add_to_group("player")
	var cam_node := get_node_or_null("Camera2D")
	if cam_node:
		cam_node.add_to_group("camera")
	collision_mask = 3
	collision_layer = 1 | (1 << 7)
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")
	var pickup_context := PickupContext.new()
	pickup_context.name = "PickupContext"
	add_child(pickup_context)
	var delivery := WeaponDelivery.new()
	delivery.name = "WeaponDelivery"
	add_child(delivery)
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = TerrainSurface.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)
	_last_safe_position = position


func _physics_process(delta: float) -> void:
	var inventory := get_node_or_null("PlayerInventory")
	if GameModeManager.is_creative():
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = _original_collision_layer
		collision_mask = _original_collision_mask
	if inventory and inventory.is_dead():
		velocity = Vector2.ZERO
		move_and_slide()
		_resolve_terrain_overlap()
		return

	var input_dir := _get_input_direction()
	if _knockback_velocity.length_squared() > 0.01:
		_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)
	_update_target()
	var enemy_dir := _find_closest_enemy_direction()
	var is_pushing_wall := input_dir != Vector2.ZERO and _is_blocked_by_terrain(input_dir)
	if is_pushing_wall:
		_last_facing = input_dir
	elif enemy_dir != Vector2.ZERO:
		_last_facing = enemy_dir
	elif input_dir != Vector2.ZERO:
		_last_facing = input_dir
	if _last_facing.x < -0.01:
		_facing_left = true
	elif _last_facing.x > 0.01:
		_facing_left = false
	if _color_rect != null:
		_color_rect.scale.x = -1.0 if _facing_left else 1.0
	_apply_movement(input_dir, delta)
	velocity += _knockback_velocity
	move_and_slide()
	_resolve_terrain_overlap()

	var wm := get_parent().get_node_or_null("WorldManager")
	if wm:
		wm.tracking_position = global_position


func _get_input_direction() -> Vector2:
	if ConsoleManager.is_open():
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	return dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO


func _is_blocked_by_terrain(direction: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var ray_length := max(BODY_WIDTH, BODY_HEIGHT) / 2.0 + 4.0
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + direction * ray_length,
		1,  # terrain collision_layer (see chunk_manager.gd:115)
		[self]
	)
	var result := space_state.intersect_ray(query)
	return not result.is_empty()


func _resolve_terrain_overlap() -> void:
	var shape_node: CollisionShape2D = $CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		_last_safe_position = global_position
		return
	var space_state := get_world_2d().direct_space_state
	var shape_params := PhysicsShapeQueryParameters2D.new()
	shape_params.shape = shape_node.shape
	shape_params.transform = global_transform
	shape_params.collision_mask = 1  # terrain layer
	shape_params.collide_with_areas = false
	shape_params.collide_with_bodies = true
	shape_params.margin = 0.0
	shape_params.exclude = [get_rid()]

	var overlaps := space_state.intersect_shape(shape_params, 1)
	if overlaps.is_empty():
		_last_safe_position = global_position
		return

	var priority_dir := _last_facing if _last_facing.length_squared() > 0.01 else Vector2.ZERO
	var directions: Array[Vector2] = []
	if priority_dir != Vector2.ZERO:
		directions.append(priority_dir.normalized())
	directions.append_array([
		Vector2.UP,
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.UP + Vector2.RIGHT,
		Vector2.DOWN + Vector2.RIGHT,
		Vector2.DOWN + Vector2.LEFT,
		Vector2.UP + Vector2.LEFT,
	])
	for d_idx in directions.size():
		directions[d_idx] = directions[d_idx].normalized()

	for step in range(1, MAX_RECOVERY_STEPS + 1):
		for dir in directions:
			var test_pos := global_position + dir * RECOVERY_STEP * step
			shape_params.transform = Transform2D(global_rotation, test_pos)
			var test_overlaps := space_state.intersect_shape(shape_params, 1)
			if test_overlaps.is_empty():
				global_position = test_pos
				_last_safe_position = global_position
				return

	global_position = _last_safe_position


func _apply_movement(input_dir: Vector2, delta: float) -> void:
	if input_dir != Vector2.ZERO:
		velocity += input_dir * acceleration * delta
	else:
		var friction_amount: float = friction * delta
		if velocity.length() <= friction_amount:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity.normalized() * friction_amount
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed


func _can_see_enemy(enemy: Node2D) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, enemy.global_position)
	query.collision_mask = 1
	query.exclude = [self, enemy]
	var result := space_state.intersect_ray(query)
	return result.is_empty()


func _update_target() -> void:
	if targeted_enemy != null and is_instance_valid(targeted_enemy) and (targeted_enemy is Node2D):
		var dist_to_current := global_position.distance_to(targeted_enemy.global_position)
		if dist_to_current <= auto_face_range and _can_see_enemy(targeted_enemy):
			var closer_enemy: Node2D = null
			var closer_dist := dist_to_current * TARGET_SWITCH_RATIO
			for enemy in get_tree().get_nodes_in_group("attackable"):
				if enemy == targeted_enemy or not is_instance_valid(enemy) or not (enemy is Node2D):
					continue
				var dist := global_position.distance_to(enemy.global_position)
				if dist < closer_dist and _can_see_enemy(enemy):
					closer_dist = dist
					closer_enemy = enemy
			if closer_enemy != null:
				targeted_enemy = closer_enemy
			return

	var closest_dist := auto_face_range
	var closest_enemy: Node2D = null
	for enemy in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < closest_dist and _can_see_enemy(enemy):
			closest_dist = dist
			closest_enemy = enemy
	targeted_enemy = closest_enemy


func _find_closest_enemy_direction() -> Vector2:
	if targeted_enemy != null and is_instance_valid(targeted_enemy):
		var to_enemy: Vector2 = targeted_enemy.global_position - global_position
		if to_enemy.length() > 0.01:
			return to_enemy.normalized()
	return Vector2.ZERO


func get_facing_direction() -> Vector2:
	return _last_facing


func is_facing_left() -> bool:
	return _facing_left


func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity = hit_dir.normalized() * KNOCKBACK_SPEED

	_play_hit_flash()
	_play_squash()
	_play_zoom_punch(damage)

	var inventory := get_node_or_null("PlayerInventory")
	if inventory:
		inventory.take_damage(damage, hit_dir)


func _play_hit_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_color_rect.modulate = HIT_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_color_rect, "modulate", Color.WHITE, 0.12)


func _play_squash() -> void:
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	var sgn := -1.0 if _facing_left else 1.0
	var target_scale := Vector2(sgn * 1.3, 0.7)
	var rest_scale := Vector2(sgn, 1.0)
	_squash_tween = create_tween()
	_squash_tween.tween_property(_color_rect, "scale", target_scale, 0.06)
	_squash_tween.tween_property(_color_rect, "scale", rest_scale, 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _play_zoom_punch(damage: int) -> void:
	if damage < ZOOM_PUNCH_THRESHOLD:
		return
	var cam := get_node_or_null("Camera2D")
	if cam == null:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var default_zoom : Vector2 = cam.zoom
	var punched_zoom := default_zoom * ZOOM_PUNCH_AMOUNT
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(cam, "zoom", punched_zoom, 0.07).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_property(cam, "zoom", default_zoom, 0.08)


const PARRY_KNOCKBACK_SPEED: float = 40.0
const PARRY_STUN_DURATION: float = 0.25


func try_parry(attacker: Node, hit_pos: Vector2, hit_dir: Vector2) -> bool:
	var inv := get_node_or_null("PlayerInventory")
	if inv == null:
		return false
	var weapon = inv.get_weapon(inv.active_weapon_slot)
	if weapon == null or not (weapon is MeleeWeapon):
		return false
	var melee: MeleeWeapon = weapon
	if not melee.is_parry_active():
		return false
	if attacker != null and "weapon" in attacker:
		var aw = attacker.get("weapon")
		if aw is MeleeWeapon and not aw.parryable:
			return false
	var dir := hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector2.RIGHT
	_knockback_velocity = -dir * PARRY_KNOCKBACK_SPEED
	if attacker is Node2D and "_knockback_velocity" in attacker:
		attacker._knockback_velocity = dir * PARRY_KNOCKBACK_SPEED
	if "_parry_stun_remaining" in attacker:
		attacker._parry_stun_remaining = PARRY_STUN_DURATION
	var midpoint: Vector2 = (global_position + (attacker.global_position if attacker is Node2D else hit_pos)) * 0.5
	var nail_clash := preload("res://src/player/feedback/nail_clash_fx.gd")
	nail_clash.play(midpoint, dir.orthogonal())
	return true
