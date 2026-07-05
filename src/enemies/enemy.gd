class_name Enemy
extends CharacterBody2D

signal died
signal health_changed(current: int, maximum: int)

enum State { WANDER, CHASE, WINDUP, ATTACK, COOLDOWN, HURT, DEATH }
enum EliteAbility { NONE, FAST, TANK, TELEPORT, ENRAGE }

@export var max_health: int = 20
@export var speed: float = 50.0
@export var enemy_tier: int = DropTable.EnemyTier.NORMAL
@export var detection_radius: float = 150.0
@export var windup_duration: float = 0.35
@export var death_duration: float = 0.3
@export var hurt_duration: float = 0.2
@export var cooldown_duration: float = 0.8
@export var is_elite: bool = false
@export var elite_ability: int = EliteAbility.NONE
@export var separation_radius: float = 22.0
@export var separation_weight: float = 1.2
@export var crowd_spacing_scale: float = 1.0
@export var leash_radius: float = 280.0
@export var damage_scale: float = 1.0
@export var carries_weapon: bool = true

const KNOCKBACK_SPEED: float = 180.0
const KNOCKBACK_DECAY: float = 12.0
const DEFAULT_BODY_RADIUS: float = 8.0
# Max distance moved per collision sub-step. Matches NavField.CELL so a single
# step never skips over a solid cell (prevents knockback tunneling through walls).
const MOVE_STEP_PX: float = 8.0
const CROWD_PUSH_CAP: float = 4.0
const FLASH_COLOR: Color = Color(3.0, 3.0, 3.0)
const FLASH_DECAY: float = 0.12
const BURN_FLASH_COLOR := Color(1.0, 0.55, 0.15)
const BURN_FLASH_MAX := 0.7
const BURN_FLASH_DECAY := 6.0
const SQUASH_SCALE: Vector2 = Vector2(1.4, 0.7)
const SQUASH_DURATION: float = 0.18
const ELITE_OUTLINE_SHADER: Shader = preload("res://shaders/visual/outline.gdshader")
const ELITE_OUTLINE_WIDTH: float = 1.0
const ELITE_GLOW_INTENSITY: float = 2.0
const ELITE_TINT_BLEND: float = 0.35
const FOOTSTEP_MIN_SPEED_SQ: float = 100.0

const TARGETED_SPEED_MULT: float = 1.3
const TARGETED_COOLDOWN_MULT: float = 0.6
const PASSIVE_SPEED_MULT: float = 0.7
const PASSIVE_COOLDOWN_MULT: float = 1.5


var health: int
var drop_table: DropTable = null
var weapon: Weapon = null
var _knockback_velocity: Vector2 = Vector2.ZERO
var _body_radius: float = DEFAULT_BODY_RADIUS
var _base_modulate: Color = Color.WHITE
var _elite_tint_color: Color = Color.WHITE
var _burn_flash: float = 0.0
var _flash_tween: Tween = null
var _squash_tween: Tween = null
var _death_tween: Tween = null
var _death_vfx: DeathDissolveVfx = null

var _state: int = State.WANDER
var _state_timer: float = 0.0

var _prev_state: int = State.WANDER
var _player_ref: Node2D = null
var _world_manager: Node = null
var _status_component: Node = null
var _attack_range: float = 32.0
var _player_in_range: bool = false
var _aggroed: bool = false
var _speed_base: float = 0.0
var _teleport_cooldown: float = 0.0
var _elite_enraged: bool = false
var _weapon_visual: Node2D = null
var _weapon_sprite: Sprite2D = null
var _animator: EnemyAnimator = null
var _hurt_vfx: HurtSparkVfx = null
var _footstep_vfx: FootstepDustVfx = null
var _footstep_timer: float = 0.0
var _windup_vfx: WindupTelegraphVfx = null
var _attack_vfx: AttackSlashVfx = null
var _director = null

var _attack_started: bool = false

var _wander_direction: Vector2 = Vector2.RIGHT
var _wander_timer: float = 0.0
var _wander_is_paused: bool = true

var _exclaim_label: Label = null
var _exclaim_tween: Tween = null


