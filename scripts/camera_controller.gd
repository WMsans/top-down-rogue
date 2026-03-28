extends Camera2D

@export var move_speed: float = 400.0

func _process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_key_pressed(KEY_D):
		input.x += 1
	if Input.is_key_pressed(KEY_W):
		input.y -= 1
	if Input.is_key_pressed(KEY_S):
		input.y += 1
	if input != Vector2.ZERO:
		position += input.normalized() * move_speed * delta
