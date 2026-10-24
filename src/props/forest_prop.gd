class_name ForestProp
extends StaticBody2D

# Runtime for breakable forest props built from ForestPropDef. The whole sprite
# (trunk and canopy) is one StaticBody2D. Rocks block bodies and navigation with
# the trunk circle; trees only keep it on attackable_hit so they can be hit.

# Sprite alpha while an actor stands behind a tree's canopy.
const FADE_ALPHA := 0.4
const FADE_TIME := 0.15
# Death pop: sprite squashes around the trunk base, then shrinks away.
const SQUASH := Vector2(1.25, 0.75)
const POP_TIME := 0.15
const LEAF_COLOR := Color("4b692f")  # DB32 dark green
const CHIP_COLOR := Color("847e87")  # DB32 grey

# ponytail: never cleared; keyed by seed so floors don't collide. Clear on floor_changed if it ever matters.
static var _destroyed: Dictionary = {}

var _def: ForestPropDef = null
var _prop_id: String = ""
var _sprite: Sprite2D = null
var _dead: bool = false
# Exact (pos, radius) handed to add_blocker in _enter_tree, reused verbatim in
# _exit_tree: drop_chunk() never reclaims blockers, so any mismatch between the
# add and the remove leaks a permanently solid cell.
var _blocker_pos: Vector2 = Vector2.ZERO
var _blocker_radius: float = 0.0
var _blocker_grid = null
var _occluders: int = 0


static func make_id(world_seed: int, coord: Vector2i, index: int) -> String:
	return "%d:%d:%d:%d" % [world_seed, coord.x, coord.y, index]


static func is_destroyed(prop_id: String) -> bool:
	return _destroyed.has(prop_id)


func setup(def: ForestPropDef, prop_id: String) -> void:
	_def = def
	_prop_id = prop_id
	# prop_body | attackable_hit (see projectile ATTACKABLE_HIT_LAYER); trees skip prop_body so nothing bumps into them.
	collision_layer = 128 if def.kind == "tree" else 144
	collision_mask = 0
	add_to_group("destructible")
	z_as_relative = false
	# ponytail: fixed z above walls/actors instead of y-sort; actors within ~6px south of a trunk draw under roots. Split trunk/canopy sprites if that shows.
	z_index = 2
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.centered = true
	_sprite.texture = def.texture
	if def.texture != null:
		# Bottom of the opaque art (after the transparent base rows) sits at y = 0.
		_sprite.offset.y = -float(def.texture.get_height()) / 2.0 + float(def.base_inset())
	_sprite.modulate = def.tint
	add_child(_sprite)
	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = def.trunk_radius
	shape_node.shape = circle
	add_child(shape_node)
	if def.kind == "tree" and def.texture != null:
		_add_canopy_area(def)


# Area over the canopy (sprite above the trunk) that catches player and enemy
# hurtboxes on attackable_hit; fading uses self_modulate so the hit flash on
# modulate never clobbers it.
func _add_canopy_area(def: ForestPropDef) -> void:
	var area := Area2D.new()
	area.name = "CanopyArea"
	area.collision_layer = 0
	area.collision_mask = 128  # attackable_hit: player and enemies
	area.monitorable = false
	var top := -float(def.texture.get_height() - def.base_inset())
	var bottom := -def.trunk_radius
	var rect := RectangleShape2D.new()
	rect.size = Vector2(def.texture.get_width() * 0.6, bottom - top)
	var shape_node := CollisionShape2D.new()
	shape_node.shape = rect
	shape_node.position = Vector2(0, (top + bottom) / 2.0)
	area.add_child(shape_node)
	area.body_entered.connect(_on_canopy_body_entered)
	area.body_exited.connect(_on_canopy_body_exited)
	add_child(area)


func is_faded() -> bool:
	return _occluders > 0


func _on_canopy_body_entered(body: Node2D) -> void:
	if body is ForestProp:
		return
	_occluders += 1
	if _occluders == 1:
		_fade_to(FADE_ALPHA)


func _on_canopy_body_exited(body: Node2D) -> void:
	if body is ForestProp or _occluders == 0:
		return
	_occluders -= 1
	if _occluders == 0:
		_fade_to(1.0)


func _fade_to(alpha: float) -> void:
	if is_inside_tree():
		create_tween().tween_property(_sprite, "self_modulate:a", alpha, FADE_TIME)
	else:
		_sprite.self_modulate.a = alpha


# Any hit destroys the prop.
func take_dig_hit(impact_pos: Vector2, hit_dir: Vector2, _dig_power: float) -> void:
	if _def == null or _dead:
		return
	if impact_pos == Vector2.ZERO:
		impact_pos = global_position
	_burst(impact_pos, -hit_dir, 8)
	TerrainImpact.play_impact(impact_pos, _def.impact_material(), 1.0, get_parent())
	TerrainSurface.place_dust_splash(impact_pos, 4.0, 120.0, _def.impact_material(), -hit_dir)
	_die()


func on_hit_impact(impact_pos: Vector2, hit_dir: Vector2) -> void:
	take_dig_hit(impact_pos, hit_dir, 0.0)


# One-shot leaf/chip burst parented beside the prop so it outlives _die().
func _burst(pos: Vector2, dir: Vector2, amount: int) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.6
	p.direction = dir if dir != Vector2.ZERO else Vector2.UP
	p.spread = 60.0
	p.gravity = Vector2(0.0, 120.0)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = LEAF_COLOR if _def.kind == "tree" else CHIP_COLOR
	p.z_as_relative = false
	p.z_index = z_index + 1
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true


func _enter_tree() -> void:
	if _def == null or _def.kind == "tree" or _blocker_grid != null:
		return
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm == null or wm.nav_field == null or wm.nav_field.grid == null:
		return
	_blocker_pos = global_position
	_blocker_radius = _def.trunk_radius
	_blocker_grid = wm.nav_field.grid
	_blocker_grid.add_blocker(_blocker_pos, _blocker_radius)


func _exit_tree() -> void:
	if _blocker_grid == null:
		return
	_blocker_grid.remove_blocker(_blocker_pos, _blocker_radius)
	_blocker_grid = null


func _die() -> void:
	_dead = true
	var mat := _def.impact_material()
	TerrainImpact.play_impact(global_position, mat, 2.0, get_parent())
	var tex := _def.texture
	if tex != null and _sprite != null:
		# Two more sparks in the canopy half of the sprite (sprite spans
		# offset.y +/- height/2; the upper half is offset.y - height/2 .. offset.y).
		var half_w := float(tex.get_width()) / 2.0
		var half_h := float(tex.get_height()) / 2.0
		for _i in range(2):
			var local := Vector2(
				randf_range(-half_w, half_w),
				_sprite.offset.y + randf_range(-half_h, 0.0)
			)
			TerrainImpact.play_impact(to_global(local), mat, 2.0, get_parent())
	_burst(global_position + Vector2(0, _sprite.offset.y if _sprite != null else 0.0), Vector2.UP, 24)
	TerrainSurface.place_dust_splash(global_position, 10.0, 160.0, mat)  # death cloud
	_destroyed[_prop_id] = true
	_pop()


# White flash + squash, then shrink to nothing and free. Collision drops at once
# so the dying prop no longer catches hits.
func _pop() -> void:
	collision_layer = 0
	if not is_inside_tree() or _sprite == null:
		# Node.create_tween() requires the node to be in the tree.
		queue_free()
		return
	_sprite.modulate = Color.WHITE
	_sprite.scale = SQUASH
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(0.0, 1.4), POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
