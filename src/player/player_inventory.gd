# src/player/player_inventory.gd
class_name PlayerInventory
extends Node

signal gold_changed(new_amount: int)
signal health_changed(current: int, maximum: int)
signal armor_changed(current: int, maximum: int)
signal weapon_changed(slot: int)
signal modifier_changed(weapon_slot: int, modifier_slot: int)
signal player_died()
signal damaged(amount: int)

@export var max_health: int = 3
@export var max_armor: int = 3
@export var invincibility_duration: float = 1.0

const BLINK_INTERVAL := 0.08
const DAMAGE_COLOR := Color(1.0, 0.25, 0.08)
const MAX_WEAPON_SLOTS := 3
# Armor comes back after ARMOR_REGEN_DELAY seconds without losing a point,
# then +1 every ARMOR_REGEN_INTERVAL. HP never regenerates.
const ARMOR_REGEN_DELAY := 3.0
const ARMOR_REGEN_INTERVAL := 1.0

var gold: int = 0
var _current_health: int
var _current_armor: int
var _regen_timer: float = 0.0  # seconds since the last point was lost
var _regen_next_at: float = ARMOR_REGEN_DELAY  # _regen_timer value that grants the next armor point
var _invincible_timer: float = 0.0
var _is_dead: bool = false
var _is_invincible: bool = false
var _blink_timer: float = 0.0
var _sprite: CanvasItem

var weapons: Array = [null, null, null]  # Array[Weapon], size MAX_WEAPON_SLOTS, null for empty
var active_weapon_slot: int = 0


func _ready() -> void:
	_current_health = max_health
	_current_armor = max_armor
	weapons.resize(MAX_WEAPON_SLOTS)
	var parent_player := get_parent()
	if parent_player:
		_sprite = parent_player.get_node_or_null("Sprite")


func _physics_process(delta: float) -> void:
	if _is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_is_invincible = false
			_invincible_timer = 0.0
			if not _is_dead and _sprite:
				_sprite.visible = true
	_tick_armor_regen(delta)


func _tick_armor_regen(delta: float) -> void:
	if _is_dead:
		return
	if _current_armor >= max_armor:
		_regen_timer = 0.0
		_regen_next_at = ARMOR_REGEN_DELAY
		return
	_regen_timer += delta
	while _regen_timer >= _regen_next_at and _current_armor < max_armor:
		_current_armor += 1
		_regen_next_at += ARMOR_REGEN_INTERVAL
		armor_changed.emit(_current_armor, max_armor)


func _process(delta: float) -> void:
	if _is_invincible and not _is_dead and _sprite:
		_blink_timer += delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer -= BLINK_INTERVAL
			_sprite.visible = not _sprite.visible


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

func take_hit(hit_direction: Vector2 = Vector2.ZERO) -> void:
	if _is_dead or _is_invincible:
		return
	_is_invincible = true
	_invincible_timer = invincibility_duration
	var player := get_parent()
	if player is Node2D:
		var spec := HitSpec.new()
		spec.position = (player as Node2D).global_position
		spec.direction = hit_direction
		spec.is_kill = _current_armor == 0 and _current_health <= 1
		spec.source_color = DAMAGE_COLOR
		HitReaction.play(spec)
		if HitReaction.vignette:
			HitReaction.vignette.pulse()
	_lose_point()


# Dash i-frames: shares the hit-invincibility timer, so a dash can never make
# the player *less* protected than a hit already did.
func grant_invincibility(duration: float) -> void:
	if duration <= 0.0 or _is_dead:
		return
	_is_invincible = true
	_invincible_timer = maxf(_invincible_timer, duration)


func is_invincible() -> bool:
	return _is_invincible


func take_status_tick() -> void:
	# Damage-over-time path: bypasses invincibility frames and the heavy hit
	# reaction. Still takes armor first and still triggers death.
	if _is_dead:
		return
	_lose_point()


func _lose_point() -> void:
	if _current_armor > 0:
		_current_armor -= 1
		armor_changed.emit(_current_armor, max_armor)
	else:
		_current_health = maxi(_current_health - 1, 0)
		health_changed.emit(_current_health, max_health)
	_regen_timer = 0.0
	_regen_next_at = ARMOR_REGEN_DELAY
	damaged.emit(1)
	if _current_health <= 0:
		_on_health_depleted()


func _on_health_depleted() -> void:
	if GameModeManager.is_creative():
		_current_health = max_health
		_current_armor = max_armor
		health_changed.emit(_current_health, max_health)
		armor_changed.emit(_current_armor, max_armor)
		return
	_is_dead = true
	if _sprite:
		_sprite.visible = true
	player_died.emit()


func get_health_fraction() -> float:
	return float(_current_health) / float(maxi(1, max_health))


func heal(amount: int) -> void:
	if _is_dead or amount <= 0:
		return
	_current_health = mini(_current_health + amount, max_health)
	health_changed.emit(_current_health, max_health)


func is_dead() -> bool:
	return _is_dead


func get_health() -> int:
	return _current_health


func get_max_health() -> int:
	return max_health


func get_armor() -> int:
	return _current_armor


func get_max_armor() -> int:
	return max_armor


func set_max_armor(value: int) -> void:
	max_armor = maxi(0, value)
	_current_armor = mini(_current_armor, max_armor)
	armor_changed.emit(_current_armor, max_armor)


func skip_armor_regen_delay() -> void:
	_regen_timer = maxf(_regen_timer, _regen_next_at)


# ---- Weapons ----

func equip_weapon(slot: int, weapon) -> void:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return
	weapons[slot] = weapon
	weapon_changed.emit(slot)


func remove_weapon(slot: int) -> Weapon:
	if slot < 0 or slot >= MAX_WEAPON_SLOTS:
		return null
	var old: Weapon = weapons[slot]
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
