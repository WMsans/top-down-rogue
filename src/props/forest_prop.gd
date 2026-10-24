class_name ForestProp
extends StaticBody2D

# Runtime for breakable forest props built from ForestPropDef. The whole sprite
# (trunk and canopy) is one StaticBody2D; only the trunk circle collides and the
# trunk circle is what blocks navigation.

const DIG_WEIGHT := 0.5
const DIG_CAP := 6.0
const DUST_COOLDOWN := 0.1

# ponytail: never cleared; keyed by seed so floors don't collide. Clear on floor_changed if it ever matters.
static var _destroyed: Dictionary = {}

var hp: float = 0.0

var _def: ForestPropDef = null
var _prop_id: String = ""
var _sprite: Sprite2D = null
var _dead: bool = false
var _last_dust: float = -INF
# Exact (pos, radius) handed to add_blocker in _enter_tree, reused verbatim in
# _exit_tree: drop_chunk() never reclaims blockers, so any mismatch between the
# add and the remove leaks a permanently solid cell.
var _blocker_pos: Vector2 = Vector2.ZERO
var _blocker_radius: float = 0.0
var _blocker_grid = null


static func make_id(world_seed: int, coord: Vector2i, index: int) -> String:
	return "%d:%d:%d:%d" % [world_seed, coord.x, coord.y, index]


static func is_destroyed(prop_id: String) -> bool:
	return _destroyed.has(prop_id)


func setup(def: ForestPropDef, prop_id: String) -> void:
	_def = def
	_prop_id = prop_id
	hp = def.hp
	collision_layer = 132  # enemy_body | attackable_hit (see projectile ATTACKABLE_HIT_LAYER)
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


func take_dig_hit(impact_pos: Vector2, hit_dir: Vector2, dig_power: float) -> void:
	if _def == null or _dead:
		return
	if impact_pos == Vector2.ZERO:
		impact_pos = global_position
	hp -= 1.0 + minf(maxf(dig_power, 0.0), DIG_CAP) * DIG_WEIGHT
	_sprite.modulate = Color.WHITE
	if is_inside_tree():
		# Node.create_tween() requires the node to be in the tree.
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", _def.tint, 0.15)
	TerrainImpact.play_impact(impact_pos, _def.impact_material(), 1.0, get_parent())
	var now := _now()
	if now - _last_dust >= DUST_COOLDOWN:
		_last_dust = now
		_emit_dust(impact_pos, -hit_dir)
	if hp <= 0.0:
		_die()


func on_hit_impact(impact_pos: Vector2, hit_dir: Vector2) -> void:
	take_dig_hit(impact_pos, hit_dir, 0.0)


func _enter_tree() -> void:
	if _def == null or _blocker_grid != null:
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


# Overridable so tests can drive the dust cooldown with a fake clock.
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _emit_dust(pos: Vector2, dir: Vector2) -> void:
	TerrainSurface.place_dust_splash(pos, 4.0, 120.0, _def.impact_material(), dir)


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
	TerrainSurface.place_dust_splash(global_position, 10.0, 160.0, mat)  # death cloud ignores the cooldown
	_destroyed[_prop_id] = true
	queue_free()
