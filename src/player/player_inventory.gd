# src/player/player_inventory.gd
class_name PlayerInventory
extends Node

signal gold_changed(new_amount: int)
signal health_changed(current: int, maximum: int)
signal weapon_changed(slot: int)
signal modifier_changed(weapon_slot: int, modifier_slot: int)
signal player_died()

@export var max_health: int = 100
@export var invincibility_duration: float = 1.0

const BLINK_INTERVAL := 0.08
const MAX_WEAPON_SLOTS := 3

var gold: int = 0
var _current_health: int
var _invincible_timer: float = 0.0
var _is_dead: bool = false
var _is_invincible: bool = false
var _blink_timer: float = 0.0
var _color_rect: ColorRect

var weapons: Array = []  # Array[Weapon], size MAX_WEAPON_SLOTS, null for empty
var active_weapon_slot: int = 0


func _ready() -> void:
	_current_health = max_health
	weapons.resize(MAX_WEAPON_SLOTS)
	var parent_player := get_parent()
	if parent_player:
		_color_rect = parent_player.get_node_or_null("ColorRect")


func _physics_process(delta: float) -> void:
	if _is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_is_invincible = false
			_invincible_timer = 0.0
			if not _is_dead and _color_rect:
				_color_rect.visible = true


func _process(delta: float) -> void:
	if _is_invincible and not _is_dead and _color_rect:
		_blink_timer += delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer -= BLINK_INTERVAL
			_color_rect.visible = not _color_rect.visible


# ---- Gold ----

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# ---- Health ----

func take_damage(amount: int) -> void:
	if _is_dead or _is_invincible:
		return
	_current_health = maxi(_current_health - amount, 0)
	_is_invincible = true
	_invincible_timer = invincibility_duration
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0:
		_is_dead = true
		if _color_rect:
			_color_rect.visible = true
		player_died.emit()


func heal(amount: int) -> void:
	if _is_dead:
		return
	_current_health = mini(_current_health + amount, max_health)
	health_changed.emit(_current_health, max_health)


func is_dead() -> bool:
	return _is_dead


func get_health() -> int:
	return _current_health


func get_max_health() -> int:
	return max_health


# ---- Weapons ----

func equip_weapon(slot: int, weapon) -> void:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return
	weapons[slot] = weapon
	weapon_changed.emit(slot)


func remove_weapon(slot: int):
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null
	var old := weapons[slot]
	weapons[slot] = null
	weapon_changed.emit(slot)
	return old


func get_weapon(slot: int):
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null
	return weapons[slot]


func get_weapon_count() -> int:
	var count := 0
	for w in weapons:
		if w != null:
			count += 1
	return count


func has_empty_weapon_slot() -> bool:
	for w in weapons:
		if w == null:
			return true
	return false


func find_empty_weapon_slot() -> int:
	for i in range(MAX_WEAPON_SLOTS):
		if weapons[i] == null:
			return i
	return -1


# ---- Modifiers ----

func can_equip_modifier(weapon_slot: int) -> bool:
	var weapon = get_weapon(weapon_slot)
	if weapon == null:
		return false
	return weapon.find_empty_modifier_slot() >= 0


func add_modifier_to_weapon(weapon_slot: int, modifier_slot: int, modifier) -> void:
	var weapon = get_weapon(weapon_slot)
	if weapon == null:
		return
	weapon.add_modifier(modifier_slot, modifier)
	modifier_changed.emit(weapon_slot, modifier_slot)


func get_free_modifier_slot(weapon_slot: int) -> int:
	var weapon = get_weapon(weapon_slot)
	if weapon == null:
		return -1
	return weapon.find_empty_modifier_slot()


func get_all_modifiers() -> Array:
	var result: Array = []
	for weapon in weapons:
		if weapon == null:
			continue
		for m in weapon.modifiers:
			if m != null:
				result.append(m)
	return result


# ---- Modifier Inventory ----

var _stored_modifiers: Array = []

func add_modifier_to_inventory(modifier) -> void:
	_stored_modifiers.append(modifier)


func remove_modifier_from_inventory(modifier) -> bool:
	var idx := _stored_modifiers.find(modifier)
	if idx < 0:
		return false
	_stored_modifiers.remove_at(idx)
	return true


func get_stored_modifiers() -> Array:
	return _stored_modifiers.duplicate()


func has_stored_modifiers() -> bool:
	return _stored_modifiers.size() > 0
