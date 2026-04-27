extends Node

# HitStop constants
const HIT_STOP_BASE: float = 0.06
const HIT_STOP_KILL_BONUS: float = 0.04

# ScreenShake constants
const SHAKE_AMOUNT: float = 3.0
const SHAKE_DURATION: float = 0.18

# HitSpark constants
const SPARK_COUNT_MIN: int = 6
const SPARK_COUNT_MAX: int = 8
const SPARK_SPEED_MIN: float = 80.0
const SPARK_SPEED_MAX: float = 160.0
const SPARK_LIFETIME: float = 0.15
const SPARK_CONE_HALF_ANGLE: float = PI / 6.0
const SPARK_SIZE: Vector2 = Vector2(2, 2)

# DamageNumber constants
const DAMAGE_NUMBER_LIFETIME: float = 0.6
const HOLD_FRACTION: float = 2.0 / 3.0
const POP_DURATION: float = 0.12
const POP_SCALE: Vector2 = Vector2(1.2, 1.2)
const INITIAL_VELOCITY_Y: float = -80.0
const INITIAL_VELOCITY_X_RANGE: float = 30.0
const GRAVITY: float = 200.0
const SPAWN_OFFSET: Vector2 = Vector2(0, -8)

# ChromaticFlash constants
const CHROMATIC_STRENGTH: float = 0.6
const CHROMATIC_DURATION: float = 0.12

const DAMAGE_NUMBER_SCENE := preload("res://scenes/fx/damage_number.tscn")
const CHROMATIC_FLASH_SCENE := preload("res://scenes/fx/chromatic_flash.tscn")

# Screen shake state
var _shake_amount: float = 0.0
var _shake_duration: float = 0.0
var _shake_elapsed: float = 0.0
var _shake_dir_bias: Vector2 = Vector2.ZERO

# Hit stop state
var _active_stop_timer: SceneTreeTimer = null

# Chromatic flash state
var _chromatic_layer: CanvasLayer = null
var _chromatic_rect: ColorRect = null
var _chromatic_material: ShaderMaterial = null
var _chromatic_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_chromatic_flash()


func play(spec: HitSpec) -> void:
	var dmg_int: int = floori(spec.damage)
	_spawn_sparks(spec.position, spec.direction, spec.source_color)
	_spawn_damage_number(spec.position, dmg_int)
	_do_screen_shake(spec.damage, spec.is_kill, spec.direction)
	_do_chromatic_flash(spec.damage, spec.is_kill)
	_do_hit_stop(spec.damage, spec.is_kill)


# ---- HitSpark adapter ----

func _spawn_sparks(point: Vector2, dir: Vector2, color: Color) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var base_angle: float = dir.angle() if dir.length_squared() > 0.0001 else 0.0
	var count: int = randi_range(SPARK_COUNT_MIN, SPARK_COUNT_MAX)
	for i in count:
		var spark := ColorRect.new()
		spark.color = color
		spark.size = SPARK_SIZE
		spark.pivot_offset = SPARK_SIZE / 2.0
		spark.position = point - SPARK_SIZE / 2.0
		spark.z_index = 100
		spark.z_as_relative = false
		scene_root.add_child(spark)
		var angle := base_angle + randf_range(-SPARK_CONE_HALF_ANGLE, SPARK_CONE_HALF_ANGLE)
		var speed := randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX)
		var velocity := Vector2(cos(angle), sin(angle)) * speed
		var target_pos := spark.position + velocity * SPARK_LIFETIME
		var tween := spark.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", target_pos, SPARK_LIFETIME)
		tween.tween_property(spark, "modulate:a", 0.0, SPARK_LIFETIME)
		tween.chain().tween_callback(spark.queue_free)


# ---- DamageNumber adapter ----

