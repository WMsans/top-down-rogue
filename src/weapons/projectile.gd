class_name Projectile
extends Area2D

@export var damage: float = 0.0
@export var speed: float = 120.0
@export var lifetime: float = 3.0
@export var is_enemy_projectile: bool = false
@export var crit_chance: float = 0.0
@export var crit_multiplier: float = 2.0
@export var crit_status: String = ""
@export var hit_status: String = ""
@export var collisionless_time: float = 0.0

const CRIT_STATUS_STAIN := 2.0
const HIT_STATUS_STAIN := 2.0
const ATTACKABLE_HIT_LAYER := 1 << 7  # layer 8, zero-indexed bit 7

var direction: Vector2 = Vector2.RIGHT
var source_node: Node2D = null
var behaviors: Array = []  # of ProjectileBehavior
var solidity_oracle: Callable = Callable()  # injectable; tests supply a stub

var _age: float = 0.0


func _ready() -> void:
	add_to_group("projectile")
	collision_mask = ATTACKABLE_HIT_LAYER | 1 | 8  # attackable_hit + terrain + projectile area overlap
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	for b in behaviors:
		b.on_spawn(self)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	global_position += direction * speed * delta
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.rotation = direction.angle() + PI * 3.0 / 4.0
	for b in behaviors:
		b.on_process(self, delta)


func _on_body_entered(body: Node) -> void:
	_handle_hit(body)


func _on_area_entered(area: Area2D) -> void:
	_handle_hit(area)


func _handle_hit(target: Node) -> void:
	if _age < collisionless_time:
		return
	if is_enemy_projectile:
		if target.is_in_group("player"):
			if target.has_method("on_hit_impact"):
				target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
		elif target.is_in_group("destructible") and target.has_method("on_hit_impact"):
			target.on_hit_impact(global_position, direction, int(damage))
			queue_free()
		elif target is StaticBody2D:
			var keep := false
			for b in behaviors:
				keep = b.on_terrain_hit(self) or keep
			if keep:
				return
			_carve_terrain()
			queue_free()
		return

	# Player projectile passing an enemy projectile: opt-in clear hook, no self death.
	if target != self and target.is_in_group("projectile") and "is_enemy_projectile" in target and target.is_enemy_projectile:
		for b in behaviors:
			b.on_enemy_projectile_overlap(self, target)
		return

	if target.is_in_group("attackable"):
		if target != source_node and target.has_method("on_hit_impact"):
			var is_crit: bool = randf() < clampf(crit_chance, 0.0, 1.0)
			var dmg: int = int(damage * crit_multiplier) if is_crit else int(damage)
			target.on_hit_impact(global_position, direction, dmg)
			if is_crit and crit_status != "":
				var sc = target.get_node_or_null("StatusComponent")
				if sc != null:
					sc.add_stain(crit_status, CRIT_STATUS_STAIN)
			if hit_status != "":
				var hs = target.get_node_or_null("StatusComponent")
				if hs != null:
					hs.add_stain(hit_status, HIT_STATUS_STAIN)
			var keep_enemy := false
			for b in behaviors:
				keep_enemy = b.on_enemy_hit(self, target) or keep_enemy
			if not keep_enemy:
				queue_free()
	elif target.is_in_group("destructible") and target.has_method("on_hit_impact"):
		target.on_hit_impact(global_position, direction, int(damage))
		queue_free()
	elif target is StaticBody2D:
		var keep_terrain := false
		for b in behaviors:
			keep_terrain = b.on_terrain_hit(self) or keep_terrain
		if keep_terrain:
			return
		_carve_terrain()
		queue_free()


func _carve_terrain() -> void:
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	TerrainSurface.clear_and_push_materials_in_arc(
		global_position, direction, 3.0, TAU, 0.0, 0.0, solids, damage
	)


func is_solid_at(pos: Vector2) -> bool:
	if solidity_oracle.is_valid():
		return solidity_oracle.call(pos)
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm != null and wm.nav_field != null:
		return wm.nav_field.is_solid_world(pos)
	return false
