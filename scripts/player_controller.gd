extends CharacterBody2D

@export var max_speed: float = 120.0
@export var acceleration: float = 800.0
@export var friction: float = 600.0


func _physics_process(delta: float) -> void:
	var input_dir := _get_input_direction()

	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	return dir.normalized()
