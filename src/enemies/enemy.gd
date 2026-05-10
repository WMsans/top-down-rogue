class_name Enemy
extends CharacterBody2D

signal died
signal health_changed(current: int, maximum: int)

enum State { IDLE, CHASE, WINDUP, ATTACK, COOLDOWN, HURT, DEATH }
enum EliteAbility { NONE, FAST, TANK, TELEPORT, ENRAGE }

@export var max_health: int = 20
@export var speed: float = 50.0
@export var enemy_tier: int = DropTable.EnemyTier.NORMAL
@export var detection_radius: float = 150.0
@export var windup_duration: float = 0.35
@export var death_duration: float = 0.3
@export var hurt_duration: float = 0.2
@export var cooldown_duration: float = 0.5
@export var is_elite: bool = false
@export var elite_ability: int = EliteAbility.NONE
@export var separation_radius: float = 16.0
@export var min_attack_settle_time: float = 0.5

const KNOCKBACK_SPEED: float = 180.0
const KNOCKBACK_DECAY: float = 12.0
const FLASH_COLOR: Color = Color(3.0, 3.0, 3.0)
const FLASH_DECAY: float = 0.12
const SQUASH_SCALE: Vector2 = Vector2(1.4, 0.7)
const SQUASH_DURATION: float = 0.18

var health: int
var drop_table: DropTable = null
var weapon: Weapon = null
var _knockback_velocity: Vector2 = Vector2.ZERO
var _base_modulate: Color = Color.WHITE
var _flash_tween: Tween = null
var _squash_tween: Tween = null
var _death_tween: Tween = null

var _state: int = State.IDLE
var _state_timer: float = 0.0
var _settle_timer: float = 0.0
var _prev_state: int = State.IDLE
var _player_ref: Node2D = null
var _attack_range: float = 32.0
var _player_in_range: bool = false
var _speed_base: float = 0.0
var _teleport_cooldown: float = 0.0
var _elite_enraged: bool = false
var _weapon_visual: Node2D = null
var _weapon_sprite: Sprite2D = null


func _ready() -> void:
	add_to_group("attackable")
	health = max_health
	_speed_base = speed
	motion_mode = MOTION_MODE_FLOATING

	if is_elite:
		_apply_elite_scaling()

	_player_ref = get_tree().get_first_node_in_group("player")

	_weapon_visual = Node2D.new()
	_weapon_visual.name = "WeaponVisual"
	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.name = "Sprite2D"
	_weapon_visual.add_child(_weapon_sprite)
	add_child(_weapon_visual)

	var detection_area := Area2D.new()
	detection_area.name = "DetectionArea"
	detection_area.collision_layer = 0
	detection_area.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = detection_radius
	shape.shape = circle
	detection_area.add_child(shape)
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	add_child(detection_area)

	_setup_weapon_visual.call_deferred()


func _apply_elite_scaling() -> void:
	max_health = int(float(max_health) * 3.0)
	health = max_health
	speed *= 1.3
	if weapon:
		weapon.damage *= 1.5
	scale *= 1.3

	match elite_ability:
		EliteAbility.FAST:
			windup_duration = maxf(0.2, windup_duration * 0.5)
			cooldown_duration *= 0.5
		EliteAbility.TANK:
			max_health *= 2
			health = max_health
			speed = _speed_base * 0.7
		EliteAbility.ENRAGE:
			pass  # dynamically applied in _process


func _process(delta: float) -> void:
	if _teleport_cooldown > 0.0:
		_teleport_cooldown -= delta

	if _state == State.DEATH:
		_process_death(delta)
		return

	if _state == State.HURT:
		_process_hurt(delta)
		_apply_enrage_if_needed()
	else:
		_tick_knockback(delta)
		_apply_enrage_if_needed()

		if _player_in_range:
			_settle_timer += delta
		else:
			_settle_timer = 0.0

		match _state:
			State.IDLE:
				_process_idle(delta)
			State.CHASE:
				_process_chase(delta)
			State.WINDUP:
				_process_windup(delta)
			State.ATTACK:
				_process_attack(delta)
			State.COOLDOWN:
				_process_cooldown(delta)

	if weapon:
		weapon.tick(delta)
		if weapon.has_visual():
			weapon.update_visual(delta, self)


func _physics_process(_delta: float) -> void:
	if _state == State.DEATH:
		return
	if _state == State.CHASE or _state == State.HURT:
		move_and_slide()


func _apply_enrage_if_needed() -> void:
	if not is_elite or elite_ability != EliteAbility.ENRAGE:
		return
	if not weapon:
		return
	if health < max_health * 0.3:
		if not _elite_enraged:
			_elite_enraged = true
			weapon.damage *= 2.0
			speed *= 1.5
	else:
		if _elite_enraged:
			_elite_enraged = false
			weapon.damage /= 2.0
			speed /= 1.5


