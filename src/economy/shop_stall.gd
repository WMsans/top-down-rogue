class_name ShopStall
extends Node2D

const SHOP_WEAPON_DROP := preload("res://scenes/economy/shop_weapon_drop.tscn")
const SHOP_MODIFIER_DROP := preload("res://scenes/economy/shop_modifier_drop.tscn")
const SHOP_REMOVAL := preload("res://scenes/economy/shop_removal.tscn")

const MODIFIER_COUNT := 5
const WEAPON_COUNT := 3
const MODIFIER_Y := -80.0
const MODIFIER_XS: Array[float] = [-100.0, -50.0, 0.0, 50.0, 100.0]
const WEAPON_Y := 50.0
const WEAPON_XS: Array[float] = [-70.0, 0.0, 70.0]
const REMOVAL_OFFSET := Vector2(95.0, 95.0)


func _ready() -> void:
	_spawn_modifiers()
	_spawn_weapons()
	_spawn_removal()


func _spawn_modifiers() -> void:
	var seen: Dictionary = {}
	for i in MODIFIER_COUNT:
		var tier := DropTable.ItemTier.COMMON
		var modifier := _roll_modifier(tier, seen)
		if modifier == null:
			continue
		var drop: ShopModifierDrop = SHOP_MODIFIER_DROP.instantiate()
		drop.modifier = modifier
		drop.price = ShopPricing.price_for_modifier_tier(tier)
		drop.position = Vector2(MODIFIER_XS[i], MODIFIER_Y)
		add_child(drop)


func _spawn_weapons() -> void:
	var seen: Dictionary = {}
	for i in WEAPON_COUNT:
		var tier := DropTable.resolve_item_tier(DropTable.EnemyTier.NORMAL)
		var weapon := _roll_weapon(tier, seen)
		if weapon == null:
			continue
		var drop: ShopWeaponDrop = SHOP_WEAPON_DROP.instantiate()
		drop.weapon = weapon
		drop.price = ShopPricing.price_for_weapon(weapon)
		drop.position = Vector2(WEAPON_XS[i], WEAPON_Y)
		add_child(drop)


func _spawn_removal() -> void:
	var removal: ShopRemoval = SHOP_REMOVAL.instantiate()
	removal.position = REMOVAL_OFFSET
	add_child(removal)


func _roll_modifier(tier: int, seen: Dictionary) -> Modifier:
	var result: Modifier = null
	for _attempt in range(5):
		var cand := WeaponRegistry.get_random_modifier(tier)
		if cand == null:
			break
		result = cand
		var key = cand.get_script()
		if not seen.has(key):
			seen[key] = true
			break
	return result


func _roll_weapon(tier: int, seen: Dictionary) -> Weapon:
	var result: Weapon = null
	for _attempt in range(5):
		var cand := WeaponRegistry.get_random_weapon(tier)
		if cand == null:
			break
		result = cand
		var key = cand.get_script()
		if not seen.has(key):
			seen[key] = true
			break
	return result
