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
const DEFAULT_TEXTURE_SIZE := 512.0  # PointLight2D default texture radius

var target_positions: Array[Vector2]
var target_energies: Array[float]
var current_positions: Array[Vector2]
var current_energies: Array[float]
var lights: Array[PointLight2D]
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
		light.texture_scale = DEFAULT_LIGHT_RANGE / DEFAULT_TEXTURE_SIZE
		light.color = Color(1.0, 0.5, 0.15, 1.0)  # warm lava-orange default
		add_child(light)
		lights[i] = light


func _create_unit_radius_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var radius := float(size) * 0.5 - 1.0
	for y in range(size):
		for x in range(size):
			var dist := Vector2(float(x), float(y)).distance_to(center) / radius
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func apply_light_data(cell_data: Array) -> void:
	for i in range(MAX_LIGHTS):
		var entry := cell_data[i] as Dictionary
		target_positions[i] = entry.get("position", Vector2.ZERO)
		target_energies[i] = entry.get("energy", 0.0)
		lights[i].color = entry.get("color", Color(1.0, 0.5, 0.15, 1.0))


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
