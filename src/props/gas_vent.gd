extends Node2D

const EMIT_INTERVAL := 1.0
const EMIT_RADIUS := 6.0
const EMIT_DENSITY := 80
const EMIT_SPEED := 120.0

var _timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= EMIT_INTERVAL:
		_timer -= EMIT_INTERVAL
		TerrainSurface.place_gas_splash(global_position, EMIT_RADIUS, EMIT_DENSITY, EMIT_SPEED)