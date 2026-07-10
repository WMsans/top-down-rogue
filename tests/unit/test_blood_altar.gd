extends GdUnitTestSuite

const _BloodAltar = preload("res://src/core/interactables/blood_altar.gd")

class _FakeInv extends Node:
	var hp: int = 100
	var taken: int = 0
	func get_health() -> int:
		return hp
	func take_status_damage(a: int) -> void:
		taken += a

func _make_player() -> Node2D:
	var player := Node2D.new()
	var inv := _FakeInv.new()
	inv.name = "PlayerInventory"
	player.add_child(inv)
	return player

func test_blood_altar_costs_quarter_hp_and_spawns_chest() -> void:
	var parent := Node2D.new()
	add_child(parent)
	var altar := _BloodAltar.new()
	parent.add_child(altar)          # triggers _ready
	var player := _make_player()
	add_child(player)

	altar.interact(player)

	var inv := player.get_node("PlayerInventory") as _FakeInv
	assert_int(inv.taken).is_equal(25)   # 25% of 100
	var chests := parent.get_children().filter(func(n): return n is Chest)
	assert_int(chests.size()).is_equal(1)

	parent.queue_free()
	player.queue_free()

func test_blood_altar_interact_is_one_shot() -> void:
	var parent := Node2D.new()
	add_child(parent)
	var altar := _BloodAltar.new()
	parent.add_child(altar)
	var player := _make_player()
	add_child(player)

	altar.interact(player)
	altar.interact(player)   # already consumed — no second charge

	var inv := player.get_node("PlayerInventory") as _FakeInv
	assert_int(inv.taken).is_equal(25)
	parent.queue_free()
	player.queue_free()
