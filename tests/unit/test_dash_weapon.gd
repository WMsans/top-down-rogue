extends GdUnitTestSuite

const DashWeaponScript = preload("res://src/weapons/dash_weapon.gd")
const PlayerScript = preload("res://src/player/player_controller.gd")
const WeaponManagerScript = preload("res://src/weapons/weapon_manager.gd")


# Stand-in for the player: the weapon only needs a direction source, a dash sink
# and a PlayerInventory child.
class _DashUser extends Node2D:
	var move_dir: Vector2 = Vector2.ZERO
	var facing: Vector2 = Vector2.DOWN
	var dash_calls: Array = []
	var inventory: PlayerInventory

	func _init() -> void:
		inventory = PlayerInventory.new()
		inventory.name = "PlayerInventory"
		add_child(inventory)

	func get_move_direction() -> Vector2:
		return move_dir

	func get_facing_direction() -> Vector2:
		return facing

	func request_dash(direction: Vector2, speed: float) -> void:
		dash_calls.append([direction, speed])


func _user() -> _DashUser:
	var user: _DashUser = auto_free(_DashUser.new())
	add_child(user)
	return user


func _weapon() -> DashWeapon:
	var w: DashWeapon = auto_free(DashWeaponScript.new())
	return w


func test_use_dashes_in_held_move_direction() -> void:
	var user := _user()
	user.move_dir = Vector2.RIGHT
	_weapon().use(user)
	assert_int(user.dash_calls.size()).is_equal(1)
	assert_vector(user.dash_calls[0][0]).is_equal(Vector2.RIGHT)
	assert_float(user.dash_calls[0][1]).is_equal_approx(DashWeapon.DASH_SPEED, 0.01)


func test_use_falls_back_to_facing_when_standing_still() -> void:
	var user := _user()
	user.move_dir = Vector2.ZERO
	user.facing = Vector2.LEFT
	_weapon().use(user)
	assert_int(user.dash_calls.size()).is_equal(1)
	assert_vector(user.dash_calls[0][0]).is_equal(Vector2.LEFT)


func test_use_grants_invincibility() -> void:
	var user := _user()
	_weapon().use(user)
	assert_bool(user.inventory.is_invincible()).is_true()


func test_dash_invincibility_expires() -> void:
	var user := _user()
	_weapon().use(user)
	user.inventory._physics_process(DashWeapon.IFRAME_DURATION + 0.01)
	assert_bool(user.inventory.is_invincible()).is_false()


func test_dash_takes_no_modifier_slots() -> void:
	var w := _weapon()
	assert_int(w.modifier_slot_count).is_equal(0)
	assert_int(w.find_empty_modifier_slot()).is_equal(-1)


func test_default_loadout_equips_dash_in_third_slot() -> void:
	var player: Node2D = auto_free(Node2D.new())
	add_child(player)
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	inv.name = "PlayerInventory"
	player.add_child(inv)
	var manager: WeaponManager = auto_free(WeaponManagerScript.new())
	player.add_child(manager)
	await get_tree().process_frame
	assert_bool(inv.get_weapon(2) is DashWeapon).is_true()


func test_player_move_direction_follows_input() -> void:
	var p: PlayerController = auto_free(PlayerScript.new())
	Input.action_press("move_right")
	var dir := p.get_move_direction()
	Input.action_release("move_right")
	assert_vector(dir).is_equal(Vector2.RIGHT)


func test_player_move_direction_is_zero_without_input() -> void:
	var p: PlayerController = auto_free(PlayerScript.new())
	assert_vector(p.get_move_direction()).is_equal(Vector2.ZERO)
