class_name DataModifier
extends Modifier

const EMITTER_FORWARD := 14.0
const KNOCKBACK_RADIUS_FACTOR := 1.8

var category: String = ""
var trigger: String = ""
var condition: String = ""
var effect: String = ""
var element: String = ""
var magnitude: float = 0.0
var magnitude2: float = 0.0
var _kill_stacks: float = 0.0
var _hit_streak: float = 0.0
var _time_since_event: float = 0.0

const _MATERIAL_IDS := {
	"oil": "MAT_OIL", "water": "MAT_WATER", "gas": "MAT_GAS", "ice": "MAT_ICE",
	"blood": "MAT_BLOOD", "coal": "MAT_COAL", "dust": "MAT_DUST", "lava": "MAT_LAVA",
}


func _init(row: Dictionary = {}) -> void:
	name = row.get("name", "Modifier")
	description = row.get("description", "")
	suppresses_base_use = String(row.get("suppresses_base_use", "No")).strip_edges() == "Yes"
	category = row.get("category", "")
	trigger = row.get("trigger", "")
	condition = row.get("condition", "")
	effect = row.get("effect", "")
	element = row.get("element", "")
	magnitude = float(row.get("magnitude", "0"))
	magnitude2 = float(row.get("magnitude2", "0"))


func _material_id() -> int:
	var key: String = _MATERIAL_IDS.get(element, "")
	if key == "":
		return -1
	return MaterialRegistry.get(key)


func on_attack(_weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if effect == "spawn_material" and trigger == "on_swing":
		_spawn_material(user, ctx)
	elif effect == "knockback":
		_do_knockback(user, ctx)


func _spawn_material(user: Node, ctx: Dictionary) -> void:
	var mat := _material_id()
	if mat < 0:
		return
	var origin: Vector2 = ctx.get("origin", Vector2.ZERO)
	var dir: Vector2 = ctx.get("direction", Vector2.DOWN)
	var at: Vector2 = origin + dir * EMITTER_FORWARD
	TerrainSurface.place_material(at, magnitude, mat)


func _do_knockback(user: Node, ctx: Dictionary) -> void:
	if trigger == "on_charge":
		if not ctx.get("charged", false) or ctx.get("charge_ratio", 0.0) < 1.0:
			return
	elif trigger != "on_swing":
		return
	if user == null or not (user is Node2D):
		return
	var radius: float = magnitude * KNOCKBACK_RADIUS_FACTOR
	for n in _radial_targets(user, radius):
		var dir: Vector2 = (n as Node2D).global_position - (user as Node2D).global_position
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		n.apply_knockback(dir, magnitude)


func _radial_targets(user: Node, radius: float) -> Array:
	var out: Array = []
	var tree := user.get_tree()
	if tree == null:
		return out
	var origin: Vector2 = (user as Node2D).global_position
	var r2: float = radius * radius
	for n in tree.get_nodes_in_group("attackable"):
		if n == user or not is_instance_valid(n) or not (n is Node2D):
			continue
		if not n.has_method("apply_knockback"):
			continue
		if origin.distance_squared_to((n as Node2D).global_position) <= r2:
			out.append(n)
	return out


func _condition_met(target: Node) -> bool:
	if condition == "":
		return true
	if condition.begins_with("target_status:"):
		var id := condition.substr("target_status:".length())
		var sc = target.get_node_or_null("StatusComponent") if target else null
		if sc != null:
			return sc.get_stain(id) > 0.0
		return false
	if condition == "target_low_hp":
		if target == null or not ("health" in target) or not ("max_health" in target):
			return false
		var frac: float = target.health / maxf(1.0, target.max_health)
		var thresh: float = magnitude2 if magnitude2 > 0.0 else 0.3
		return frac <= thresh
	return true


func modify_hit_damage(_weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if trigger == "on_hit" and effect == "stat_mult" and element == "damage":
		if condition == "":
			if name == "Momentum":
				var frac := _speed_fraction(user)
				return dmg * lerpf(1.0, magnitude, frac)
			if magnitude2 > 0.0:
				return dmg + _hit_streak
		elif condition == "self_full_hp":
			if _self_full_hp(user):
				return dmg * magnitude
		elif _condition_met(target):
			return dmg * magnitude
	return dmg


func _speed_fraction(user: Node) -> float:
	if user != null and "velocity" in user and "max_speed" in user:
		return clampf((user.velocity as Vector2).length() / maxf(1.0, user.max_speed), 0.0, 1.0)
	return 0.0


func _self_full_hp(user: Node) -> bool:
	var inv = user.get_node_or_null("PlayerInventory") if user else null
	return inv != null and inv.has_method("is_full_health") and inv.is_full_health()


func on_hit_target(_weapon: Weapon, _user: Node, target: Node) -> void:
	if trigger == "on_hit" and effect == "apply_status":
		var sc = target.get_node_or_null("StatusComponent")
		if sc != null:
			sc.add_stain(element, magnitude)
	if name == "Rampage":
		_hit_streak = minf(_hit_streak + magnitude, magnitude2)
		_time_since_event = 0.0


func on_kill(_weapon: Weapon, user: Node, _target: Node) -> void:
	if trigger != "on_kill":
		return
	if effect == "stat_add" and element == "damage":
		_kill_stacks = minf(_kill_stacks + magnitude, magnitude2)
		_time_since_event = 0.0
	elif effect == "heal":
		var inv = user.get_node_or_null("PlayerInventory") if user else null
		if inv != null and inv.has_method("heal"):
			inv.heal(int(magnitude))


func get_stat_add(stat: String) -> float:
	if effect == "stat_add" and element == stat and trigger == "passive":
		return magnitude
	if trigger == "on_kill" and effect == "stat_add" and element == stat:
		return _kill_stacks
	return 0.0


func get_stat_mult(stat: String) -> float:
	if effect == "stat_mult" and element == stat and trigger == "passive":
		return magnitude
	if effect == "stat_add" and element == "damage" and stat == "cooldown" and magnitude2 > 0.0 and trigger == "passive":
		return magnitude2
	return 1.0


func modify_crit_chance(weapon: Weapon, base: float) -> float:
	if trigger == "passive" and effect == "stat_add" and element == "crit_chance":
		return base + magnitude
	if trigger == "every_n_hits" and element == "crit_chance" and weapon != null:
		var n := int(magnitude2)
		if n > 0 and (weapon._hit_count % n) == n - 1:
			return 1.0
	return base


func on_tick(_weapon: Weapon, delta: float) -> void:
	_time_since_event += delta
	if name == "Bloodlust" and _time_since_event >= 3.0 and _kill_stacks > 0.0:
		_kill_stacks = maxf(0.0, _kill_stacks - 1.0)
		_time_since_event = 0.0
	if name == "Rampage" and _time_since_event >= 1.5:
		_hit_streak = 0.0
