extends GdUnitTestSuite

const _Blood = preload("res://src/core/interactables/blood_altar.gd")
const _Mimic = preload("res://src/core/interactables/mimic_chest.gd")
const _Greed = preload("res://src/core/interactables/greed_vault.gd")
const _Trial = preload("res://src/core/interactables/trial_gauntlet.gd")

func test_shrines_have_title_and_icon_defaults() -> void:
	for script in [_Blood, _Mimic, _Greed, _Trial]:
		var shrine = script.new()
		auto_free(shrine)
		assert_str(shrine.title).is_not_empty()
		assert_object(shrine.icon).is_not_null()

func test_caves_wires_five_event_rooms_each_with_a_sign() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_object(biome).is_not_null()
	var event_count := 0
	for tmpl in biome.room_templates:
		var rt := tmpl as RoomTemplate
		if rt.composition == null:
			continue
		var comp := rt.composition as ArenaComposition
		if comp.arena_kind != &"event":
			continue
		event_count += 1
		var has_sign := false
		var has_payload := false
		for f in comp.features:
			if f is FeatureRoomSign:
				has_sign = true
			if f is FeatureInteractable or f is FeatureHazardFlood:
				has_payload = true
		assert_bool(has_sign).is_true()
		assert_bool(has_payload).is_true()
	assert_int(event_count).is_equal(5)

func test_reactor_has_hazard_and_chest() -> void:
	var comp: ArenaComposition = load("res://assets/arenas/event/caves_reactor_chamber.tres")
	assert_object(comp).is_not_null()
	var has_flood := false
	var has_chest := false
	for f in comp.features:
		if f is FeatureHazardFlood:
			has_flood = true
		if f is FeatureChestSpawn:
			has_chest = true
	assert_bool(has_flood).is_true()
	assert_bool(has_chest).is_true()

func test_interactable_feature_carries_shrine_script() -> void:
	var comp: ArenaComposition = load("res://assets/arenas/event/caves_blood_altar.tres")
	var feat_script: Script = null
	for f in comp.features:
		if f is FeatureInteractable:
			feat_script = f.shrine_script
	assert_object(feat_script).is_not_null()
