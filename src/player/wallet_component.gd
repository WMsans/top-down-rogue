# src/player/wallet_component.gd
class_name WalletComponent
extends Node

signal gold_changed(new_amount: int)

var gold: int = 0


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
