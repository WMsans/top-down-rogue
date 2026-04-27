class_name DropTable
extends Resource

enum DropKind { GOLD, WEAPON_POOL, MODIFIER_POOL, SCENE }
enum ItemTier { COMMON, UNCOMMON, RARE }
enum EnemyTier { EASY, NORMAL, HARD }

class DropEntry:
	var kind: int = DropKind.SCENE
	var weight: float = 1.0
	var min_count: int = 1
	var max_count: int = 1
	var gold_per_drop: int = 0
	var item_tier: int = ItemTier.COMMON
	var scene: PackedScene = null

	func _init(p_kind: int = DropKind.SCENE, p_weight: float = 1.0, p_min: int = 1, p_max: int = 1, p_gold: int = 0, p_item_tier: int = ItemTier.COMMON, p_scene: PackedScene = null) -> void:
		kind = p_kind
		weight = p_weight
		min_count = p_min
		max_count = p_max
		gold_per_drop = p_gold
		item_tier = p_item_tier
		scene = p_scene

	static func gold(p_weight: float, p_min: int, p_max: int, p_gold_per_drop: int) -> DropEntry:
		return DropEntry.new(DropKind.GOLD, p_weight, p_min, p_max, p_gold_per_drop)

	static func weapon_pool(p_weight: float, p_tier: int, p_min: int = 1, p_max: int = 1) -> DropEntry:
		return DropEntry.new(DropKind.WEAPON_POOL, p_weight, p_min, p_max, 0, p_tier)

	static func modifier_pool(p_weight: float, p_tier: int, p_min: int = 1, p_max: int = 1) -> DropEntry:
		return DropEntry.new(DropKind.MODIFIER_POOL, p_weight, p_min, p_max, 0, p_tier)

	static func scene(p_scene: PackedScene, p_weight: float = 1.0, p_min: int = 1, p_max: int = 1) -> DropEntry:
		return DropEntry.new(DropKind.SCENE, p_weight, p_min, p_max, 0, ItemTier.COMMON, p_scene)

const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const MODIFIER_DROP_SCENE := preload("res://scenes/modifier_drop.tscn")

const _TIER_GOLD_MIN: Dictionary = {EnemyTier.EASY: 2, EnemyTier.NORMAL: 4, EnemyTier.HARD: 8}
const _TIER_GOLD_MAX: Dictionary = {EnemyTier.EASY: 5, EnemyTier.NORMAL: 10, EnemyTier.HARD: 20}
const _TIER_GOLD_PER_DROP: Dictionary = {EnemyTier.EASY: 5, EnemyTier.NORMAL: 5, EnemyTier.HARD: 5}
const _TIER_WEAPON_WEIGHT: Dictionary = {EnemyTier.EASY: 0.3, EnemyTier.NORMAL: 0.3, EnemyTier.HARD: 0.3}
const _TIER_MODIFIER_WEIGHT: Dictionary = {EnemyTier.EASY: 0.1, EnemyTier.NORMAL: 0.1, EnemyTier.HARD: 0.1}
const _TIER_ITEM_WEIGHTS: Dictionary = {
	EnemyTier.EASY: {ItemTier.COMMON: 0.70, ItemTier.UNCOMMON: 0.25, ItemTier.RARE: 0.05},
	EnemyTier.NORMAL: {ItemTier.COMMON: 0.50, ItemTier.UNCOMMON: 0.35, ItemTier.RARE: 0.15},
	EnemyTier.HARD: {ItemTier.COMMON: 0.30, ItemTier.UNCOMMON: 0.40, ItemTier.RARE: 0.30},
}

var entries: Array[DropEntry] = []


func add_entry(entry: DropEntry) -> void:
	entries.append(entry)


static func from_enemy_tier(tier: int, drops_gold: bool = true, drops_weapon: bool = true, drops_modifier: bool = true) -> DropTable:
	var table := DropTable.new()
	if drops_gold:
		table.add_entry(DropEntry.gold(1.0, _TIER_GOLD_MIN[tier], _TIER_GOLD_MAX[tier], _TIER_GOLD_PER_DROP[tier]))
	if drops_weapon:
		var weights: Dictionary = _TIER_ITEM_WEIGHTS[tier]
		for item_tier in weights:
			table.add_entry(DropEntry.weapon_pool(_TIER_WEAPON_WEIGHT[tier] * float(weights[item_tier]), item_tier))
	if drops_modifier:
		var weights: Dictionary = _TIER_ITEM_WEIGHTS[tier]
		for item_tier in weights:
			table.add_entry(DropEntry.modifier_pool(_TIER_MODIFIER_WEIGHT[tier] * float(weights[item_tier]), item_tier))
	return table


static func resolve_item_tier(enemy_tier: int) -> int:
	var weights: Dictionary = _TIER_ITEM_WEIGHTS[enemy_tier]
	var roll := randf()
	var cumulative := 0.0
	for item_tier in [ItemTier.COMMON, ItemTier.UNCOMMON, ItemTier.RARE]:
		cumulative += float(weights[item_tier])
		if roll <= cumulative:
			return item_tier
	return ItemTier.COMMON


func resolve(position: Vector2, parent: Node) -> void:
	for entry in entries:
		var roll := randf()
		if roll > entry.weight:
			continue
		var count := randi_range(entry.min_count, entry.max_count)
		for i in count:
			match entry.kind:
				DropKind.GOLD:
					_resolve_gold(position, parent, entry)
				DropKind.WEAPON_POOL:
					_resolve_weapon_pool(position, parent, entry)
				DropKind.MODIFIER_POOL:
					_resolve_modifier_pool(position, parent, entry)
				DropKind.SCENE:
					_resolve_scene(position, parent, entry)


func _resolve_gold(position: Vector2, parent: Node, entry: DropEntry) -> void:
	var drop: Node = GOLD_DROP_SCENE.instantiate()
	if drop.has_method("set_amount") and entry.gold_per_drop > 0:
		drop.set_amount(entry.gold_per_drop)
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset


func _resolve_weapon_pool(position: Vector2, parent: Node, entry: DropEntry) -> void:
	var weapon := WeaponRegistry.get_random_weapon(entry.item_tier)
	if weapon == null:
		return
	var drop: Node = WEAPON_DROP_SCENE.instantiate()
	drop.weapon = weapon
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset


func _resolve_modifier_pool(position: Vector2, parent: Node, entry: DropEntry) -> void:
	var modifier := WeaponRegistry.get_random_modifier(entry.item_tier)
	if modifier == null:
		return
	var drop: Node = MODIFIER_DROP_SCENE.instantiate()
	drop.modifier = modifier
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset


func _resolve_scene(position: Vector2, parent: Node, entry: DropEntry) -> void:
	if entry.scene == null:
		return
	var drop: Node = entry.scene.instantiate()
	if drop.has_method("set_amount") and entry.gold_per_drop > 0:
		drop.set_amount(entry.gold_per_drop)
	var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	parent.add_child(drop)
	drop.global_position = position + offset