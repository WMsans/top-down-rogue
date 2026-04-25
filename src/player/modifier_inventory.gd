# src/player/modifier_inventory.gd
class_name ModifierInventory
extends Node

signal modifier_added(modifier: Modifier)
signal modifier_removed(modifier: Modifier)

var _modifiers: Array[Modifier] = []


func add_modifier(modifier: Modifier) -> void:
	_modifiers.append(modifier)
	modifier_added.emit(modifier)


func remove_modifier(modifier: Modifier) -> bool:
	var idx := _modifiers.find(modifier)
	if idx < 0:
		return false
	_modifiers.remove_at(idx)
	modifier_removed.emit(modifier)
	return true


func get_modifiers() -> Array[Modifier]:
	return _modifiers.duplicate()


func has_modifiers() -> bool:
	return _modifiers.size() > 0
