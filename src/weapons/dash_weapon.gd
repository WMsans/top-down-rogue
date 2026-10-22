class_name DashWeapon
extends Weapon

# request_dash() decays at PlayerController.DASH_DECAY (9/s), so the distance
# travelled is DASH_SPEED / 9 ≈ 90 px, most of it in the first 0.15 s.
const DASH_SPEED := 510.0
const IFRAME_DURATION := 0.25


func _init() -> void:
	name = "Dash"
	description = "Dash in the direction you move, briefly invincible. Takes no modifiers."
	cooldown = 1.0
	dig_power = 0.0
	modifier_slot_count = 0
	rarity = DropTable.ItemTier.COMMON


func _use_impl(user: Node) -> void:
	var direction: Vector2 = Vector2.ZERO
	if user.has_method("get_move_direction"):
		direction = user.get_move_direction()
	if direction == Vector2.ZERO and user.has_method("get_facing_direction"):
		direction = user.get_facing_direction()
	if user.has_method("request_dash"):
		user.request_dash(direction, DASH_SPEED)
	var inventory := user.get_node_or_null("PlayerInventory")
	if inventory != null:
		inventory.grant_invincibility(IFRAME_DURATION)
