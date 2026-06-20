class_name MinimapModel
extends RefCounted

const _SectorGrid = preload("res://src/core/sector_grid.gd")

const CELL := 16                          # world px per minimap cell
const CHUNK := 256
const CELLS_PER_CHUNK := CHUNK / CELL     # 16
const PASS_CELLS := CHUNK / 8             # 32 (passability tile width)
const REVEAL_THRESHOLD := 0.5

enum { POI_BOSS, POI_SHOP, POI_ELITE }

var world_half_px: int
var world_cells: int
var terrain_img: Image
var reveal_img: Image
var terrain_tex: ImageTexture
var reveal_tex: ImageTexture
var _pois: Array = []

func _init() -> void:
	world_half_px = _SectorGrid.WALL_INNER_SECTORS * _SectorGrid.SECTOR_SIZE_PX + CHUNK
	world_cells = int(ceil(float(world_half_px * 2) / float(CELL)))
	terrain_img = Image.create(world_cells, world_cells, false, Image.FORMAT_R8)
	reveal_img = Image.create(world_cells, world_cells, false, Image.FORMAT_R8)
	terrain_img.fill(Color(0, 0, 0, 1))
	reveal_img.fill(Color(0, 0, 0, 1))
	terrain_tex = ImageTexture.create_from_image(terrain_img)
	reveal_tex = ImageTexture.create_from_image(reveal_img)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori((world_pos.x + float(world_half_px)) / float(CELL)),
		floori((world_pos.y + float(world_half_px)) / float(CELL)))

func world_to_uv(world_pos: Vector2) -> Vector2:
	var span := float(world_cells * CELL)
	return Vector2((world_pos.x + float(world_half_px)) / span,
		(world_pos.y + float(world_half_px)) / span)

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < world_cells and cell.y < world_cells

func get_pois() -> Array:
	return _pois

const REVEAL_R_INNER := 0.9   # in chunks: plateau radius
const REVEAL_R_OUTER := 1.25  # in chunks: falloff edge (>1 so neighbors overlap)


func reveal_chunk(coord: Vector2i) -> void:
	var center_world := Vector2(coord) * CHUNK + Vector2(CHUNK / 2.0, CHUNK / 2.0)
	var center_cell := world_to_cell(center_world)
	var r_inner := REVEAL_R_INNER * float(CELLS_PER_CHUNK)
	var r_outer := REVEAL_R_OUTER * float(CELLS_PER_CHUNK)
	var r := int(ceil(r_outer))
	var changed := false
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := center_cell + Vector2i(dx, dy)
			if not _in_bounds(c):
				continue
			var d := sqrt(float(dx * dx + dy * dy))
			var v: float
			if d <= r_inner:
				v = 1.0
			elif d >= r_outer:
				continue
			else:
				v = 1.0 - (d - r_inner) / (r_outer - r_inner)
			if v > reveal_img.get_pixel(c.x, c.y).r:
				reveal_img.set_pixel(c.x, c.y, Color(v, v, v, 1.0))
				changed = true
	if changed:
		reveal_tex.update(reveal_img)


func is_revealed_world(world_pos: Vector2) -> bool:
	var c := world_to_cell(world_pos)
	if not _in_bounds(c):
		return false
	return reveal_img.get_pixel(c.x, c.y).r >= REVEAL_THRESHOLD