func _ready() -> void:
	add_to_group("attackable")
	add_to_group("gas_interactors")
	_body_radius = _measure_body_radius()
	health = max_health
	_speed_base = speed
	_apply_damage_scale()
	motion_mode = MOTION_MODE_FLOATING

	if is_elite:
		_apply_elite_scaling()
	_animator = get_node_or_null("EnemyAnimator")
	if is_inside_tree():
		_player_ref = get_tree().get_first_node_in_group("player")
		_world_manager = get_tree().get_first_node_in_group("world_manager")

	_weapon_visual = Node2D.new()
	_weapon_visual.name = "WeaponVisual"
	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.name = "Sprite2D"
	_weapon_visual.add_child(_weapon_sprite)
	add_child(_weapon_visual)

	_exclaim_label = Label.new()
	_exclaim_label.name = "ExclaimLabel"
	_exclaim_label.text = "!"
	_exclaim_label.position = Vector2(0, -16)
	_exclaim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exclaim_label.add_theme_font_size_override("font_size", 22)
	_exclaim_label.add_theme_color_override("font_color", Color.RED)
	_exclaim_label.scale = Vector2.ZERO
	add_child(_exclaim_label)

	var hurt_vfx := HurtSparkVfx.new()
	hurt_vfx.name = "HurtSparkVfx"
	add_child(hurt_vfx)
	_hurt_vfx = hurt_vfx

	var footstep_vfx := FootstepDustVfx.new()
	footstep_vfx.name = "FootstepDustVfx"
	add_child(footstep_vfx)
	_footstep_vfx = footstep_vfx

	var windup_vfx := WindupTelegraphVfx.new()
	windup_vfx.name = "WindupTelegraphVfx"
	add_child(windup_vfx)
	_windup_vfx = windup_vfx

	var attack_vfx := AttackSlashVfx.new()
	attack_vfx.name = "AttackSlashVfx"
	add_child(attack_vfx)
	_attack_vfx = attack_vfx

	var death_vfx := DeathDissolveVfx.new()
	death_vfx.name = "DeathDissolveVfx"
	add_child(death_vfx)
	_death_vfx = death_vfx

	_setup_weapon_visual.call_deferred()
	_roll_weapon_modifier()

	var status := StatusComponent.new()
	status.name = "StatusComponent"
	add_child(status)
	_status_component = status

	var visuals := StatusVisuals.new()
	visuals.name = "StatusVisuals"
	add_child(visuals)
	visuals.setup(status, Vector2(0.0, -14.0))
	status.burn_tick.connect(_on_burn_tick)


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
	_apply_elite_visuals()


func _apply_elite_visuals() -> void:
	_elite_tint_color = _elite_outline_tint(elite_ability)
	var sprite := get_node_or_null("Sprite2D")
	if sprite == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = ELITE_OUTLINE_SHADER
	mat.set_shader_parameter("outline_width", ELITE_OUTLINE_WIDTH)
	mat.set_shader_parameter("outline_color", _elite_tint_color)
	mat.set_shader_parameter("glow_intensity", ELITE_GLOW_INTENSITY)
	sprite.material = mat


static func _elite_outline_tint(ability: int) -> Color:
	match ability:
		EliteAbility.FAST:
			return Color(0.3, 0.9, 1.0)
		EliteAbility.TANK:
			return Color(0.6, 0.6, 0.65)
		EliteAbility.TELEPORT:
			return Color(0.7, 0.3, 1.0)
		EliteAbility.ENRAGE:
			return Color(1.0, 0.2, 0.2)
	return Color(1.0, 0.85, 0.3)


func _apply_damage_scale() -> void:
	if weapon != null and damage_scale != 1.0:
		weapon.damage *= damage_scale


func _process(delta: float) -> void:
	if _state == State.DEATH:
		_process_death(delta)
		return

	if _status_component != null and _status_component.is_stunned():
		velocity = Vector2.ZERO
		return

	if _teleport_cooldown > 0.0:
		_teleport_cooldown -= delta

	_update_player_in_range()

	if _state == State.HURT:
		_process_hurt(delta)
		_apply_enrage_if_needed()
	else:
		_tick_knockback(delta)
		_apply_enrage_if_needed()

		match _state:
			State.WANDER:
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


