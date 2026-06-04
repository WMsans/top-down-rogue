extends GdUnitTestSuite

const CsvTable = preload("res://src/util/csv_table.gd")

func test_parses_rows_keyed_by_header() -> void:
	var rows := CsvTable.parse("res://tests/fixtures/csv_sample.csv")
	assert_that(rows.size()).is_equal(2)
	assert_that(rows[0]["id"]).is_equal("alpha")
	assert_that(rows[0]["name"]).is_equal("Alpha")
	assert_that(rows[0]["extra"]).is_equal("x")

func test_handles_quoted_comma_and_blank_cell() -> void:
	var rows := CsvTable.parse("res://tests/fixtures/csv_sample.csv")
	assert_that(rows[1]["note"]).is_equal("a note, with comma")
	assert_that(rows[1]["extra"]).is_equal("")

func test_missing_file_returns_empty() -> void:
	var rows := CsvTable.parse("res://tests/fixtures/does_not_exist.csv")
	assert_that(rows.size()).is_equal(0)
