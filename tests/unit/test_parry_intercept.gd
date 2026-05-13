extends GdUnitTestSuite

func test_try_parry_returns_false_when_no_weapon() -> void:
	var player: PlayerController = auto_free(PlayerController.new())
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	inv.name = "PlayerInventory"
	player.add_child(inv)
	var attacker: Node2D = auto_free(Node2D.new())
	assert_that(player.try_parry(attacker, Vector2.ZERO, Vector2.RIGHT)).is_false()

func test_try_parry_succeeds_in_window() -> void:
	var player: PlayerController = auto_free(PlayerController.new())
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	inv.name = "PlayerInventory"
	player.add_child(inv)
	var container := Node2D.new()
	container.name = "WeaponVisual"
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	container.add_child(sprite)
	player.add_child(container)
	var w := MeleeWeapon.new()
	inv.equip_weapon(inv.active_weapon_slot, w)
	w.setup_visual(container, sprite)
	w._is_swinging = true
	w._swing_elapsed = 0.0
	var attacker: Enemy = auto_free(Enemy.new())
	var enemy_weapon := MeleeWeapon.new()
	enemy_weapon.parryable = true
	attacker.weapon = enemy_weapon
	var parried := player.try_parry(attacker, player.global_position, Vector2.RIGHT)
	assert_that(parried).is_true()

func test_try_parry_fails_for_unparryable_attacker() -> void:
	var player: PlayerController = auto_free(PlayerController.new())
	var inv: PlayerInventory = auto_free(PlayerInventory.new())
	inv.name = "PlayerInventory"
	player.add_child(inv)
	var container := Node2D.new()
	container.name = "WeaponVisual"
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	container.add_child(sprite)
	player.add_child(container)
	var w := MeleeWeapon.new()
	inv.equip_weapon(inv.active_weapon_slot, w)
	w.setup_visual(container, sprite)
	w._is_swinging = true
	w._swing_elapsed = 0.0
	var attacker: Enemy = auto_free(Enemy.new())
	var enemy_weapon := MeleeWeapon.new()
	enemy_weapon.parryable = false
	attacker.weapon = enemy_weapon
	var parried := player.try_parry(attacker, player.global_position, Vector2.RIGHT)
	assert_that(parried).is_false()
