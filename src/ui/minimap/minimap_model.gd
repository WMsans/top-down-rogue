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
