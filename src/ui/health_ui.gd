extends CanvasLayer

const SHIMMER_SHADER := preload("res://shaders/ui/health_bar_shimmer.gdshader")

@onready var _bar_background: PanelContainer = %BarBackground
@onready var _bar_fill: ColorRect = %BarFill
@onready var _health_label: Label = %HealthLabel

var _health_component: HealthComponent
var _low_health_tween: Tween = null
var _bar_bg_style: StyleBoxFlat


func _ready() -> void:
	theme = UiTheme.get_theme()
	_bar_bg_style = _bar_background.get_theme_stylebox("panel") as StyleBoxFlat
	if _bar_bg_style:
		_bar_bg_style = _bar_bg_style.duplicate()
		_bar_background.add_theme_stylebox_override("panel", _bar_bg_style)

	var shimmer_mat := ShaderMaterial.new()
	shimmer_mat.shader = SHIMMER_SHADER
	_bar_fill.material = shimmer_mat

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.health_changed.connect(_on_health_changed)
		_health_component.died.connect(_on_died)
		_on_health_changed(_health_component.max_health, _health_component.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	var ratio := float(current) / float(maximum)
	_bar_fill.size.x = _bar_background.size.x * ratio

	var current_str := "%d" % current
	var max_str := " / %d" % maximum
	_health_label.clear()
	_health_label.push_color(UiTheme.ACCENT_GOLD)
	_health_label.append_text(current_str)
	_health_label.pop()
	_health_label.push_color(UiTheme.TEXT_SECONDARY)
	_health_label.append_text(max_str)
	_health_label.pop()

	if _bar_bg_style:
		if ratio <= 0.25:
			_start_low_health_pulse()
		else:
			_stop_low_health_pulse()

	if current < maximum:
		_flash_damage()


func _on_died() -> void:
	_bar_fill.size.x = 0.0
	_health_label.clear()
	_health_label.push_color(UiTheme.DANGER)
	_health_label.append_text("0")
	_health_label.pop()
	_health_label.push_color(UiTheme.TEXT_SECONDARY)
	_health_label.append_text(" / %d" % _health_component.max_health)
	_health_label.pop()
	_stop_low_health_pulse()


func _flash_damage() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_bar_fill, "color", Color.WHITE, 0.05)
	tween.tween_property(_bar_fill, "color", Color(1, 1, 1, 1), 0.05)


func _start_low_health_pulse() -> void:
	if _low_health_tween != null and _low_health_tween.is_valid():
		return
	if _bar_bg_style:
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_loops()
		tween.tween_property(_bar_bg_style, "border_color", UiTheme.ACCENT, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(_bar_bg_style, "border_color", UiTheme.DANGER, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_low_health_pulse() -> void:
	if _low_health_tween != null:
		_low_health_tween.kill()
		_low_health_tween = null
	if _bar_bg_style:
		_bar_bg_style.border_color = UiTheme.PANEL_BORDER