extends Node

const _Weapon = preload("res://src/weapons/weapon.gd")
const _Modifier = preload("res://src/weapons/modifier.gd")

class WeaponDropEntry:
	var script: GDScript
	var weight: float

	func _init(p_script: GDScript, p_weight: float = 1.0) -> void:
		script = p_script
		weight = p_weight

class ModifierDropEntry:
	var script: GDScript
	var weight: float

	func _init(p_script: GDScript, p_weight: float = 1.0) -> void:
		script = p_script
		weight = p_weight

var weapon_scripts: Dictionary = {}
var modifier_scripts: Dictionary = {}
var weapon_tiers: Dictionary = {}
var modifier_tiers: Dictionary = {}

func _ready() -> void:
	weapon_scripts["melee"] = preload("res://src/weapons/melee_weapon.gd")
	weapon_scripts["test"] = preload("res://src/weapons/test_weapon.gd")
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/lava_emitter_modifier.gd")

	_populate_tiers()


func _populate_tiers() -> void:
	weapon_tiers[DropTable.ItemTier.COMMON] = [
		WeaponDropEntry.new(preload("res://src/weapons/melee_weapon.gd"), 1.0),
		WeaponDropEntry.new(preload("res://src/weapons/test_weapon.gd"), 0.5),
	]
	weapon_tiers[DropTable.ItemTier.UNCOMMON] = []
	weapon_tiers[DropTable.ItemTier.RARE] = []

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
			return entry.script.new()
	return entries[0].script.new()


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
			return entry.script.new()
	return entries[0].script.new()