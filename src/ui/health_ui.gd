extends CanvasLayer

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")

@onready var _bar_background: ColorRect = %BarBackground
@onready var _bar_fill: ColorRect = %BarFill
@onready var _health_label: Label = %HealthLabel

var _health_component: HealthComponent


func _ready() -> void:
	_apply_theme()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.health_changed.connect(_on_health_changed)
		_health_component.died.connect(_on_died)
		_on_health_changed(_health_component.max_health, _health_component.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	_bar_fill.size.x = _bar_background.size.x * (float(current) / float(maximum))
	_health_label.text = "%d / %d" % [current, maximum]


func _on_died() -> void:
	_bar_fill.size.x = 0.0
	_health_label.text = "0 / %d" % _health_component.max_health


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	_health_label.theme = t
