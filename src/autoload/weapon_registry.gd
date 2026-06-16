extends Node

const _Weapon = preload("res://src/weapons/weapon.gd")
const _Modifier = preload("res://src/weapons/modifier.gd")
const _DataModifier = preload("res://src/weapons/modifiers/data_modifier.gd")

class WeaponDropEntry:
	var weapon_resource: Weapon
	var weight: float

	func _init(p_resource: Weapon, p_weight: float = 1.0) -> void:
		weapon_resource = p_resource
		weight = p_weight

class ModifierDropEntry:
	var modifier_script: GDScript
	var modifier_id: String
	var weight: float

	func _init(p_script: GDScript, p_id: String, p_weight: float = 1.0) -> void:
		modifier_script = p_script
		modifier_id = p_id
		weight = p_weight

var weapon_scripts: Dictionary = {}
var modifier_scripts: Dictionary = {}
var weapon_tiers: Dictionary = {}
var modifier_tiers: Dictionary = {}

const WEAPON_RESOURCE_DIR := "res://resources/weapons"
const WEAPON_CSV_PATH := "res://docs/design_docs/weapons.csv"
const MODIFIER_CSV_PATH := "res://docs/design_docs/modifiers.csv"

var _all_weapons: Array = []
var _modifier_data: Dictionary = {}  # id -> full CSV row
var _weapons_by_id: Dictionary = {}  # id -> overlaid Weapon (canonical copy)

const _RARITY_WORDS := {
	"Common": DropTable.ItemTier.COMMON,
	"Uncommon": DropTable.ItemTier.UNCOMMON,
	"Rare": DropTable.ItemTier.RARE,
}


func _ready() -> void:
	weapon_scripts["melee"] = preload("res://src/weapons/melee_weapon.gd")
	weapon_scripts["test"] = preload("res://src/weapons/test_weapon.gd")
	weapon_scripts["ranged"] = preload("res://src/weapons/ranged_weapon.gd")
	weapon_scripts["aimed_burst"] = preload("res://src/weapons/aimed_burst_weapon.gd")
	weapon_scripts["fan"] = preload("res://src/weapons/fan_weapon.gd")
	weapon_scripts["split_shot"] = preload("res://src/weapons/split_shot_weapon.gd")
	weapon_scripts["sniper"] = preload("res://src/weapons/sniper_weapon.gd")
	weapon_scripts["willowblade"] = preload("res://src/weapons/willowblade_weapon.gd")
	weapon_scripts["blood_blade"] = preload("res://src/weapons/blood_blade_weapon.gd")
	weapon_scripts["void_sword"] = preload("res://src/weapons/void_sword_weapon.gd")
	weapon_scripts["dragon_fang"] = preload("res://src/weapons/dragon_fang_weapon.gd")
	weapon_scripts["executioner"] = preload("res://src/weapons/executioner_weapon.gd")
	weapon_scripts["grand_knight"] = preload("res://src/weapons/grand_knight_weapon.gd")
	weapon_scripts["deep_dark"] = preload("res://src/weapons/deep_dark_weapon.gd")
	weapon_scripts["phantom_blade"] = preload("res://src/weapons/phantom_blade_weapon.gd")
	weapon_scripts["qinggang"] = preload("res://src/weapons/qinggang_weapon.gd")
	modifier_scripts["lava_emitter"] = preload("res://src/weapons/modifiers/lava_emitter_modifier.gd")
	modifier_scripts["fireball_fan"] = preload("res://src/weapons/modifiers/fireball_fan_modifier.gd")
	modifier_scripts["icicle_volley"] = preload("res://src/weapons/modifiers/icicle_volley_modifier.gd")
	modifier_scripts["gleaming_projectile"] = preload("res://src/weapons/modifiers/gleaming_projectile_modifier.gd")
	modifier_scripts["green_crescent"] = preload("res://src/weapons/modifiers/green_crescent_modifier.gd")
	modifier_scripts["arc_volley"] = preload("res://src/weapons/modifiers/arc_volley_modifier.gd")
	modifier_scripts["triangular_volley"] = preload("res://src/weapons/modifiers/triangular_volley_modifier.gd")
	modifier_scripts["splitting_rounds"] = preload("res://src/weapons/modifiers/splitting_rounds_modifier.gd")
	modifier_scripts["bouncing_bullets"] = preload("res://src/weapons/modifiers/bouncing_bullets_modifier.gd")
	modifier_scripts["penetrating_shockwave"] = preload("res://src/weapons/modifiers/penetrating_shockwave_modifier.gd")
	modifier_scripts["lightning_bolt"] = preload("res://src/weapons/modifiers/lightning_bolt_modifier.gd")
	_load_modifier_data()

	_load_weapon_resources()
	_build_tier_buckets()
	_populate_modifier_tiers()