func _physics_process(delta: float) -> void:
	if _state == State.DEATH:
		return
	if not is_finite(velocity.x) or not is_finite(velocity.y):
		velocity = Vector2.ZERO
	var tint_status := _status_component
	if tint_status:
		_base_modulate = tint_status.get_blended_tint()
		if is_elite:
			_base_modulate = _base_modulate.lerp(_elite_tint_color, ELITE_TINT_BLEND)
		if _burn_flash > 0.0:
			_burn_flash = maxf(0.0, _burn_flash - delta * BURN_FLASH_DECAY)
		if not (_flash_tween and _flash_tween.is_valid()):
			var sprite := get_node_or_null("Sprite2D")
			if sprite:
				var m := _base_modulate
				if _burn_flash > 0.0:
					m = m.lerp(BURN_FLASH_COLOR, _burn_flash * BURN_FLASH_MAX)
				sprite.modulate = m
	if _state == State.WANDER or _state == State.CHASE or _state == State.HURT \
			or (_state == State.ATTACK and _moves_during_attack()):
		_move_with_clamp(delta)
	_resolve_crowd_overlap()
	if _animator:
		var moving := velocity.length_squared() > 4.0
		var ratio := 0.0
		if speed > 0.001:
			ratio = clampf(velocity.length() / speed, 0.0, 1.0)
		_animator.tick(delta, moving, ratio)
	if _uses_footstep_vfx() and _state == State.CHASE and velocity.length_squared() > FOOTSTEP_MIN_SPEED_SQ:
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = FootstepDustVfx.FOOTSTEP_INTERVAL
			if _footstep_vfx:
				_footstep_vfx.puff()
	else:
		_footstep_timer = 0.0


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


func _process_idle(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
		_change_state(State.CHASE)
		return

	if _get_director() != null and _world_manager != null and is_instance_valid(_world_manager):
		var grid = _world_manager.swarm_grid
		if grid != null:
			var neighbors: Array = grid.query_neighbors(global_position)
			if EncounterDirector.should_aggro_from_neighbors(self, neighbors):
				_aggroed = true
				_change_state(State.CHASE)
				return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		if _wander_is_paused:
			_wander_is_paused = false
			_wander_direction = Vector2.RIGHT.rotated(randf() * TAU)
			_wander_timer = randf_range(1.0, 3.0)
		else:
			_wander_is_paused = true
			velocity = Vector2.ZERO
			_wander_timer = randf_range(0.5, 1.5)
			return

	if not _wander_is_paused:
		velocity = _wander_direction * _get_effective_speed() * 0.5


func _process_chase(_delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_aggroed = false
		_change_state(State.WANDER)
		return

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	var sees := _can_see_player()

	if sees:
		_aggroed = true
	elif not _aggroed:
		_change_state(State.WANDER)
		return

	if dist < 1.0:
		velocity = Vector2.ZERO
		return

	if sees and dist <= _attack_range:
		velocity = Vector2.ZERO
		_change_state(State.WINDUP)
		return

	var move_dir: Vector2
	if sees:
		move_dir = _safe_normalized(to_player)
	else:
		var fd := _nav_field_dir()
		if fd != Vector2.ZERO:
			move_dir = fd
		else:
			move_dir = _safe_normalized(to_player)

	move_dir = _apply_separation(move_dir)
	velocity = move_dir * _get_effective_speed()


func _process_windup(delta: float) -> void:
	if _status_component != null and _status_component.is_stunned():
		_change_state(State.CHASE)
		return
	_state_timer -= delta
	if not _can_see_player():
		_hide_exclaim()
		_change_state(State.WANDER)
		return
	if _state_timer <= 0.0:
		_hide_exclaim()
		_change_state(State.ATTACK)


func _process_attack(_delta: float) -> void:
	if _status_component != null and _status_component.is_stunned():
		_change_state(State.CHASE)
		return
	if not _attack_started:
		_attack_started = true
		_execute_attack()
		if _uses_attack_slash_vfx() and _attack_vfx:
			_attack_vfx.play(get_facing_direction())
	if not _attack_in_progress():
		_change_state(State.COOLDOWN)


func _attack_in_progress() -> bool:
	return false


func _moves_during_attack() -> bool:
	return false


func _uses_footstep_vfx() -> bool:
	return false


func _uses_windup_telegraph_vfx() -> bool:
	return true


func _uses_attack_slash_vfx() -> bool:
	return true


func _process_cooldown(delta: float) -> void:
	_state_timer -= delta
	if not is_finite(velocity.x) or not is_finite(velocity.y):
		velocity = Vector2.ZERO
	else:
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)
	if _state_timer <= 0.0:
		if _player_ref and is_instance_valid(_player_ref) and _player_in_range:
			_change_state(State.CHASE)
		else:
			_change_state(State.WANDER)


func _process_hurt(delta: float) -> void:
	_state_timer -= delta
	if not is_finite(_knockback_velocity.x) or not is_finite(_knockback_velocity.y):
		_knockback_velocity = Vector2.ZERO
	else:
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
		sprite.rotation = lerp_angle(sprite.rotation, _death_rotation_target(), t)
	if _state_timer <= 0.0:
		_spawn_drops()
		queue_free()


func _death_rotation_target() -> float:
	if _knockback_velocity.length_squared() > 0.0:
		return _knockback_velocity.angle()
	return get_facing_direction().angle()


func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent(), 2.5 if is_elite else 1.0)
	if weapon and DropTable.roll_should_drop_weapon(enemy_tier):
		_spawn_weapon_drop()


