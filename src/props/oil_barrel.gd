extends Area2D

const MAX_HP := 3
const SPLASH_RADIUS := 4.0
const DUMP_RADIUS := 8.0

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
	TerrainSurface.place_oil(splash_pos, SPLASH_RADIUS)
	if _hp <= 0:
		_dead = true
		TerrainSurface.place_oil(global_position, DUMP_RADIUS)
		queue_free()


func _flash() -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D")
	if sprite == null:
		return
	sprite.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(0.6, 0.35, 0.15, 1.0), 0.15)