extends GdUnitTestSuite

const SHOP_STALL := preload("res://scenes/economy/shop_stall.tscn")

func _spawn_stall() -> ShopStall:
	var stall: ShopStall = SHOP_STALL.instantiate()
	add_child(stall)
	auto_free(stall)
	return stall

func test_stall_spawns_5_modifiers_3_weapons_1_removal() -> void:
	var stall := _spawn_stall()
	var mods := 0
	var wpns := 0
	var rems := 0
	for c in stall.get_children():
		if c is ShopModifierDrop:
			mods += 1
		elif c is ShopWeaponDrop:
			wpns += 1
		elif c is ShopRemoval:
			rems += 1
	assert_int(mods).is_equal(5)
	assert_int(wpns).is_equal(3)
	assert_int(rems).is_equal(1)

func test_modifiers_use_back_row_offsets() -> void:
	var stall := _spawn_stall()
	var xs: Array[float] = []
	for c in stall.get_children():
		if c is ShopModifierDrop:
			assert_float((c as Node2D).position.y).is_equal(ShopStall.MODIFIER_Y)
			xs.append((c as Node2D).position.x)
	assert_array(xs).contains_exactly(ShopStall.MODIFIER_XS)

func test_removal_in_bottom_right() -> void:
	var stall := _spawn_stall()
	for c in stall.get_children():
		if c is ShopRemoval:
			assert_vector((c as Node2D).position).is_equal(ShopStall.REMOVAL_OFFSET)
