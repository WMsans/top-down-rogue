extends StaticBody2D

# World-space Y offset from the body origin marking the plaque's visual base.
# The player sorts in front when standing below this line, behind when above it.
var sort_pivot_y: float = -8.0

var _player: Node2D

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	if _player.global_position.y > global_position.y + sort_pivot_y:
		z_index = -1
	else:
		z_index = 1
