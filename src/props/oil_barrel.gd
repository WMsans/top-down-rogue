extends Area2D

const MAX_HP := 3
const SPLASH_RADIUS := 10.0
const DUMP_RADIUS := 20.0
const SPLASH_SPEED := 200.0
const DUMP_SPEED := 280.0
const SPLASH_SATTELITES := 3
const DUMP_SATTELITES := 5

var _hp: int = MAX_HP
var _dead: bool = false


func _ready() -> void:
	add_to_group("destructible")


func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if _dead:
		return
	_hp -= 1
	_flash()
	var splash_pos := impact_point if impact_point != Vector2.ZERO else global_position
	var dir := hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector2.ZERO
	TerrainSurface.place_oil_splash(splash_pos, SPLASH_RADIUS, SPLASH_SPEED, dir)
	for i in range(SPLASH_SATTELITES):
		var spread_angle := randf_range(-0.7, 0.7)
		var s_dir := dir.rotated(spread_angle) if dir != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
		var dist := randf_range(4.0, 14.0)
		var offset := s_dir * dist
		var radius := SPLASH_RADIUS * randf_range(0.4, 0.9)
		var speed := SPLASH_SPEED * randf_range(0.7, 1.4)
		TerrainSurface.place_oil_splash(splash_pos + offset, radius, speed, s_dir)
	if _hp <= 0:
		_dead = true
		TerrainSurface.place_oil_splash(global_position, DUMP_RADIUS, DUMP_SPEED)
		for i in range(DUMP_SATTELITES):
			var s_dir := Vector2.from_angle(randf() * TAU)
			var dist := randf_range(4.0, 14.0)
			var offset := s_dir * dist
			var radius := DUMP_RADIUS * randf_range(0.4, 0.9)
			var speed := DUMP_SPEED * randf_range(0.7, 1.4)
			TerrainSurface.place_oil_splash(global_position + offset, radius, speed, s_dir)
		queue_free()


func _flash() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(0.6, 0.35, 0.15, 1.0), 0.15)