func _spawn_weapon_drop() -> void:
	var drop_scene := preload("res://scenes/weapon_drop.tscn")
	var drop: Node = drop_scene.instantiate()
	drop.weapon = weapon
	drop.global_position = global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	get_parent().add_child(drop)


func _apply_separation(move_dir: Vector2) -> Vector2:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return move_dir
	var grid = _world_manager.swarm_grid
	if grid == null:
		return move_dir
	var sep := Vector2.ZERO
	for enemy in grid.query_neighbors(global_position):
		if enemy == self or not is_instance_valid(enemy):
			continue
		var to_other: Vector2 = global_position - enemy.global_position
		var dist: float = to_other.length()
		if dist < separation_radius and dist > 0.001:
			sep += to_other / dist * ((separation_radius - dist) / separation_radius)
	if sep == Vector2.ZERO:
		return move_dir
	return _safe_normalized(move_dir + sep * separation_weight)


## Push this body out of any neighbor it overlaps. Each body resolves HALF of a
## pair's overlap; the neighbor resolves its own half, so the pair separates
## symmetrically without oscillating. Runs every non-DEATH frame, so stationary
## enemies (windup/attack/cooldown) spread out too. Wall-safe: corrections that
## would enter solid terrain are dropped.
func _resolve_crowd_overlap() -> void:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return
	var grid = _world_manager.swarm_grid
	if grid == null:
		return
	var push := Vector2.ZERO
	for enemy in grid.query_neighbors(global_position):
		if enemy == self or not is_instance_valid(enemy):
			continue
		var other_radius: float = DEFAULT_BODY_RADIUS
		if "_body_radius" in enemy:
			other_radius = enemy._body_radius
		var min_dist: float = (_body_radius + other_radius) * crowd_spacing_scale
		var to_self: Vector2 = global_position - enemy.global_position
		var dist: float = to_self.length()
		if dist >= min_dist:
			continue
		var dir: Vector2
		if dist > 0.001:
			dir = to_self / dist
		else:
			# Coincident: split deterministically along X by instance-id order so
			# the pair always pushes apart (never the same direction).
			var sign_dir: float = 1.0 if get_instance_id() > enemy.get_instance_id() else -1.0
			dir = Vector2(sign_dir, 0.0)
		push += dir * ((min_dist - dist) * 0.5)
	if push == Vector2.ZERO:
		return
	var push_len := push.length()
	if push_len > CROWD_PUSH_CAP:
		push = push / push_len * CROWD_PUSH_CAP
	_apply_crowd_push(push)


## Apply a small positional correction, clamped per-axis against solid cells so a
## crowd in a corridor is never shoved into a wall. The caller caps total push at
## CROWD_PUSH_CAP (4.0), well under MOVE_STEP_PX (8.0), so per-axis EDGE_CHECKS
## cannot tunnel.
func _apply_crowd_push(offset: Vector2) -> void:
	if offset.x != 0.0 and not _edge_blocked(Vector2(offset.x, 0.0)):
		global_position.x += offset.x
	if offset.y != 0.0 and not _edge_blocked(Vector2(0.0, offset.y)):
		global_position.y += offset.y


func _safe_normalized(v: Vector2) -> Vector2:
	if not is_finite(v.x) or not is_finite(v.y):
		return Vector2.ZERO
	var l := v.length()
	if l > 0.001:
		return v / l
	return Vector2.ZERO


func _nav_field_dir() -> Vector2:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return Vector2.ZERO
	var nf = _world_manager.get("nav_field")
	if nf == null:
		return Vector2.ZERO
	return nf.sample_direction(global_position)


func _is_blocked(pos: Vector2) -> bool:
	if _world_manager == null or not is_instance_valid(_world_manager):
		return false
	var nf = _world_manager.get("nav_field")
	if nf == null:
		return false
	return nf.is_solid_world(pos)


