class_name ShopStall
extends Node2D

# Compact Soul Knight-style trader: a merchant behind a counter, goods on small
# tables in two tight rows. No walls or floor patch: it sits on the cave floor.

const SHOP_WEAPON_DROP := preload("res://scenes/economy/shop_weapon_drop.tscn")
const SHOP_MODIFIER_DROP := preload("res://scenes/economy/shop_modifier_drop.tscn")
const SHOP_REMOVAL := preload("res://scenes/economy/shop_removal.tscn")

const DECOR_SHEET := preload("res://textures/Assets/DawnLike/Objects/Decor0.png")
const MERCHANT_FRAMES: Array[Texture2D] = [
	preload("res://textures/Assets/DawnLike/Characters/Humanoid0.png"),
	preload("res://textures/Assets/DawnLike/Characters/Humanoid1.png"),
]

const MERCHANT_REGION := Rect2(16, 368, 16, 16)   # hooded trader with pack
const COUNTER_REGION := Rect2(0, 160, 48, 16)
const TABLE_REGION := Rect2(64, 112, 16, 16)
const MERCHANT_FPS := 2.0

const MODIFIER_COUNT := 5
const WEAPON_COUNT := 3
const MERCHANT_POS := Vector2(0.0, -34.0)
const COUNTER_POS := Vector2(0.0, -20.0)
const MODIFIER_Y := 0.0
const MODIFIER_XS: Array[float] = [-44.0, -22.0, 0.0, 22.0, 44.0]
const FRONT_ROW_Y := 30.0
const WEAPON_XS: Array[float] = [-33.0, -11.0, 11.0]
const REMOVAL_OFFSET := Vector2(33.0, FRONT_ROW_Y)
const TABLE_OFFSET := Vector2(0.0, 6.0)          # item rests on the table's top

var _tables: Node2D


func _ready() -> void:
	_spawn_merchant()
	_spawn_counter()
	_tables = Node2D.new()
	_tables.name = "Tables"
	add_child(_tables)
	_spawn_modifiers()
	_spawn_weapons()
	_spawn_removal()


func _spawn_merchant() -> void:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", MERCHANT_FPS)
	for sheet in MERCHANT_FRAMES:
		frames.add_frame(&"default", _atlas(sheet, MERCHANT_REGION))
	var merchant := AnimatedSprite2D.new()
	merchant.name = "Merchant"
	merchant.sprite_frames = frames
	merchant.position = MERCHANT_POS
	add_child(merchant)
	merchant.play(&"default")


func _spawn_counter() -> void:
	var counter := Sprite2D.new()
	counter.name = "Counter"
	counter.texture = _atlas(DECOR_SHEET, COUNTER_REGION)
	counter.position = COUNTER_POS
	add_child(counter)


func _place_table(item_pos: Vector2) -> void:
	var table := Sprite2D.new()
	table.texture = _atlas(DECOR_SHEET, TABLE_REGION)
	table.position = item_pos + TABLE_OFFSET
	_tables.add_child(table)


static func _atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = region
	return tex


func _spawn_modifiers() -> void:
	var seen: Dictionary = {}
	for i in MODIFIER_COUNT:
		var tier := DropTable.roll_modifier_tier()
		var modifier := _roll_modifier(tier, seen)
		if modifier == null:
			continue
		var drop: ShopModifierDrop = SHOP_MODIFIER_DROP.instantiate()
		drop.modifier = modifier
		drop.price = ShopPricing.price_for_modifier_tier(tier)
		drop.position = Vector2(MODIFIER_XS[i], MODIFIER_Y)
		_place_table(drop.position)
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
		drop.position = Vector2(WEAPON_XS[i], FRONT_ROW_Y)
		_place_table(drop.position)
		add_child(drop)


func _spawn_removal() -> void:
	var removal: ShopRemoval = SHOP_REMOVAL.instantiate()
	removal.position = REMOVAL_OFFSET
	_place_table(removal.position)
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
