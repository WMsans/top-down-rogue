class_name SpectralEchoModifier
extends ProjectileModifier

const ECHO_DELAY := 0.3
const ECHO_DAMAGE := 3.0

func _init() -> void:
	name = "Spectral Echo"
	description = "A ghostly copy repeats your swing a moment later."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	var tree := _user.get_tree()
	if tree == null:
		return
	var origin: Vector2 = _ctx.get("origin", Vector2.ZERO)
	var dir: Vector2 = _ctx.get("direction", Vector2.RIGHT)
	tree.create_timer(ECHO_DELAY).timeout.connect(_spawn_echo.bind(_user, origin, dir))

func _spawn_echo(user: Node, origin: Vector2, direction: Vector2) -> void:
	if not is_instance_valid(user):
		return
	ModifierProjectile.spawn_one(user, origin, direction, ECHO_DAMAGE,
		{ "tint": Color(0.7, 0.7, 1.0, 0.5) })
