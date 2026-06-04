class_name Weapon
extends Resource

const CRIT_STATUS_STAIN := 2.0

@export var name: String = "Weapon"
@export var description: String = ""
@export var rarity: int = DropTable.ItemTier.COMMON
var cooldown: float = 0.8
var damage: float = 0.0
var crit_chance: float = 0.0
var crit_multiplier: float = 2.0
var crit_status: String = ""
var icon_texture: Texture2D = null
var visual: Node2D = null
var _sprite: Sprite2D = null
var modifier_slot_count: int = 3
var modifiers: Array = []
var _cooldown_timer: float = 0.0


func use(user: Node) -> void:
	if not is_ready():
		return
	for modifier in modifiers:
		if modifier != null:
			modifier.on_use(self, user)
	var suppress: bool = false
	for modifier in modifiers:
		if modifier != null and modifier.suppresses_base_use:
			suppress = true
			break
	if not suppress:
		_use_impl(user)
	_cooldown_timer = cooldown


func _use_impl(_user: Node) -> void:
	pass


func tick(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	for modifier in modifiers:
		if modifier != null:
			modifier.on_tick(self, delta)
	_tick_impl(delta)


func _tick_impl(_delta: float) -> void:
	pass


func is_ready() -> bool:
	return _cooldown_timer <= 0.0


func has_visual() -> bool:
	return false


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	visual = container
	_sprite = sprite


func update_visual(_delta: float, _user: Node) -> void:
	pass


func add_modifier(slot_index: int, modifier: Modifier) -> void:
	if slot_index < 0 or slot_index >= modifier_slot_count:
		return
	modifiers[slot_index] = modifier
	modifier.on_equip(self)


func get_modifier_at(slot_index: int) -> Modifier:
	if slot_index < 0 or slot_index >= modifiers.size():
		return null
	return modifiers[slot_index]


func find_empty_modifier_slot() -> int:
	for i in range(modifier_slot_count):
		if modifiers[i] == null:
			return i
	return -1


func get_base_stats() -> Dictionary:
	return {
		"name": name,
		"cooldown": cooldown,
		"damage": damage
	}


func get_effective_crit_chance() -> float:
	var c: float = crit_chance
	for modifier in modifiers:
		if modifier != null and modifier.has_method("modify_crit_chance"):
			c = modifier.modify_crit_chance(self, c)
	return clampf(c, 0.0, 1.0)


func roll_crit() -> bool:
	return randf() < get_effective_crit_chance()


func _on_crit(target: Node) -> void:
	if crit_status == "":
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain(crit_status, CRIT_STATUS_STAIN)


func get_stats() -> Dictionary:
	return get_base_stats()
