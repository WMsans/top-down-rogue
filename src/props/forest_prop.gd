class_name ForestProp
extends StaticBody2D

# Runtime for breakable forest props built from ForestPropDef. The whole sprite
# (trunk and canopy) is one StaticBody2D. Rocks block bodies and navigation with
# the trunk circle; trees only keep it on attackable_hit so they can be hit.
# The sprite is split: the canopy draws over walls at z 2, while the bottom
# TRUNK_BAND rows move into the world's y-sorted entity layer so actors and
# flora south of the base draw in front of the trunk.

# Sprite alpha while an actor stands behind a tree's canopy.
const FADE_ALPHA := 0.4
const FADE_TIME := 0.15
# Death pop: sprite squashes around the trunk base, then shrinks away.
const SQUASH := Vector2(1.25, 0.75)
const POP_TIME := 0.15
const LEAF_COLOR := Color("4b692f")  # DB32 dark green
const CHIP_COLOR := Color("847e87")  # DB32 grey
# Sprite rows above the base that y-sort with actors (about the player's height).
const TRUNK_BAND := 32
# Ground contact shadow peak darkness; matches the wall crease's ao_strength.
const SHADOW_STRENGTH := 0.6
const _SHADOW_TEX_SIZE := 32

static var _shadow_tex: GradientTexture2D = null

# ponytail: never cleared; keyed by seed so floors don't collide. Clear on floor_changed if it ever matters.
static var _destroyed: Dictionary = {}

var _def: ForestPropDef = null
var _prop_id: String = ""
var _sprite: Sprite2D = null  # canopy; the band itself when the prop is shorter than TRUNK_BAND
var _band: Sprite2D = null
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


# The world's y-sorted entity layer, or null without a world manager (tests, editor).
static func find_entity_layer(tree: SceneTree) -> Node2D:
	if tree == null:
		return null
	var wm := tree.get_first_node_in_group("world_manager")
	return wm.get("entity_layer") as Node2D if wm != null else null


# Drawn size of the contact-shadow oval centred on the trunk base.
static func shadow_size(def: ForestPropDef) -> Vector2:
	var w := def.trunk_radius * 4.0
	return Vector2(w, w * 0.5)


# Shadow darkness at `offset` from the base: linear from SHADOW_STRENGTH at the
# centre to 0 at the oval's edge (same falloff as the gradient texture).
static func shadow_darkness(def: ForestPropDef, offset: Vector2) -> float:
	var r := shadow_size(def) / 2.0
	return SHADOW_STRENGTH * (1.0 - clampf((offset / r).length(), 0.0, 1.0))


# True when a bottom-anchored sprite `flora_height` tall at `offset` from the
# base stands south of the trunk and overlaps the band, so it must draw over it.
static func is_in_front(def: ForestPropDef, offset: Vector2, flora_height: float) -> bool:
	return offset.y > 0.0 and offset.y - flora_height < 0.0 \
		and absf(offset.x) < def.texture.get_width() / 2.0


func setup(def: ForestPropDef, prop_id: String) -> void:
	_def = def
	_prop_id = prop_id
	# prop_body | attackable_hit (see projectile ATTACKABLE_HIT_LAYER); trees skip prop_body so nothing bumps into them.
	collision_layer = 128 if def.kind == "tree" else 144
	collision_mask = 0
	add_to_group("destructible")
	z_as_relative = false
	z_index = 2
	if def.texture != null:
		# Bottom of the opaque art (after the transparent base rows) sits at y = 0.
		var w := def.texture.get_width()
		var opaque_h := def.texture.get_height() - def.base_inset()
		var band_h := mini(TRUNK_BAND, opaque_h)
		_band = _make_part("TrunkBand", Rect2(0, opaque_h - band_h, w, band_h))
		_band.z_as_relative = false
		_band.z_index = 0
		add_child(_band)
		_sprite = _band
		if opaque_h > band_h:
			_sprite = _make_part("Sprite2D", Rect2(0, 0, w, opaque_h - band_h))
			_sprite.offset.y -= band_h
			add_child(_sprite)
	add_child(_make_shadow(def))
	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = def.trunk_radius
	shape_node.shape = circle
	add_child(shape_node)
	if def.kind == "tree" and def.texture != null:
		_add_canopy_area(def)


