class_name BossHud
extends CanvasLayer

const PADDING := 8
const BAR_H := 14

var _phase: int = 1
var _phase_buttons: Array = []
var _banner: Label = null
var _bar: ProgressBar = null
var _name_label: Label = null


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.position = Vector2(0, 0)
	bg.custom_minimum_size = Vector2(0, 56)
	bg.size = Vector2(get_viewport().get_visible_rect().size.x, 56)
	add_child(bg)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.position = Vector2(PADDING, 4)
	_name_label.text = ""
	add_child(_name_label)

	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.position = Vector2(PADDING, 24)
	_bar.size = Vector2(get_viewport().get_visible_rect().size.x - 2 * PADDING, BAR_H)
	_bar.show_percentage = false
	add_child(_bar)

	var pips := HBoxContainer.new()
	pips.name = "Pips"
	pips.position = Vector2(PADDING, 42)
	add_child(pips)


func setup(boss_name: String, max_health: int, phase_count: int, _thresholds: Array[int]) -> void:
	_name_label.text = boss_name
	_bar.max_value = float(max_health)
	_bar.value = float(max_health)
	var pips: HBoxContainer = get_node("Pips")
	_phase_buttons.clear()
	for c in pips.get_children():
		c.queue_free()
	for i in phase_count:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(12, 8)
		pips.add_child(pip)
		_phase_buttons.append(pip)
	if _banner != null:
		_banner.queue_free()
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 60, 8)
	_banner.modulate.a = 0.0
	add_child(_banner)
	_phase = 1


func update_health(current: int) -> void:
	_bar.value = float(clamp(current, 0, int(_bar.max_value)))


func set_phase(phase: int) -> void:
	_phase = phase
	for i in _phase_buttons.size():
		_phase_buttons[i].self_modulate = Color.WHITE if i + 1 == phase else Color(0.3, 0.3, 0.3, 0.5)
	if _banner:
		_banner.text = "PHASE %d" % phase
		var t := create_tween()
		t.tween_property(_banner, "modulate:a", 1.0, 0.15)
		t.tween_interval(0.8)
		t.tween_property(_banner, "modulate:a", 0.0, 0.5)


func show_hud() -> void:
	visible = true


func hide_hud() -> void:
	visible = false


func get_public_phase() -> int:
	return _phase
