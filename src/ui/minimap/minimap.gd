extends Control

const MinimapModel = preload("res://src/ui/minimap/minimap_model.gd")

@export var view_chunks: float = 7.0

const _REVEAL_STEP_PX := 64.0

var _model: MinimapModel
var _world_manager: Node
var _connected := false
var _stamped_hash: Dictionary = {}   # Vector2i -> int
var _last_reveal_pos: Vector2 = Vector2(INF, INF)

@onready var _surface: ColorRect = $Surface
@onready var _overlay: Control = $Overlay

func _ready() -> void:
	_model = MinimapModel.new()
	var mat := _surface.material as ShaderMaterial
	mat.set_shader_parameter("terrain_tex", _model.terrain_tex)
	mat.set_shader_parameter("reveal_tex", _model.reveal_tex)
	mat.set_shader_parameter("world_origin", Vector2(-_model.world_half_px, -_model.world_half_px))
	var span := float(_model.world_cells * MinimapModel.CELL)
	mat.set_shader_parameter("world_size", Vector2(span, span))
	_overlay.model = _model
	if LevelManager.has_signal("floor_changed"):
		LevelManager.floor_changed.connect(_on_floor_changed)

func _process(_delta: float) -> void:
	if _world_manager == null or not is_instance_valid(_world_manager):
		_world_manager = get_tree().get_first_node_in_group("world_manager")
		if _world_manager == null:
			return
	if not _connected:
		_connect_world()
	_update_terrain()
	_update_uniforms()
	_overlay.queue_redraw()

func _connect_world() -> void:
	_do_reset()
	_connected = true

func _do_reset() -> void:
	var grid = LevelManager.get_grid()
	if grid == null:
		return
	_model.reset(grid,
		Callable(self, "_sector_has_shop").bind(grid),
		Callable(self, "_sector_is_elite").bind(grid))
	_stamped_hash.clear()
	_last_reveal_pos = Vector2(INF, INF)

func _on_floor_changed(_n: int) -> void:
	if _world_manager != null:
		_do_reset()

func _update_terrain() -> void:
	var nav = _world_manager.nav_field
	if nav == null:
		return
	for c in _world_manager.chunks.keys():
		var tile: PackedByteArray = nav.grid.get_tile(c)
		if tile.is_empty():
			continue
		var h := hash(tile)
		if _stamped_hash.get(c, 0) == h:
			continue
		_stamped_hash[c] = h
		_model.stamp_terrain(c, tile)

func _update_uniforms() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var ppos: Vector2 = player.global_position if player else _world_manager.tracking_position
	if ppos.distance_to(_last_reveal_pos) >= _REVEAL_STEP_PX:
		_model.reveal_world_pos(ppos)
		_last_reveal_pos = ppos
	var extent := view_chunks * 0.5 * float(MinimapModel.CHUNK)
	var mat := _surface.material as ShaderMaterial
	mat.set_shader_parameter("player_world", ppos)
	mat.set_shader_parameter("view_extent", Vector2(extent, extent))
	_overlay.player_world = ppos
	_overlay.view_extent = Vector2(extent, extent)
	if player != null and player.velocity.length() > 5.0:
		_overlay.player_facing = player.velocity.normalized()

func _sector_is_elite(s: Vector2i, grid) -> bool:
	var slot = grid.resolve_sector(s)
	return slot.composition != null and slot.composition.arena_kind == &"elite"

func _sector_has_shop(s: Vector2i, grid) -> bool:
	var slot = grid.resolve_sector(s)
	if slot.is_empty or slot.is_boss:
		return false
	var tmpl = grid.get_template_for_slot(slot)
	if tmpl == null:
		return false
	var idx := BiomeRegistry.get_template_index(tmpl)
	if idx < 0:
		return false
	for m in BiomeRegistry.template_pack.collect_markers(slot.template_size, idx):
		if int(m["type"]) == 4:
			return true
	return false
