class_name FogManager
extends Node2D

const VP_WIDTH := 320
const VP_HEIGHT := 180
const LIGHT_STAMP_SIZE := 64

var fog_sprite: Sprite2D
var fog_material: ShaderMaterial

var fog_image: Image
var fog_texture: ImageTexture
var light_stamp: Image

var camera: Camera2D


func _ready() -> void:
	z_index = 101

	fog_image = Image.create(VP_WIDTH, VP_HEIGHT, false, Image.FORMAT_RGBA8)
	fog_texture = ImageTexture.create_from_image(fog_image)

	light_stamp = _create_light_stamp()

	if fog_sprite:
		fog_sprite.texture = fog_texture
	if fog_material:
		fog_material.set_shader_parameter("fog_map", fog_texture)

	# Wait one frame for scene tree to be fully set up, then find camera
	call_deferred("_connect_camera")


func _connect_camera() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var cam: Camera2D = player.get_node_or_null("Camera2D")
		if cam:
			camera = cam


func _create_light_stamp() -> Image:
	var img := Image.create(LIGHT_STAMP_SIZE, LIGHT_STAMP_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(LIGHT_STAMP_SIZE - 1) * 0.5, float(LIGHT_STAMP_SIZE - 1) * 0.5)
	var radius := float(LIGHT_STAMP_SIZE) * 0.5 - 1.0

	for y in range(LIGHT_STAMP_SIZE):
		for x in range(LIGHT_STAMP_SIZE):
			var dist := Vector2(float(x), float(y)).distance_to(center) / radius
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a))

	return img


func _process(_delta: float) -> void:
	if not fog_image or not fog_texture:
		return

	# Reset to full fog
	fog_image.fill(Color.WHITE)

	# Stamp player light
	_stamp_player_light()

	# Stamp terrain glow lights
	_stamp_terrain_lights()

	# Update texture
	fog_texture.update(fog_image)


func _stamp_player_light() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player or not camera:
		return

	var light_node: PointLight2D = player.get_node_or_null("PointLight2D")
	if not light_node or not light_node.visible:
		return

	var world_pos := light_node.global_position
	var screen_pos := _world_to_screen(world_pos, light_node.energy)

	var stamp_size := int(LIGHT_STAMP_SIZE * light_node.energy)
	if stamp_size < 4:
		return

	var scaled_stamp := light_stamp
	if stamp_size != LIGHT_STAMP_SIZE:
		scaled_stamp = light_stamp.duplicate()
		scaled_stamp.resize(stamp_size, stamp_size, Image.INTERPOLATE_LANCZOS)

	var top_left := screen_pos - Vector2(float(stamp_size) / 2.0, float(stamp_size) / 2.0)
	fog_image.blend_rect(scaled_stamp, Rect2i(Vector2i.ZERO, Vector2i(stamp_size, stamp_size)), top_left)


func _stamp_terrain_lights() -> void:
	var world_manager := get_tree().get_first_node_in_group("world_manager")
	if not world_manager:
		return

	var chunk_manager: ChunkManager = world_manager.chunk_manager
	if not chunk_manager:
		return

	var light_data: Dictionary = chunk_manager.get_visible_light_data()
	var positions: PackedVector2Array = light_data.get("positions", PackedVector2Array())
	var energies: PackedFloat32Array = light_data.get("energies", PackedFloat32Array())

	var count := mini(positions.size(), energies.size())
	for i in range(count):
		var energy := energies[i]
		if energy < 0.01:
			continue

		var screen_pos := positions[i]
		var stamp_size := int(LIGHT_STAMP_SIZE * minf(energy * 2.0, 1.5))
		if stamp_size < 4:
			continue

		var top_left := screen_pos - Vector2(float(stamp_size) / 2.0, float(stamp_size) / 2.0)

		var scaled_stamp := light_stamp
		if stamp_size != LIGHT_STAMP_SIZE:
			scaled_stamp = light_stamp.duplicate()
			scaled_stamp.resize(stamp_size, stamp_size, Image.INTERPOLATE_LANCZOS)

		fog_image.blend_rect(scaled_stamp, Rect2i(Vector2i.ZERO, Vector2i(stamp_size, stamp_size)), top_left)


func _world_to_screen(world_pos: Vector2, energy: float) -> Vector2:
	if not camera:
		return Vector2.ZERO
	var offset := world_pos - camera.global_position
	var screen_center := Vector2(VP_WIDTH / 2.0, VP_HEIGHT / 2.0)
	var zoom := camera.zoom
	return offset * zoom + screen_center


func set_fog_color(color: Color) -> void:
	if fog_material:
		fog_material.set_shader_parameter("fog_color", color)
