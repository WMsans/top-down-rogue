class_name DataModifier
extends Modifier

const EMITTER_FORWARD := 14.0

var category: String = ""
var trigger: String = ""
var condition: String = ""
var effect: String = ""
var element: String = ""
var magnitude: float = 0.0
var magnitude2: float = 0.0

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
	if trigger != "on_swing":
		return
	if effect == "spawn_material":
		_spawn_material(user, ctx)


func _spawn_material(user: Node, ctx: Dictionary) -> void:
	var mat := _material_id()
	if mat < 0:
		return
	var origin: Vector2 = ctx.get("origin", Vector2.ZERO)
	var dir: Vector2 = ctx.get("direction", Vector2.DOWN)
	var at: Vector2 = origin + dir * EMITTER_FORWARD
	TerrainSurface.place_material(at, magnitude, mat)


func on_hit_target(_weapon: Weapon, _user: Node, target: Node) -> void:
	if trigger != "on_hit" or effect != "apply_status":
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc != null:
		sc.add_stain(element, magnitude)


func get_stat_add(stat: String) -> float:
	if effect == "stat_add" and element == stat:
		return magnitude
	return 0.0


func get_stat_mult(stat: String) -> float:
	if effect == "stat_mult" and element == stat:
		return magnitude
	if effect == "stat_add" and element == "damage" and stat == "cooldown" and magnitude2 > 0.0:
		return magnitude2
	return 1.0


func modify_crit_chance(_weapon: Weapon, base: float) -> float:
	if effect == "stat_add" and element == "crit_chance":
		return base + magnitude
	return base
