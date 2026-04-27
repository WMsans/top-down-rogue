class_name GoldDrop
extends Area2D

const MAGNET_ACCELERATION: float = 800.0
const MAGNET_DRAG: float = 4.0
const MAGNET_MAX_SPEED: float = 300.0
const MAGNET_RANGE: float = 100.0
const PICKUP_RANGE: float = 6.0

var amount: int = 1

var _velocity: Vector2 = Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite2D


func set_amount(value: int) -> void:
	amount = value


func get_pickup_type() -> int:
	return Drop.PickupType.GOLD

func get_pickup_payload():
	return amount

func should_auto_pickup() -> bool:
	return true


func _ready() -> void:
	_sprite.modulate = Color(1.0, 0.84, 0.0)
	_sprite.scale = Vector2(0.6, 0.6)


func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return

	var dist_sq := global_position.distance_squared_to(player.global_position)

	if dist_sq <= MAGNET_RANGE * MAGNET_RANGE:
		var direction := global_position.direction_to(player.global_position)
		_velocity += direction * MAGNET_ACCELERATION * delta
		_velocity -= _velocity * MAGNET_DRAG * delta
		_velocity = _velocity.limit_length(MAGNET_MAX_SPEED)
		position += _velocity * delta

	if dist_sq <= PICKUP_RANGE * PICKUP_RANGE:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			wallet.add_gold(amount)
		queue_free()
