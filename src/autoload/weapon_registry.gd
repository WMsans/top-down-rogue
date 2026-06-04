extends Node

const _Weapon = preload("res://src/weapons/weapon.gd")
const _Modifier = preload("res://src/weapons/modifier.gd")

class WeaponDropEntry:
	var weapon_resource: Weapon
	var weight: float

	func _init(p_resource: Weapon, p_weight: float = 1.0) -> void:
		weapon_resource = p_resource
		weight = p_weight

class ModifierDropEntry:
	var modifier_script: GDScript
	var weight: float

	func _init(p_script: GDScript, p_weight: float = 1.0) -> void:
		modifier_script = p_script
		weight = p_weight

var weapon_scripts: Dictionary = {}
var modifier_scripts: Dictionary = {}
var weapon_tiers: Dictionary = {}
var modifier_tiers: Dictionary = {}

const WEAPON_RESOURCE_DIR := "res://resources/weapons"
const WEAPON_CSV_PATH := "res://docs/design_docs/weapons.csv"
const MODIFIER_CSV_PATH := "res://docs/design_docs/modifiers.csv"

var _all_weapons: Array = []
var _modifier_data: Dictionary = {}  # id -> { name, description, suppresses_base_use }


func _ready() -> void:
	weapon_scripts["melee"] = preload("res://src/weapons/melee_weapon.gd")
	weapon_scripts["test"] = preload("res://src/weapons/test_weapon.gd")
	weapon_scripts["ranged"] = preload("res://src/weapons/ranged_weapon.gd")
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/lava_emitter_modifier.gd")
	_load_modifier_data()

	_load_weapon_resources()
	_build_tier_buckets()
	_populate_modifier_tiers()


func _load_weapon_resources() -> void:
	_all_weapons.clear()
	var dir := DirAccess.open(WEAPON_RESOURCE_DIR)
	if dir == null:
		push_warning("WeaponRegistry: could not open %s" % WEAPON_RESOURCE_DIR)
		return
	for filename in dir.get_files():
		if not (filename.ends_with(".tres") or filename.ends_with(".res")):
			continue
		var path := "%s/%s" % [WEAPON_RESOURCE_DIR, filename]
		var res := load(path)
		if res is Weapon:
			var id := filename.get_basename()
			_all_weapons.append({ "id": id, "resource": res, "weight": 1.0 })
		else:
			push_warning("WeaponRegistry: %s is not a Weapon resource" % path)


func _build_tier_buckets() -> void:
	weapon_tiers.clear()
	for entry in _all_weapons:
		var res: Weapon = entry.resource
		var tier: int = res.rarity
		if not weapon_tiers.has(tier):
			weapon_tiers[tier] = []
		weapon_tiers[tier].append(WeaponDropEntry.new(res, entry.weight))


func _populate_modifier_tiers() -> void:
	modifier_tiers[DropTable.ItemTier.COMMON] = [
		ModifierDropEntry.new(preload("res://src/weapons/lava_emitter_modifier.gd"), 1.0),
	]
	modifier_tiers[DropTable.ItemTier.UNCOMMON] = []
	modifier_tiers[DropTable.ItemTier.RARE] = []


func get_random_weapon(tier: int) -> _Weapon:
	var entries: Array = weapon_tiers.get(tier, [])
	if entries.is_empty():
		entries = weapon_tiers.get(DropTable.ItemTier.COMMON, [])
	if entries.is_empty():
		return null
	var total_weight := 0.0
	for entry in entries:
		total_weight += entry.weight
	var roll := randf() * total_weight
	var cumulative := 0.0
	for entry in entries:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.weapon_resource.duplicate(true)
	return entries[0].weapon_resource.duplicate(true)


func get_random_modifier(tier: int) -> _Modifier:
	var entries: Array = modifier_tiers.get(tier, [])
	if entries.is_empty():
		entries = modifier_tiers.get(DropTable.ItemTier.COMMON, [])
	if entries.is_empty():
		return null
	var total_weight := 0.0
	for entry in entries:
		total_weight += entry.weight
	var roll := randf() * total_weight
	var cumulative := 0.0
	for entry in entries:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.modifier_script.new()
	return entries[0].modifier_script.new()


func _load_modifier_data() -> void:
	_modifier_data.clear()
	for row in CsvTable.parse(MODIFIER_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		_modifier_data[id] = {
			"name": row.get("name", ""),
			"description": row.get("description", ""),
			"suppresses_base_use": row.get("suppresses_base_use", "No").strip_edges() == "Yes",
		}


func _make_modifier(id: String) -> _Modifier:
	var script: GDScript = modifier_scripts.get(id)
	if script == null:
		push_warning("WeaponRegistry: unknown modifier id '%s'" % id)
		return null
	var mod: _Modifier = script.new()
	var data: Dictionary = _modifier_data.get(id, {})
	if data.has("name"):
		mod.name = data["name"]
	if data.has("description"):
		mod.description = data["description"]
	if data.has("suppresses_base_use"):
		mod.suppresses_base_use = data["suppresses_base_use"]
	return mod
