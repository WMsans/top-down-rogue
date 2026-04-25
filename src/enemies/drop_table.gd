class_name DropTable
extends Resource

class DropEntry:
	var scene: PackedScene
	var weight: float
	var min_count: int = 1
	var max_count: int = 1
	var gold_per_drop: int = 0

	func _init(p_scene: PackedScene, p_weight: float, p_min: int = 1, p_max: int = 1, p_gold: int = 0):
		scene = p_scene
		weight = p_weight
		min_count = p_min
		max_count = p_max
		gold_per_drop = p_gold

var entries: Array[DropEntry] = []


func add_entry(entry: DropEntry) -> void:
	entries.append(entry)


func resolve(position: Vector2, parent: Node) -> void:
	for entry in entries:
		var roll := randf()
		if roll > entry.weight:
			continue
		var count := randi_range(entry.min_count, entry.max_count)
		for i in count:
			var drop: Node = entry.scene.instantiate()
			if drop.has_method("set_amount") and entry.gold_per_drop > 0:
				drop.set_amount(entry.gold_per_drop)
			var offset := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
			parent.add_child(drop)
			drop.global_position = position + offset