func _move_with_clamp(delta: float) -> void:
	var motion := velocity * delta
	# Sub-step so a single step never exceeds one nav cell. Without this, fast
	# knockback can tunnel straight through a thin wall in one frame.
	var steps := maxi(1, ceili(motion.length() / MOVE_STEP_PX))
	var step := motion / float(steps)
	for _i in range(steps):
		if step.x != 0.0 and not _edge_blocked(Vector2(step.x, 0.0)):
			global_position.x += step.x
		elif step.x != 0.0:
			step.x = 0.0
			velocity.x = 0.0
		if step.y != 0.0 and not _edge_blocked(Vector2(0.0, step.y)):
			global_position.y += step.y
		elif step.y != 0.0:
			step.y = 0.0
			velocity.y = 0.0
		if step == Vector2.ZERO:
			break


## True if moving the body's leading edge by `step` (a single-axis delta) would
## put part of the body inside a solid cell. Samples the leading face's centre
## and both corners so the body half-width can't sink into a wall.
func _edge_blocked(step: Vector2) -> bool:
	var len_sq := step.length_squared()
	if len_sq < 0.0001:
		return false
	var axis := step / sqrt(len_sq)
	var perp := Vector2(-axis.y, axis.x)
	var lead := global_position + axis * _body_radius + step
	for t in [-1.0, 0.0, 1.0]:
		if _is_blocked(lead + perp * (_body_radius * t)):
			return true
	return false


## Largest half-extent of the body's collision shape, used for edge sampling.
func _measure_body_radius() -> float:
	for owner_id in get_shape_owners():
		var xform: Transform2D = shape_owner_get_transform(owner_id)
		for i in range(shape_owner_get_shape_count(owner_id)):
			var shape: Shape2D = shape_owner_get_shape(owner_id, i)
			var rect := Rect2()
			if shape is CircleShape2D:
				var r: float = (shape as CircleShape2D).radius
				rect = Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
			elif shape is RectangleShape2D:
				var half: Vector2 = (shape as RectangleShape2D).size * 0.5
				rect = Rect2(-half, half * 2.0)
			elif shape is CapsuleShape2D:
				var cs := shape as CapsuleShape2D
				var h := cs.height * 0.5 + cs.radius
				rect = Rect2(Vector2(-cs.radius, -h), Vector2(cs.radius * 2.0, h * 2.0))
			else:
				continue
			rect = xform * rect
			return maxf(rect.size.x, rect.size.y) * 0.5
	return DEFAULT_BODY_RADIUS


func _change_state(new_state: int) -> void:
	if new_state == State.HURT:
		_prev_state = _state
		_state = new_state
		_state_timer = hurt_duration
		return

	_state = new_state
	match new_state:
		State.ATTACK:
			_attack_started = false
		State.WINDUP:
			_state_timer = windup_duration
			_show_exclaim()
		State.COOLDOWN:
			_state_timer = cooldown_duration * _get_cooldown_multiplier()
		State.DEATH:
			_state_timer = death_duration
			_death_tween = null
			if _death_vfx:
				_death_vfx.burst(_base_modulate)


func _show_exclaim() -> void:
	if _exclaim_label == null:
		return
	if _exclaim_tween and _exclaim_tween.is_valid():
		_exclaim_tween.kill()
	_exclaim_label.scale = Vector2.ZERO
	_exclaim_tween = create_tween()
	_exclaim_tween.set_trans(Tween.TRANS_BACK)
	_exclaim_tween.set_ease(Tween.EASE_OUT)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2(1.2, 1.2), 0.05)
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2.ONE, 0.05)
	if _uses_windup_telegraph_vfx() and _windup_vfx:
		_windup_vfx.play()


func _hide_exclaim() -> void:
	if _exclaim_label == null:
		return
	if _exclaim_tween and _exclaim_tween.is_valid():
		_exclaim_tween.kill()
	_exclaim_tween = create_tween()
	_exclaim_tween.tween_property(_exclaim_label, "scale", Vector2.ZERO, 0.05)


func _execute_attack() -> void:
	pass


func _can_see_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	if not is_inside_tree():
		return false
	var world := get_world_2d()
	if world == null:
		return false
	var space_state := world.direct_space_state
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
	_on_hit()
	if health <= 0:
		_change_state(State.DEATH)
		die()
		return
	if _state != State.HURT:
		_prev_state = _state
	_state = State.HURT
	_state_timer = hurt_duration


func apply_status_damage(amount: int) -> void:
	# Quiet DoT path: drains health without forcing HURT state.
	if amount <= 0 or _state == State.DEATH:
		return
	if GameModeManager.is_creative():
		amount = max_health
	health -= amount
	health_changed.emit(health, max_health)
	_play_hit_flash()
	if health <= 0:
		_change_state(State.DEATH)
		die()


