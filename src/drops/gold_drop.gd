class_name GoldDrop
extends Drop

var amount: int = 1


func set_amount(value: int) -> void:
	amount = value


func _ready() -> void:
	super._ready()
	_sprite.modulate = Color(1.0, 0.84, 0.0)


func _pickup(player: Node) -> void:
	var wallet := player.get_node_or_null("WalletComponent")
	if wallet:
		wallet.add_gold(amount)
	queue_free()
