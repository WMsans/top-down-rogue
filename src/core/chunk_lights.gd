class_name ChunkLights
extends Node2D

const CHUNK_SIZE := 256.0
const CELLS_X := 4
const CELLS_Y := 4
const MAX_LIGHTS := 16
const DEFAULT_LIGHT_RANGE := 64.0
const MAX_GLOW := 20.0
const SMOOTH_SPEED := 30.0
const MIN_PIXELS := 4
const TEXTURE_RADIUS := 32.0  # Half of the 64px baked falloff texture

static var _cached_radius_texture: Texture2D

var target_positions: Array[Vector2]
var target_energies: Array[float]
var current_positions: Array[Vector2]
var current_energies: Array[float]
var lights: Array[PointLight2D]
var fog_positions: PackedVector2Array
var fog_energies: PackedFloat32Array
var chunk_coord: Vector2i

func _init(coord: Vector2i) -> void:
	chunk_coord = coord
	name = "Lights"
	z_index = 2

	var light_texture := _create_unit_radius_texture()

	target_positions.resize(MAX_LIGHTS)
	target_energies.resize(MAX_LIGHTS)
	current_positions.resize(MAX_LIGHTS)
	current_energies.resize(MAX_LIGHTS)
	lights.resize(MAX_LIGHTS)

	for i in range(MAX_LIGHTS):
		target_positions[i] = Vector2.ZERO
		target_energies[i] = 0.0
		current_positions[i] = Vector2.ZERO
		current_energies[i] = 0.0

		var light := PointLight2D.new()
		light.visible = false
		light.shadow_enabled = false
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.texture = light_texture
		light.texture_scale = DEFAULT_LIGHT_RANGE / TEXTURE_RADIUS
		light.color = Color(1.0, 0.5, 0.15, 1.0)  # warm lava-orange default
		add_child(light)
		lights[i] = light

	fog_positions.resize(MAX_LIGHTS)
	fog_energies.resize(MAX_LIGHTS)
	for i in range(MAX_LIGHTS):
		fog_positions[i] = Vector2.ZERO
		fog_energies[i] = 0.0


func _create_unit_radius_texture() -> Texture2D:
	if _cached_radius_texture:
		return _cached_radius_texture

	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var radius := float(size) * 0.5 - 1.0
	for y in range(size):
		for x in range(size):
			var dist := Vector2(float(x), float(y)).distance_to(center) / radius
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_cached_radius_texture = ImageTexture.create_from_image(img)
	return _cached_radius_texture


func apply_light_data(cell_data: Array) -> void:
	if cell_data.size() < MAX_LIGHTS:
		return
	for i in range(MAX_LIGHTS):
		var entry := cell_data[i] as Dictionary
		target_positions[i] = entry.get("position", Vector2.ZERO)
		target_energies[i] = entry.get("energy", 0.0)
		lights[i].color = entry.get("color", Color(1.0, 0.5, 0.15, 1.0))


func update_fog_data(camera: Camera2D, viewport_size: Vector2) -> void:
	var screen_center := viewport_size / 2.0
	if camera:
		var zoom := camera.zoom
		for i in range(MAX_LIGHTS):
			if current_energies[i] < 0.005:
				fog_energies[i] = 0.0
				continue
			var world_pos := global_position + current_positions[i]
			var offset := world_pos - camera.global_position
			fog_positions[i] = offset * zoom + screen_center
			fog_energies[i] = current_energies[i]
	else:
		for i in range(MAX_LIGHTS):
			fog_positions[i] = Vector2.ZERO
			fog_energies[i] = 0.0


func _process(delta: float) -> void:
	var t := 1.0 - exp(-SMOOTH_SPEED * delta)
	for i in range(MAX_LIGHTS):
		current_positions[i] = current_positions[i].lerp(target_positions[i], t)
		current_energies[i] = lerpf(current_energies[i], target_energies[i], t)

		if current_energies[i] < 0.005:
			lights[i].visible = false
		else:
			lights[i].visible = true
			lights[i].position = current_positions[i]
			lights[i].energy = current_energies[i]

	var tree := get_tree()
	if tree:
		var player := tree.get_first_node_in_group("player")
		if player:
			var cam := player.get_node("Camera2D") as Camera2D
			var vp_size := Vector2(320, 180)
			update_fog_data(cam, vp_size)