func _load_weapon_resources() -> void:
	_all_weapons.clear()
	_weapons_by_id.clear()
	for row in CsvTable.parse(WEAPON_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		var arch: String = row.get("archetype", "").strip_edges()
		if arch == "":
			arch = "ranged" if row.get("type", "") == "Ranged" else "melee"
		var script: GDScript = weapon_scripts.get(arch)
		if script == null:
			push_warning("WeaponRegistry: weapon '%s' archetype '%s' not registered; skipping" % [id, arch])
			continue
		var weapon: Weapon = script.new()
		_apply_csv_fields(weapon, row)
		weapon.invalidate_effective_stats()
		_weapons_by_id[id] = weapon
		_all_weapons.append({ "id": id, "resource": weapon, "weight": 1.0 })


func _apply_csv_fields(weapon: Weapon, row: Dictionary) -> void:
	weapon.name = row.get("name", weapon.name)
	weapon.description = row.get("description", "")
	weapon.cooldown = float(row.get("cooldown", weapon.cooldown))
	weapon.damage = float(row.get("damage", weapon.damage))
	var cc: String = row.get("crit_chance", "")
	if cc != "":
		weapon.crit_chance = float(cc)
	var cm: String = row.get("crit_multiplier", "")
	if cm != "":
		weapon.crit_multiplier = float(cm)
	weapon.crit_status = row.get("crit_status", "")
	weapon.modifier_slot_count = int(row.get("modifier_slots", weapon.modifier_slot_count))
	weapon.rarity = _map_rarity(row.get("rarity", ""))
	_validate_type(weapon, row.get("type", ""))
	_apply_weapon_texture(weapon, row.get("weapon_texture", ""))
	_apply_tuning(weapon, row)
	_apply_pre_attached_modifiers(weapon, row)


func _map_rarity(word: String) -> int:
	if _RARITY_WORDS.has(word):
		return _RARITY_WORDS[word]
	push_warning("WeaponRegistry: unknown rarity '%s', defaulting to COMMON" % word)
	return DropTable.ItemTier.COMMON


func _validate_type(weapon: Weapon, type_word: String) -> void:
	var is_ranged: bool = weapon is RangedWeapon
	if type_word == "Ranged" and not is_ranged:
		push_warning("WeaponRegistry: '%s' CSV type Ranged but script is not RangedWeapon" % weapon.name)
	elif type_word == "Melee" and is_ranged:
		push_warning("WeaponRegistry: '%s' CSV type Melee but script is RangedWeapon" % weapon.name)


func _apply_weapon_texture(weapon: Weapon, tex_path: String) -> void:
	if tex_path == "":
		return
	var tex := load(tex_path)
	if tex is Texture2D:
		weapon.weapon_texture = tex
		weapon.icon_texture = tex
	else:
		push_warning("WeaponRegistry: could not load texture '%s'" % tex_path)


func _apply_tuning(weapon: Weapon, row: Dictionary) -> void:
	if weapon is MeleeWeapon:
		var reach: String = row.get("reach", "")
		if reach != "":
			(weapon as MeleeWeapon).weapon_reach = float(reach)
		var arc: String = row.get("arc", "")
		if arc != "":
			(weapon as MeleeWeapon).arc_angle = deg_to_rad(float(arc))
	elif weapon is RangedWeapon:
		var rw := weapon as RangedWeapon
		var ps: String = row.get("projectile_speed", "")
		if ps != "":
			rw.projectile_speed = float(ps)
		var pl: String = row.get("projectile_lifetime", "")
		if pl != "":
			rw.projectile_lifetime = float(pl)
		var sp: String = row.get("spread", "")
		if sp != "":
			rw.spread_angle = float(sp)
		var pc: String = row.get("projectile_count", "")
		if pc != "":
			rw.projectile_count = int(pc)
		var pt: String = row.get("projectile_texture", "")
		if pt != "":
			var tex := load(pt)
			if tex is Texture2D:
				rw.projectile_texture = tex

func _apply_pre_attached_modifiers(weapon: Weapon, row: Dictionary) -> void:
	for i in range(1, 4):
		var mod_id: String = row.get("pre_attached_modifier%d" % i, "")
		if mod_id == "":
			continue
		var mod := _make_modifier(mod_id)
		if mod == null:
			continue
		var slot := weapon.find_empty_modifier_slot()
		if slot >= 0:
			weapon.add_modifier(slot, mod)


func _build_tier_buckets() -> void:
	weapon_tiers.clear()
	for entry in _all_weapons:
		var res: Weapon = entry.resource
		var tier: int = res.rarity
		if not weapon_tiers.has(tier):
			weapon_tiers[tier] = []
		weapon_tiers[tier].append(WeaponDropEntry.new(res, entry.weight))


func _populate_modifier_tiers() -> void:
	modifier_tiers.clear()
	for id in _modifier_data.keys():
		var row: Dictionary = _modifier_data[id]
		var tier: int = _map_rarity(row.get("rarity", "Common"))
		if not modifier_tiers.has(tier):
			modifier_tiers[tier] = []
		modifier_tiers[tier].append(ModifierDropEntry.new(modifier_scripts.get(id), id, 1.0))


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


func get_weapon_by_id(id: String) -> _Weapon:
	var weapon: Weapon = _weapons_by_id.get(id)
	if weapon == null:
		push_warning("WeaponRegistry: unknown weapon id '%s'" % id)
		return null
	return weapon.duplicate(true)


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
			return _make_modifier(entry.modifier_id)
	return _make_modifier(entries[0].modifier_id)


func _load_modifier_data() -> void:
	_modifier_data.clear()
	for row in CsvTable.parse(MODIFIER_CSV_PATH):
		var id: String = row.get("id", "")
		if id == "":
			continue
		_modifier_data[id] = row


func _make_modifier(id: String) -> _Modifier:
	var data: Dictionary = _modifier_data.get(id, {})
	var script: GDScript = modifier_scripts.get(id)
	if script != null:
		var mod: _Modifier = script.new()
		mod.name = data.get("name", mod.name)
		mod.description = data.get("description", mod.description)
		mod.suppresses_base_use = String(data.get("suppresses_base_use", "No")).strip_edges() == "Yes"
		return mod
	if data.is_empty():
		push_warning("WeaponRegistry: unknown modifier id '%s'" % id)
		return null
	return _DataModifier.new(data)
