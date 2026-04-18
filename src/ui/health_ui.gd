extends CanvasLayer

const SHIMMER_SHADER := preload("res://shaders/ui/health_bar_shimmer.gdshader")

@onready var _bar_background: Panel = %BarBackground
@onready var _bar_fill: ColorRect = %BarFill
@onready var _health_label: RichTextLabel = %HealthLabel

var _health_component: HealthComponent
var _low_health_tween: Tween = null
var _bar_bg_style: StyleBoxFlat


func _ready() -> void:
	get_node("MarginContainer").theme = UiTheme.get_theme()
	_bar_bg_style = _bar_background.get_theme_stylebox("panel") as StyleBoxFlat
	if _bar_bg_style:
		_bar_bg_style = _bar_bg_style.duplicate()
		_bar_background.add_theme_stylebox_override("panel", _bar_bg_style)

	var shimmer_mat := ShaderMaterial.new()
	shimmer_mat.shader = SHIMMER_SHADER
	_bar_fill.material = shimmer_mat

	_health_label.add_theme_font_size_override("normal_font_size", 16)
	_health_label.add_theme_color_override("default_color", UiTheme.TEXT_PRIMARY)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.health_changed.connect(_on_health_changed)
		_health_component.died.connect(_on_died)
		_on_health_changed(_health_component.max_health, _health_component.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0)
	_bar_fill.anchor_right = ratio

	_bar_fill.color = _color_for_ratio(ratio)
	_render_label(current, maximum, ratio <= 0.25)

	if _bar_bg_style:
		if ratio <= 0.25:
			_start_low_health_pulse()
		else:
			_stop_low_health_pulse()

	if current < maximum:
		_flash_damage()


func _on_died() -> void:
	_bar_fill.anchor_right = 0.0
	_render_label(0, _health_component.max_health, true)
	_stop_low_health_pulse()


func _render_label(current: int, maximum: int, low: bool) -> void:
	var current_color := UiTheme.DANGER if low else UiTheme.TEXT_PRIMARY
	var max_color := UiTheme.TEXT_SECONDARY
	var bbcode := "[center][b][color=#%s]%d[/color][color=#%s] / %d[/color][/b][/center]" % [
		current_color.to_html(false),
		current,
		max_color.to_html(false),
		maximum,
	]
	_health_label.text = bbcode


func _color_for_ratio(ratio: float) -> Color:
	if ratio <= 0.25:
		return UiTheme.DANGER
	if ratio <= 0.5:
		return UiTheme.ACCENT_GOLD
	return UiTheme.ACCENT


func _flash_damage() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var bright := Color.WHITE
	var original := _bar_fill.color
	tween.tween_property(_bar_fill, "color", bright, 0.05)
	tween.tween_property(_bar_fill, "color", original, 0.15)


func _start_low_health_pulse() -> void:
	if _low_health_tween != null and _low_health_tween.is_valid():
		return
	if _bar_bg_style:
		_low_health_tween = create_tween()
		_low_health_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_low_health_tween.set_loops()
		_low_health_tween.tween_property(_bar_bg_style, "border_color", UiTheme.ACCENT, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_low_health_tween.tween_property(_bar_bg_style, "border_color", UiTheme.DANGER, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_low_health_pulse() -> void:
	if _low_health_tween != null:
		_low_health_tween.kill()
		_low_health_tween = null
	if _bar_bg_style:
		_bar_bg_style.border_color = UiTheme.PANEL_BORDER
