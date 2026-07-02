extends GdUnitTestSuite

const CsvTable = preload("res://src/util/csv_table.gd")

func test_gas_emitter_radius_capped_at_16() -> void:
	var rows := CsvTable.parse("res://docs/design_docs/modifiers.csv")
	var magnitude := ""
	for row in rows:
		if row.get("id", "") == "gas_emitter":
			magnitude = row.get("magnitude", "")
			break
	assert_that(magnitude).is_not_empty()
	assert_that(magnitude).is_equal("16")
