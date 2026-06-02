extends Node2D

## Thin adapter: maps the metas set by FeatureLanternCluster onto the
## FlickerLight that drives the lantern's glow. Flicker math lives in FlickerLight.

@onready var _light: FlickerLight = $Light as FlickerLight

func _ready() -> void:
	if _light == null:
		return
	if has_meta("flicker_base_energy"):
		_light.base_energy = get_meta("flicker_base_energy")
		_light.energy = _light.base_energy
	if has_meta("flicker_amplitude"):
		_light.amplitude = get_meta("flicker_amplitude")
