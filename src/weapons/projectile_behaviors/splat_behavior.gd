class_name SplatBehavior
extends ProjectileBehavior

var material: String = "lava"   # "lava" or "gas"
var radius: float = 6.0
var gas_density: int = 200
var place_sink: Callable = Callable()  # injectable for tests: (mat, pos, radius, density)

var _done: bool = false


func on_enemy_hit(proj, _target) -> bool:
	_splat(proj)
	return false  # die after delivering the splat


func on_terrain_hit(proj) -> bool:
	_splat(proj)
	return false  # let the projectile carve + die normally


func on_expire(proj) -> void:
	_splat(proj)


func _splat(proj) -> void:
	if _done:
		return
	_done = true
	var pos: Vector2 = proj.global_position if proj != null else Vector2.ZERO
	if place_sink.is_valid():
		place_sink.call(material, pos, radius, gas_density)
		return
	if material == "gas":
		TerrainSurface.place_gas(pos, radius, gas_density)
	else:
		TerrainSurface.place_lava(pos, radius)
