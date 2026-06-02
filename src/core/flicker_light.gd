class_name FlickerLight
extends PointLight2D

## A PointLight2D that gently flickers its energy.
## base_energy is captured from `energy` on _ready unless set explicitly.

var base_energy: float = 1.0
var amplitude: float = 0.08
var _phase: float = 0.0

func _ready() -> void:
	base_energy = energy
	_phase = randf() * TAU

func _process(delta: float) -> void:
	if amplitude <= 0.0:
		energy = base_energy
		set_process(false)
		return
	_phase += delta * 8.0
	var jitter: float = sin(_phase) * 0.6 + sin(_phase * 2.3) * 0.4
	energy = base_energy + jitter * amplitude
