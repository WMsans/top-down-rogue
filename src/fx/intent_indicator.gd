class_name IntentIndicator
extends Node2D

const FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

@onready var label: Label = $Label

var _show_tween: Tween = null
var _idle_tween: Tween = null
var _hide_tween: Tween = null

func _ready() -> void:
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = 14
	settings.font_color = Color(1.0, 0.1, 0.1, 1.0)
	settings.outline_size = 2
	settings.outline_color = Color(0, 0, 0, 1)
	label.label_settings = settings
	label.text = "!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	modulate.a = 0.0
	scale = Vector2.ZERO


func show_indicator() -> void:
	_kill_tweens()
	visible = true
	_show_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_show_tween.set_parallel(true)
	_show_tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.08).from(Vector2.ZERO).set_ease(Tween.EASE_OUT)
	_show_tween.tween_property(self, "modulate:a", 1.0, 0.08).from(0.0)
	_show_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.07).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_show_tween.chain().tween_callback(_start_idle)


func hide_indicator() -> void:
	_kill_tweens()
	_hide_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hide_tween.set_parallel(true)
	_hide_tween.tween_property(self, "scale", Vector2.ZERO, 0.1).set_ease(Tween.EASE_IN)
	_hide_tween.tween_property(self, "modulate:a", 0.0, 0.1).set_ease(Tween.EASE_IN)
	_hide_tween.chain().tween_callback(queue_free)


func _start_idle() -> void:
	_idle_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_loops()
	_idle_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _kill_tweens() -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
