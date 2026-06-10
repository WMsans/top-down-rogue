class_name BounceBehavior
extends ProjectileBehavior

var max_bounces: int = 3
var probe_step: float = 6.0


func on_terrain_hit(proj) -> bool:
	if max_bounces <= 0:
		return false  # default carve + die
	var d: Vector2 = proj.direction
	var p: Vector2 = proj.global_position
	var sx: float = signf(d.x) if absf(d.x) > 0.0001 else 0.0
	var sy: float = signf(d.y) if absf(d.y) > 0.0001 else 0.0
	var hit_x: bool = sx != 0.0 and proj.is_solid_at(p + Vector2(sx * probe_step, 0.0))
	var hit_y: bool = sy != 0.0 and proj.is_solid_at(p + Vector2(0.0, sy * probe_step))
	if not hit_x and not hit_y:
		# Ambiguous (corner / coarse grid): reverse fully.
		d = -d
	else:
		if hit_x:
			d.x = -d.x
		if hit_y:
			d.y = -d.y
	proj.direction = d.normalized()
	proj.global_position = p + proj.direction * probe_step  # clear the wall
	max_bounces -= 1
	return true
