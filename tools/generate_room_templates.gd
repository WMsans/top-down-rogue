@tool
extends SceneTree

# Entry script. Run via:
#   godot --headless --script tools/generate_room_templates.gd
#
# Writes PNGs to assets/rooms/<biome>/. Creates directories if missing.

const OUT_DIR := "res://assets/rooms"

# Material IDs (must match MaterialTable order; cannot import the autoload
# from a SceneTree script, so values are duplicated here)
const MAT_LAVA := 4
const MAT_DIRT := 5
const MAT_COAL := 6
const MAT_ICE := 7
const MAT_WATER := 8

const _Blob = preload("res://tools/room_generators/blob_room.gd")
const _Arena = preload("res://tools/room_generators/arena.gd")
const _Corridor = preload("res://tools/room_generators/corridor.gd")
const _SecretVault = preload("res://tools/room_generators/secret_vault.gd")
const _ShopChamber = preload("res://tools/room_generators/shop_chamber.gd")

func _init() -> void:
	_ensure_dirs()
	_generate_caves()
	_generate_mines()
	_generate_magma()
	_generate_frozen()
	_generate_vault()
	print("[generate_room_templates] done")
	quit()

func _ensure_dirs() -> void:
	for biome in ["caves", "mines", "magma", "frozen", "vault"]:
		DirAccess.make_dir_recursive_absolute("res://assets/rooms/" + biome)

func _save(img: Image, biome: String, name: String) -> void:
	var path := "%s/%s/%s.png" % [OUT_DIR, biome, name]
	var abs := ProjectSettings.globalize_path(path)
	img.save_png(abs)
	print("  wrote ", path)

# --- per-biome bootstraps ---

func _generate_caves() -> void:
	_save(_Blob.generate(64, MAT_DIRT, 3, 1001), "caves", "blob_a")
	_save(_Blob.generate(64, -1, 4, 1002), "caves", "blob_b")
	_save(_Corridor.generate(96, 32, true, 1003), "caves", "corridor_a")
	_save(_SecretVault.generate(32, 1004), "caves", "secret_a")
	_save(_Arena.generate(128, 0, true, 1005), "caves", "boss_arena")

func _generate_mines() -> void:
	_save(_Corridor.generate(96, 32, false, 2001), "mines", "corridor_a")
	_save(_Corridor.generate(96, 32, true, 2002), "mines", "corridor_b")
	_save(_Arena.generate(64, 5, false, 2003), "mines", "arena_a")
	_save(_SecretVault.generate(32, 2004), "mines", "secret_a")
	_save(_Arena.generate(128, 0, true, 2005), "mines", "boss_arena")

func _generate_magma() -> void:
	_save(_Blob.generate(64, MAT_LAVA, 3, 3001), "magma", "blob_lava_a")
	_save(_Blob.generate(64, MAT_LAVA, 4, 3002), "magma", "blob_lava_b")
	_save(_Arena.generate(64, 4, false, 3003), "magma", "arena_a")
	_save(_Arena.generate(128, 0, true, 3005), "magma", "boss_arena")

func _generate_frozen() -> void:
	_save(_Blob.generate(64, MAT_WATER, 3, 4001), "frozen", "blob_water_a")
	_save(_Blob.generate(64, MAT_WATER, 4, 4002), "frozen", "blob_water_b")
	_save(_Corridor.generate(96, 32, true, 4003), "frozen", "corridor_a")
	_save(_Arena.generate(128, 0, true, 4005), "frozen", "boss_arena")

func _generate_vault() -> void:
	_save(_Arena.generate(64, 5, false, 5001), "vault", "arena_a")
	_save(_Arena.generate(64, 5, false, 5002), "vault", "arena_b")
	_save(_ShopChamber.generate(32, 5003), "vault", "shop_a")
	_save(_Arena.generate(128, 0, true, 5005), "vault", "boss_arena")