# A bottom-anchored slice of the texture: origin at the slice's bottom centre.
func _make_part(part_name: String, region: Rect2) -> Sprite2D:
	var part := Sprite2D.new()
	part.name = part_name
	part.texture = _def.texture
	part.centered = false
	part.region_enabled = true
	part.region_rect = region
	part.offset = Vector2(-region.size.x / 2.0, -region.size.y)
	part.modulate = _def.tint
	return part


# Soft oval at the trunk base above floor and flora (z -10), below actors.
func _make_shadow(def: ForestPropDef) -> Sprite2D:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, SHADOW_STRENGTH))
		g.set_color(1, Color(0, 0, 0, 0))
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = g
		_shadow_tex.width = _SHADOW_TEX_SIZE
		_shadow_tex.height = _SHADOW_TEX_SIZE
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5)
		_shadow_tex.fill_to = Vector2(1.0, 0.5)
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = _shadow_tex
	shadow.scale = shadow_size(def) / float(_SHADOW_TEX_SIZE)
	shadow.z_as_relative = false
	shadow.z_index = -9
	return shadow


# Canopy and band, without the duplicate when the band is the whole sprite.
func _parts() -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for part in [_sprite, _band]:
		if part != null and is_instance_valid(part) and not out.has(part):
			out.append(part)
	return out


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
	for part in _parts():
		if is_inside_tree():
			create_tween().tween_property(part, "self_modulate:a", alpha, FADE_TIME)
		else:
			part.self_modulate.a = alpha


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
	if _band != null and _band.get_parent() == self:
		var layer := find_entity_layer(get_tree())
		if layer != null:
			remove_child(_band)
			layer.add_child(_band)
			_band.global_position = global_position
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
	# The band lives in the entity layer, so it must be freed by hand.
	if _band != null and is_instance_valid(_band) and _band.get_parent() != self:
		_band.queue_free()
	if _blocker_grid == null:
		return
	_blocker_grid.remove_blocker(_blocker_pos, _blocker_radius)
	_blocker_grid = null


func _die() -> void:
	_dead = true
	var mat := _def.impact_material()
	TerrainImpact.play_impact(global_position, mat, 2.0, get_parent())
	var tex := _def.texture
	var opaque_h := 0.0
	if tex != null:
		# Two more sparks in the upper half of the art (it spans y = -opaque_h .. 0).
		opaque_h = float(tex.get_height() - _def.base_inset())
		var half_w := float(tex.get_width()) / 2.0
		for _i in range(2):
			var local := Vector2(randf_range(-half_w, half_w), -randf_range(opaque_h / 2.0, opaque_h))
			TerrainImpact.play_impact(to_global(local), mat, 2.0, get_parent())
	_burst(global_position + Vector2(0, -opaque_h / 2.0), Vector2.UP, 24)
	TerrainSurface.place_dust_splash(global_position, 10.0, 160.0, mat)  # death cloud
	_destroyed[_prop_id] = true
	_pop()


# White flash + squash, then shrink to nothing and free. Collision drops at once
# so the dying prop no longer catches hits.
func _pop() -> void:
	collision_layer = 0
	var parts := _parts()
	if not is_inside_tree() or parts.is_empty():
		# Node.create_tween() requires the node to be in the tree.
		queue_free()
		return
	var tween := create_tween().set_parallel()
	for part in parts:
		part.modulate = Color.WHITE
		part.scale = SQUASH
		tween.tween_property(part, "scale", Vector2(0.0, 1.4), POP_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
