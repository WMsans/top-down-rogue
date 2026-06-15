class_name Weapon
extends Resource

const CRIT_STATUS_STAIN := 2.0

@export var name: String = "Weapon"
@export var description: String = ""
@export var rarity: int = DropTable.ItemTier.COMMON
@export var cooldown: float = 0.8
@export var damage: float = 0.0
@export var crit_chance: float = 0.0
@export var crit_multiplier: float = 2.0
@export var crit_status: String = ""
var icon_texture: Texture2D = null
var visual: Node2D = null
var _sprite: Sprite2D = null
var modifier_slot_count: int = 3
var modifiers: Array = []
var _cooldown_timer: float = 0.0
const COOLDOWN_FLOOR := 0.1
var _effective_cache: Dictionary = {}


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
	_cooldown_timer = get_effective_stats()["cooldown"]


func notify_attack(user: Node, ctx: Dictionary) -> void:
	for modifier in modifiers:
		if modifier != null:
			modifier.on_attack(self, user, ctx)


func on_press(user: Node) -> void:
	use(user)


func on_release(_user: Node) -> void:
	pass


func get_charge_ratio() -> float:
	return 0.0


func is_chargeable() -> bool:
	return false


func is_charging() -> bool:
	return false


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
	modifiers.resize(max(modifiers.size(), modifier_slot_count))
	modifiers[slot_index] = modifier
	modifier.on_equip(self)
	invalidate_effective_stats()


func get_modifier_at(slot_index: int) -> Modifier:
	if slot_index < 0 or slot_index >= modifiers.size():
		return null
	return modifiers[slot_index]


func find_empty_modifier_slot() -> int:
	for i in range(modifier_slot_count):
		if modifiers[i] == null:
			return i
	return -1


func _seed_effective_stats() -> Dictionary:
	return {
		"damage": damage,
		"cooldown": cooldown,
		"crit_chance": crit_chance,
		"crit_multiplier": crit_multiplier,
		"reach": 0.0,
		"arc": 0.0,
		"move_speed": 1.0,
		"carve_depth": 1.0,
	}


func get_effective_stats() -> Dictionary:
	if not _effective_cache.is_empty():
		return _effective_cache
	var s := _seed_effective_stats()
	for stat in s.keys():
		var v: float = s[stat]
		for m in modifiers:
			if m != null:
				v += m.get_stat_add(stat)
		for m in modifiers:
			if m != null:
				v *= m.get_stat_mult(stat)
		s[stat] = v
	s["cooldown"] = maxf(COOLDOWN_FLOOR, s["cooldown"])
	_effective_cache = s
	return s


func invalidate_effective_stats() -> void:
	_effective_cache = {}


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
