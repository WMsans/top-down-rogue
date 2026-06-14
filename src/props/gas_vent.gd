extends Node2D

const EMIT_INTERVAL := 5.0
const EMIT_RADIUS := 6.0
const EMIT_DENSITY := 80

var _timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= EMIT_INTERVAL:
		_timer -= EMIT_INTERVAL
		TerrainSurface.place_gas(global_position, EMIT_RADIUS, EMIT_DENSITY)