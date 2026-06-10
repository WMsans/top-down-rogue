class_name LightningBoltModifier
extends Modifier

const RANGE := 160.0
const DAMAGE := 6
const FROZEN_STAIN := 3.0

var proc_chance: float = 0.25

func _init() -> void:
	name = "Lightning Bolt"
	description = "Calls a bolt of lightning down onto a marked target with a chance to stun. Not triggered every attack."
	icon_texture = preload("res://textures/wall.png")

func on_attack(_weapon, user, _ctx) -> void:
	if randf() >= proc_chance:
		return
	var target := _nearest_target(user)
	if target == null:
		return
	if target.has_method("on_hit_impact"):
		var dir: Vector2 = target.global_position - user.global_position
		target.on_hit_impact(target.global_position, dir, DAMAGE)
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain("frozen", FROZEN_STAIN)
	_play_fx(user, target.global_position)

func _nearest_target(user: Node) -> Node2D:
	var tree := user.get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d := RANGE * RANGE
	for n in tree.get_nodes_in_group("attackable"):
		if n == user or not is_instance_valid(n) or not (n is Node2D):
			continue
		var d: float = (user as Node2D).global_position.distance_squared_to((n as Node2D).global_position)
		if d <= best_d:
			best_d = d
			best = n
	return best

func _play_fx(user: Node, pos: Vector2) -> void:
	var parent := user.get_parent()
	if parent == null:
		return
	var fx := Sprite2D.new()
	fx.texture = preload("res://textures/wall.png")
	fx.modulate = Color(0.8, 0.85, 1.0)
	parent.add_child(fx)
	fx.global_position = pos
	var tree := user.get_tree()
	if tree != null:
		tree.create_timer(0.15).timeout.connect(fx.queue_free)