func _spawn_damage_number(pos: Vector2, amount: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var label: Label = DAMAGE_NUMBER_SCENE.instantiate()
	label.text = str(amount)
	label.global_position = pos + SPAWN_OFFSET
	label.scale = Vector2(0.5, 0.5)
	label.z_index = 100
	label.z_as_relative = false
	scene_root.add_child(label)

	var hold_time: float = DAMAGE_NUMBER_LIFETIME * HOLD_FRACTION
	var fade_time: float = DAMAGE_NUMBER_LIFETIME - hold_time
	var velocity := Vector2(randf_range(-INITIAL_VELOCITY_X_RANGE, INITIAL_VELOCITY_X_RANGE), INITIAL_VELOCITY_Y)

	var pop := label.create_tween()
	pop.tween_property(label, "scale", POP_SCALE, POP_DURATION * 0.5)
	pop.tween_property(label, "scale", Vector2.ONE, POP_DURATION * 0.5)

	var motion := label.create_tween()
	motion.tween_method(_drive_damage_motion.bind(label, velocity, pos + SPAWN_OFFSET), 0.0, DAMAGE_NUMBER_LIFETIME, DAMAGE_NUMBER_LIFETIME)

	var fade := label.create_tween()
	fade.tween_interval(hold_time)
	fade.tween_property(label, "modulate:a", 0.0, fade_time)
	fade.tween_callback(label.queue_free)


func _drive_damage_motion(t: float, label: Label, initial_vel: Vector2, start_pos: Vector2) -> void:
	if not is_instance_valid(label):
		return
	var pos := start_pos + initial_vel * t + Vector2(0, 0.5 * GRAVITY * t * t)
	label.global_position = pos


# ---- ScreenShake adapter ----

func _do_screen_shake(damage: float, is_kill: bool, dir: Vector2) -> void:
	var amount := SHAKE_AMOUNT
	var duration := SHAKE_DURATION
	# kill bonus: stronger shake on killing blows
	if is_kill:
		amount *= 1.5
		duration *= 1.3
	_shake_amount = amount
	_shake_duration = duration
	_shake_elapsed = 0.0
	_shake_dir_bias = dir


func _process(delta: float) -> void:
	if _shake_duration > 0.0:
		_shake_elapsed += delta
		if _shake_elapsed >= _shake_duration:
			var cam := get_viewport().get_camera_2d()
			if cam:
				cam.offset = Vector2.ZERO
			_shake_duration = 0.0
		else:
			var t: float = 1.0 - (_shake_elapsed / _shake_duration)
			var current: float = _shake_amount * t
			var rand_offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * current
			var bias := _shake_dir_bias * 0.5 * current
			var cam := get_viewport().get_camera_2d()
			if cam:
				cam.offset = rand_offset + bias


# ---- ChromaticFlash adapter ----

func _setup_chromatic_flash() -> void:
	_chromatic_layer = CHROMATIC_FLASH_SCENE.instantiate()
	add_child(_chromatic_layer)
	_chromatic_rect = _chromatic_layer.get_node("Rect")
	_chromatic_material = _chromatic_rect.material as ShaderMaterial
	_chromatic_material.set_shader_parameter("strength", 0.0)


func _do_chromatic_flash(damage: float, is_kill: bool) -> void:
	if _chromatic_material == null:
		return
	var strength := CHROMATIC_STRENGTH
	var duration := CHROMATIC_DURATION
	if is_kill:
		strength *= 1.4
		duration *= 1.3
	if _chromatic_tween and _chromatic_tween.is_valid():
		_chromatic_tween.kill()
	_chromatic_material.set_shader_parameter("strength", strength)
	_chromatic_tween = create_tween()
	_chromatic_tween.tween_method(_set_chromatic_strength, strength, 0.0, duration)


func _set_chromatic_strength(value: float) -> void:
	if _chromatic_material:
		_chromatic_material.set_shader_parameter("strength", value)


# ---- HitStop adapter ----

func _do_hit_stop(damage: float, is_kill: bool) -> void:
	var duration: float = HIT_STOP_BASE
	if is_kill:
		duration += HIT_STOP_KILL_BONUS
	if duration <= 0.0:
		return
	Engine.time_scale = 0.0
	_active_stop_timer = get_tree().create_timer(duration, true, false, true)
	var my_timer := _active_stop_timer
	await my_timer.timeout
	if _active_stop_timer == my_timer:
		Engine.time_scale = 1.0
		_active_stop_timer = null
