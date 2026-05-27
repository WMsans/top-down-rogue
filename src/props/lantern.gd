extends Node2D

@onready var _light: PointLight2D = $Light
var _base_energy: float = 1.2
var _amplitude: float = 0.08
var _phase: float = 0.0

func _ready() -> void:
	if has_meta("flicker_base_energy"):
		_base_energy = get_meta("flicker_base_energy")
	if has_meta("flicker_amplitude"):
		_amplitude = get_meta("flicker_amplitude")
	_phase = randf() * TAU

func _process(delta: float) -> void:
	if _light == null:
		return
	_phase += delta * 8.0
	var jitter: float = sin(_phase) * 0.6 + sin(_phase * 2.3) * 0.4
	_light.energy = _base_energy + jitter * _amplitude
