extends Node

const DAMAGE_NUMBER_LIFETIME: float = 0.6
const HOLD_FRACTION: float = 2.0 / 3.0
const POP_DURATION: float = 0.12
const POP_SCALE: Vector2 = Vector2(1.2, 1.2)
const INITIAL_VELOCITY_Y: float = -80.0
const INITIAL_VELOCITY_X_RANGE: float = 30.0
const GRAVITY: float = 200.0
const SPAWN_OFFSET: Vector2 = Vector2(0, -8)

const SCENE := preload("res://scenes/fx/damage_number.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func spawn(pos: Vector2, amount: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var label: Label = SCENE.instantiate()
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
	motion.tween_method(_drive_motion.bind(label, velocity, pos + SPAWN_OFFSET), 0.0, DAMAGE_NUMBER_LIFETIME, DAMAGE_NUMBER_LIFETIME)

	var fade := label.create_tween()
	fade.tween_interval(hold_time)
	fade.tween_property(label, "modulate:a", 0.0, fade_time)
	fade.tween_callback(label.queue_free)


func _drive_motion(t: float, label: Label, initial_vel: Vector2, start_pos: Vector2) -> void:
	if not is_instance_valid(label):
		return
	var pos := start_pos + initial_vel * t + Vector2(0, 0.5 * GRAVITY * t * t)
	label.global_position = pos
