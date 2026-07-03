extends GdUnitTestSuite

const CARD_SCENE := preload("res://scenes/ui/card.tscn")


func _make_card() -> Card:
	var card: Card = CARD_SCENE.instantiate()
	add_child(card)
	return card


func test_stat_label_autowraps() -> void:
	var card := _make_card()
	var long_desc := "Arcs to a nearby foe on hit, chaining lightning between clustered enemies and applying a shock stain."
	card.populate(null, "Chain Spark", [long_desc])
	var stats_container: VBoxContainer = card.get_node(
		"SubViewportContainer/SubViewport/CardPanel/ContentVBox/StatsContainer")
	assert_that(stats_container.get_child_count()).is_equal(1)
	var label := stats_container.get_child(0) as Label
	assert_that(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_that(label.custom_minimum_size.x > 0.0).is_true()
	assert_that(label.custom_minimum_size.x < card.card_size.x).is_true()
	card.queue_free()