func _process_idle(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if _player_in_range:
		_change_state(State.CHASE)


func _process_chase(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_change_state(State.IDLE)
		return
	if not _player_in_range:
		_change_state(State.IDLE)
		return
	if not _can_see_player():
		_change_state(State.IDLE)
		return

	var to_player := _player_ref.global_position - global_position
	if to_player.length() < 1.0:
		velocity = Vector2.ZERO
		return

	var move_dir := to_player.normalized()
	move_dir = _apply_separation(move_dir)
	velocity = move_dir * speed

	if to_player.length() <= _attack_range and _settle_timer >= min_attack_settle_time:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)


func _process_windup(delta: float) -> void:
	_state_timer -= delta
	if not _can_see_player():
		_change_state(State.IDLE)
		return
	if _state_timer <= 0.0:
		_change_state(State.ATTACK)


func _process_attack(_delta: float) -> void:
	_execute_attack()
	_change_state(State.COOLDOWN)


func _process_cooldown(delta: float) -> void:
	_state_timer -= delta
	velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
	if _state_timer <= 0.0:
		if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
			_change_state(State.CHASE)
		else:
			_change_state(State.IDLE)


func _process_hurt(delta: float) -> void:
	_state_timer -= delta
	_knockback_velocity = _knockback_velocity.lerp(Vector2.ZERO, 3.0 * delta)
	velocity = _knockback_velocity
	if _state_timer <= 0.0:
		velocity = Vector2.ZERO
		_change_state(_prev_state)


func _process_death(delta: float) -> void:
	_state_timer -= delta
	var t := 1.0 - (_state_timer / death_duration)
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.scale = Vector2.ONE * maxf(0.0, 1.0 - t)
	if _state_timer <= 0.0:
		_spawn_drops()
		queue_free()


func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent())
	if weapon:
		var drop_scene := preload("res://scenes/weapon_drop.tscn")
		var drop: Node = drop_scene.instantiate()
		drop.weapon = weapon
		drop.global_position = global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		get_parent().add_child(drop)


func _apply_separation(move_dir: Vector2) -> Vector2:
	var sep := Vector2.ZERO
	for enemy in get_tree().get_nodes_in_group("attackable"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		var to_other: Vector2 = global_position - enemy.global_position
		var dist: float = to_other.length()
		if dist < separation_radius and dist > 0.001:
			sep += to_other.normalized() * ((separation_radius - dist) / separation_radius)
	return (move_dir + sep * 0.5).normalized()


func _change_state(new_state: int) -> void:
	if new_state == State.HURT:
		_prev_state = _state
		_state = new_state
		_state_timer = hurt_duration
		return

	_state = new_state
	match new_state:
		State.WINDUP:
			_state_timer = windup_duration
			_settle_timer = 0.0
		State.COOLDOWN:
			_state_timer = cooldown_duration
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null


func _execute_attack() -> void:
	pass


func _can_see_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, _player_ref.global_position)
	query.collision_mask = 1
	query.exclude = [self, _player_ref]
	var result := space_state.intersect_ray(query)
	return result.is_empty()


func hit(damage: int) -> void:
	if damage <= 0:
		return
	if GameModeManager.is_creative():
		damage = max_health

	health -= damage
	health_changed.emit(health, max_health)
	if health <= 0:
		_change_state(State.DEATH)
		die()
		return
	if _state != State.HURT:
		_prev_state = _state
	_state = State.HURT
	_state_timer = hurt_duration


func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity += hit_dir.normalized() * KNOCKBACK_SPEED
	var display_damage: int = max_health if GameModeManager.is_creative() else damage
	var lethal: bool = display_damage >= health
	var spec := HitSpec.new()
	spec.position = impact_point
	spec.direction = hit_dir
	spec.damage = float(display_damage)
	spec.is_kill = lethal
	spec.source_color = Color.WHITE
	spec.source_radius = 8.0
	HitReaction.play(spec)

	if is_elite and elite_ability == EliteAbility.TELEPORT and _teleport_cooldown <= 0.0:
		var angle := randf() * TAU
		global_position += Vector2(cos(angle), sin(angle)) * 64.0
		_teleport_cooldown = 0.5

	hit(damage)


func die() -> void:
	died.emit()
	_on_death()


func _on_detection_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_detection_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _tick_knockback(delta: float) -> void:
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO
		return
	_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)


func _set_base_modulate(c: Color) -> void:
	_base_modulate = c
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = c


func _play_hit_flash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", _base_modulate, FLASH_DECAY)


func _play_squash() -> void:
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	sprite.scale = SQUASH_SCALE
	_squash_tween = create_tween()
	_squash_tween.set_trans(Tween.TRANS_ELASTIC)
	_squash_tween.set_ease(Tween.EASE_OUT)
	_squash_tween.tween_property(sprite, "scale", Vector2.ONE, SQUASH_DURATION)


func _on_hit() -> void:
	_play_hit_flash()
	_play_squash()


func _setup_weapon_visual() -> void:
	if weapon and weapon.has_visual():
		weapon.setup_visual(_weapon_visual, _weapon_sprite)


func _on_death() -> void:
	pass


func get_facing_direction() -> Vector2:
	if _player_ref and is_instance_valid(_player_ref):
		var d := _player_ref.global_position - global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector2.DOWN