func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		apply_knockback(hit_dir, KNOCKBACK_SPEED)
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

	var blood_dir := hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector2.ZERO
	var splatter_count := 5 if lethal else 3
	var base_radius := 11.0 if lethal else 8.0
	var base_speed := 280.0 if lethal else 200.0
	TerrainSurface.place_blood(impact_point, base_radius, base_speed, blood_dir)
	for i in range(splatter_count):
		var spread_angle := randf_range(-0.7, 0.7)
		var dir := blood_dir.rotated(spread_angle) if blood_dir != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
		var dist := randf_range(4.0, 14.0)
		var offset := dir * dist
		var radius := base_radius * randf_range(0.4, 0.9)
		var speed := base_speed * randf_range(0.7, 1.4)
		TerrainSurface.place_blood(impact_point + offset, radius, speed, dir)

	if is_elite and elite_ability == EliteAbility.TELEPORT and _teleport_cooldown <= 0.0:
		var angle := randf() * TAU
		global_position += Vector2(cos(angle), sin(angle)) * 64.0
		_teleport_cooldown = 0.5

	hit(damage)


func die() -> void:
	var dir = _get_director()
	if dir != null:
		dir.unregister(self)
	died.emit()
	_on_death()


func _update_player_in_range() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_in_range = false
		return
	var r: float = detection_radius
	_player_in_range = global_position.distance_squared_to(_player_ref.global_position) <= r * r


func _tick_knockback(delta: float) -> void:
	if not is_finite(_knockback_velocity.x) or not is_finite(_knockback_velocity.y):
		_knockback_velocity = Vector2.ZERO
		return
	if _knockback_velocity.length_squared() < 1.0:
		_knockback_velocity = Vector2.ZERO
		return
	_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)


func apply_knockback(direction: Vector2, strength: float) -> void:
	if not is_finite(direction.x) or not is_finite(direction.y):
		return
	if direction.length_squared() > 0.0001:
		_knockback_velocity += direction / direction.length() * strength


func _set_base_modulate(c: Color) -> void:
	_base_modulate = c
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = c


func _on_burn_tick() -> void:
	_burn_flash = 1.0


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
	if _hurt_vfx:
		_hurt_vfx.burst()


func _setup_weapon_visual() -> void:
	if weapon and weapon.has_visual():
		weapon.setup_visual(_weapon_visual, _weapon_sprite)


func _roll_weapon_modifier() -> void:
	if weapon == null:
		return
	var modifier := DropTable.roll_modifier_for_enemy(enemy_tier)
	if modifier == null:
		return
	var slot := weapon.find_empty_modifier_slot()
	if slot >= 0:
		weapon.add_modifier(slot, modifier)


func _on_death() -> void:
	pass


func is_pursuing() -> bool:
	return _aggroed


func _get_director():
	if _director != null:
		return _director
	if _world_manager != null and is_instance_valid(_world_manager):
		_director = _world_manager.get("encounter_director")
	return _director


func get_facing_direction() -> Vector2:
	if _player_ref and is_instance_valid(_player_ref):
		var d := _player_ref.global_position - global_position
		if d.length() > 0.01:
			return d.normalized()
	return Vector2.DOWN


func _is_targeted() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return _player_ref.get("targeted_enemy") == self


func _get_effective_speed() -> float:
	var base := _base_effective_speed()
	if _status_component != null and is_instance_valid(_status_component):
		base *= _status_component.get_move_speed_multiplier()
	return _apply_catch_up(base)


func _apply_catch_up(base: float) -> float:
	if not _aggroed or _player_ref == null or not is_instance_valid(_player_ref):
		return base
	var dist := global_position.distance_to(_player_ref.global_position)
	var player_speed: float = 120.0
	if "max_speed" in _player_ref:
		player_speed = _player_ref.max_speed
	return EncounterDirector.catch_up_speed(base, dist, player_speed)


func _base_effective_speed() -> float:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return speed
	var target = _player_ref.get("targeted_enemy")
	if target == null:
		return speed
	if target == self:
		return speed * TARGETED_SPEED_MULT
	return speed * PASSIVE_SPEED_MULT


func _get_cooldown_multiplier() -> float:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return 1.0
	var target = _player_ref.get("targeted_enemy")
	if target == null:
		return 1.0
	if target == self:
		return TARGETED_COOLDOWN_MULT
	return PASSIVE_COOLDOWN_MULT
