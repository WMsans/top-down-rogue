class_name WeaponDelivery
extends Node

var _player: Node2D
var _inventory: PlayerInventory
var _popup = null
var _pending_callback: Callable
var _test_mode: bool = false
var _test_response_accepted: bool = false
var _test_response_slot: int = 0


func _ready() -> void:
	_player = get_parent()
	_inventory = _player.get_node_or_null("PlayerInventory")


func offer(spec: WeaponOfferSpec, callback: Callable) -> void:
	match spec.type:
		WeaponOfferSpec.OfferType.WEAPON:
			_offer_weapon(spec, callback)
		WeaponOfferSpec.OfferType.MODIFIER:
			_offer_modifier(spec, callback)
		WeaponOfferSpec.OfferType.REMOVE_MODIFIER:
			_offer_remove_modifier(spec, callback)


func _offer_weapon(spec: WeaponOfferSpec, callback: Callable) -> void:
	if not _inventory:
		callback.call(false, -1)
		return
	if _test_mode:
		if _test_response_accepted:
			var old := _inventory.remove_weapon(_test_response_slot)
			_inventory.equip_weapon(_test_response_slot, spec.weapon)
			if old and spec.weapon and old.modifiers:
				for i in range(min(old.modifiers.size(), spec.weapon.modifier_slot_count)):
					if old.modifiers[i] != null:
						spec.weapon.add_modifier(i, old.modifiers[i])
		callback.call(_test_response_accepted, _test_response_slot)
		return
	var popup := _get_weapon_popup()
	if popup == null:
		callback.call(false, -1)
		return
	var weapon_manager := _player.get_node_or_null("WeaponManager")
	_pending_callback = callback
	popup.open_for_pickup(weapon_manager, spec.weapon, _on_weapon_slot_selected)


func _offer_modifier(spec: WeaponOfferSpec, callback: Callable) -> void:
	if not _inventory:
		callback.call(false, -1)
		return
	if not _inventory.can_equip_modifier(spec.suggested_slot):
		var found := false
		for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
			var free_slot := _inventory.get_free_modifier_slot(i)
			if free_slot >= 0:
				spec.suggested_slot = i
				found = true
				break
		if not found:
			var wpn_button := _player.get_parent().get_node_or_null("WeaponButton")
			if wpn_button and wpn_button.has_method("flash_slots_full"):
				wpn_button.flash_slots_full()
			callback.call(false, -1)
			return
	if _test_mode:
		if _test_response_accepted:
			_inventory.add_modifier_to_weapon(spec.suggested_slot, _test_response_slot, spec.modifier)
		callback.call(_test_response_accepted, _test_response_slot)
		return
	var popup := _get_weapon_popup()
	if popup == null:
		callback.call(false, -1)
		return
	var weapon_manager := _player.get_node_or_null("WeaponManager")
	_pending_callback = callback
	popup.open_for_modifier(weapon_manager, spec.modifier, _on_modifier_applied)


func _offer_remove_modifier(spec: WeaponOfferSpec, callback: Callable) -> void:
	if _test_mode:
		callback.call(_test_response_accepted, _test_response_slot)
		return
	var popup := _get_weapon_popup()
	if popup == null:
		callback.call(false, -1)
		return
	var weapon_manager := _player.get_node_or_null("WeaponManager")
	_pending_callback = callback
	popup.open_for_remove(weapon_manager, _on_remove_modifier_applied)


func _on_weapon_slot_selected(slot_index: int, modifier) -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(true, slot_index)
	_pending_callback = Callable()


func _on_modifier_applied() -> void:
	if _pending_callback.is_valid():
		_pending_callback.call(true, 0)
	_pending_callback = Callable()


func _on_remove_modifier_applied(weapon: Weapon, slot_idx: int) -> void:
	weapon.modifiers[slot_idx] = null
	if _pending_callback.is_valid():
		_pending_callback.call(true, 0)
	_pending_callback = Callable()


func _get_weapon_popup():
	if _popup and is_instance_valid(_popup):
		return _popup
	var root := _player.get_parent()
	if root:
		_popup = root.get_node_or_null("WeaponPopup")
	return _popup
