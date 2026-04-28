extends RefCounted

const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")
const MODIFIER_DROP_SCENE := preload("res://scenes/modifier_drop.tscn")
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")
const DUMMY_ENEMY_SCENE := preload("res://scenes/dummy_enemy.tscn")
const CHEST_SCENE := preload("res://scenes/chest.tscn")


static func register(registry: CommandRegistry) -> void:
	for key in WeaponRegistry.weapon_scripts:
		var type: String = key
		registry.register("spawn weapon " + type, "Spawn a " + type + " weapon drop", _spawn_weapon.bind(type))

	for key in WeaponRegistry.modifier_scripts:
		var type: String = key
		registry.register("spawn mod " + type, "Spawn a " + type + " modifier drop", _spawn_mod.bind(type))

	registry.register("spawn enemy dummy", "Spawn a dummy enemy", _spawn_enemy)
	registry.register("spawn gold", "Spawn a gold drop (default 10)", _spawn_gold)
	registry.register("spawn chest", "Spawn a chest", _spawn_chest)


static func _spawn_weapon(type: String, _args: Array[String], ctx: Dictionary) -> String:
	var script: GDScript = WeaponRegistry.weapon_scripts.get(type)
	if script == null:
		return "error: unknown weapon type '" + type + "'"
	var scene: Node = ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var drop: WeaponDrop = WEAPON_DROP_SCENE.instantiate()
	drop.weapon = script.new()
	scene.add_child(drop)
	drop.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + type + " weapon"


static func _spawn_mod(type: String, _args: Array[String], ctx: Dictionary) -> String:
	var script: GDScript = WeaponRegistry.modifier_scripts.get(type)
	if script == null:
		return "error: unknown modifier type '" + type + "'"
	var scene: Node = ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var drop: ModifierDrop = MODIFIER_DROP_SCENE.instantiate()
	drop.modifier = script.new()
	scene.add_child(drop)
	drop.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + type + " modifier"


static func _spawn_enemy(_args: Array[String], ctx: Dictionary) -> String:
	var scene: Node = ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var enemy: CharacterBody2D = DUMMY_ENEMY_SCENE.instantiate()
	scene.add_child(enemy)
	enemy.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned dummy enemy"


static func _spawn_gold(args: Array[String], ctx: Dictionary) -> String:
	var amount := 10
	if args.size() > 0 and args[0].is_valid_int():
		amount = args[0].to_int()
	var scene: Node = ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var drop: GoldDrop = GOLD_DROP_SCENE.instantiate()
	drop.set_amount(amount)
	scene.add_child(drop)
	drop.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned " + str(amount) + " gold"


static func _spawn_chest(_args: Array[String], ctx: Dictionary) -> String:
	var scene: Node = ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var chest: Chest = CHEST_SCENE.instantiate()
	scene.add_child(chest)
	chest.global_position = ctx.get("world_pos", Vector2.ZERO)
	return "Spawned chest"
