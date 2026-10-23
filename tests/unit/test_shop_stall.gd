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

func test_weapons_and_removal_share_the_front_row() -> void:
	var stall := _spawn_stall()
	var xs: Array[float] = []
	for c in stall.get_children():
		if c is ShopWeaponDrop:
			assert_float((c as Node2D).position.y).is_equal(ShopStall.FRONT_ROW_Y)
			xs.append((c as Node2D).position.x)
		elif c is ShopRemoval:
			assert_vector((c as Node2D).position).is_equal(ShopStall.REMOVAL_OFFSET)
	assert_float(ShopStall.REMOVAL_OFFSET.y).is_equal(ShopStall.FRONT_ROW_Y)
	assert_array(xs).contains_exactly(ShopStall.WEAPON_XS)

func test_every_item_sits_on_a_table() -> void:
	var stall := _spawn_stall()
	var tables := stall.get_node("Tables")
	assert_int(tables.get_child_count()).is_equal(9)

func test_stall_has_merchant_and_counter() -> void:
	var stall := _spawn_stall()
	assert_object(stall.get_node_or_null("Merchant")).is_not_null()
	assert_object(stall.get_node_or_null("Counter")).is_not_null()

func test_stall_fits_inside_compact_footprint() -> void:
	# Everything must fit well inside the 128px clearing carved by the template.
	var stall := _spawn_stall()
	for c in stall.get_children():
		if c is Node2D:
			var p := (c as Node2D).position
			assert_bool(absf(p.x) <= 50.0 and absf(p.y) <= 45.0) \
				.override_failure_message("%s at %s is outside the footprint" % [c.name, p]) \
				.is_true()

func test_shop_items_do_not_get_knocked_around() -> void:
	var stall := _spawn_stall()
	for c in stall.get_children():
		if c is Drop:
			assert_bool((c as RigidBody2D).freeze).is_true()
