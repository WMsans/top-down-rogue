extends Node

# Data-only registry: status definitions, reaction rules, and material->status
# mapping. Shared by every StatusComponent. Adding a status = one entry here.

const StatusDefScript = preload("res://src/status/status_def.gd")

# Terrain top-up: stain added per second while standing in a source material.
const TERRAIN_STAIN_RATE := 6.0

var _defs: Dictionary = {}  # id -> StatusDef


func _ready() -> void:
	_register_defs()


func _register_defs() -> void:
	_add(StatusDefScript.new(
		"on_fire", "On Fire", Color(1.0, 0.45, 0.1, 1.0),
		1.0, 1.0, StatusDef.Category.HARMFUL, 4.0))
	_add(StatusDefScript.new(
		"wet", "Wet", Color(0.35, 0.55, 0.95, 1.0),
		0.5, 1.0, StatusDef.Category.NEUTRAL))
	_add(StatusDefScript.new(
		"oiled", "Oiled", Color(0.25, 0.18, 0.1, 1.0),
		0.3, 1.0, StatusDef.Category.NEUTRAL))
	_add(StatusDefScript.new(
		"chilly", "Chilly", Color(0.6, 0.8, 0.95, 1.0),
		0.8, 1.0, StatusDef.Category.HARMFUL, 0.0, false, 0.6))
	_add(StatusDefScript.new(
		"frozen", "Frozen", Color(0.7, 0.9, 1.0, 1.0),
		0.4, 3.0, StatusDef.Category.HARMFUL, 0.0, true, 0.0))
	_add(StatusDefScript.new(
		"bloody", "Bloody", Color(0.75, 0.08, 0.08, 1.0),
		0.4, 1.0, StatusDef.Category.NEUTRAL))


func _add(def: StatusDef) -> void:
	_defs[def.id] = def


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> StatusDef:
	return _defs.get(id, null)


func get_threshold(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.active_threshold if d != null else 1.0


func get_decay_rate(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.decay_rate if d != null else 1.0


func get_tint(id: String) -> Color:
	var d: StatusDef = _defs.get(id, null)
	return d.tint_color if d != null else Color(1, 1, 1, 1)


func get_burn_dps(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.burn_dps if d != null else 0.0


func blocks_movement(id: String) -> bool:
	var d: StatusDef = _defs.get(id, null)
	return d.blocks_movement if d != null else false


func get_slow_multiplier(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.slow_multiplier if d != null else 1.0


func stain_for_material(material_id: int) -> String:
	if material_id == MaterialRegistry.MAT_LAVA or material_id == MaterialRegistry.MAT_EXPLODE_WAVE:
		return "on_fire"
	if material_id == MaterialRegistry.MAT_WATER:
		return "wet"
	if material_id == MaterialRegistry.MAT_OIL:
		return "oiled"
	if material_id == MaterialRegistry.MAT_BLOOD:
		return "bloody"
	return ""
