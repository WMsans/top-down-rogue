class_name StatusVisuals
extends Node2D

const ICON_SOURCE_PX := 60.0
const ICON_DISPLAY_PX := 14.0
const ICON_SPACING := 16.0
const ICON_Z := 80

var _status: StatusComponent = null
var _head_offset: Vector2 = Vector2(0, -14)
var _icons: Dictionary = {}
var _particles: CPUParticles2D = null


func setup(status: StatusComponent, head_offset: Vector2) -> void:
	_status = status
	_head_offset = head_offset
	if _status != null and not _status.changed.is_connected(refresh):
		_status.changed.connect(refresh)
	refresh()


func _ready() -> void:
	z_index = ICON_Z
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func refresh() -> void:
	if _status == null:
		return
	var active: Array = _status.get_active_ids()
	for id in _icons.keys():
		if not active.has(id):
			var spr: Sprite2D = _icons[id]
			remove_child(spr)
			spr.queue_free()
			_icons.erase(id)
	for id in active:
		if not _icons.has(id):
			_icons[id] = _make_icon(id)
	var ordered: Array = _icons.keys()
	for i in ordered.size():
		var id: String = ordered[i]
		var spr: Sprite2D = _icons[id]
		var x := (float(i) - (ordered.size() - 1) * 0.5) * ICON_SPACING
		spr.position = _head_offset + Vector2(x, 0.0)
		var a := StatusRegistry.get_icon_alpha(id, _status.get_stain(id))
		spr.modulate = Color(1.0, 1.0, 1.0, a)
	if _particles != null:
		_particles.emitting = _status.has_status("on_fire")


func _make_icon(id: String) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = StatusRegistry.get_icon(id)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var s := ICON_DISPLAY_PX / ICON_SOURCE_PX
	spr.scale = Vector2(s, s)
	add_child(spr)
	return spr


func _build_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.5
	p.position = _head_offset * 0.4
	p.direction = Vector2(0.0, -1.0)
	p.spread = 25.0
	p.gravity = Vector2(0.0, -40.0)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(1.0, 0.55, 0.15, 0.9)
	p.z_as_relative = false
	p.z_index = ICON_Z - 1
	return p
