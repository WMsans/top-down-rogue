class_name CsvTable
extends RefCounted

# Parses a CSV file into an Array of Dictionaries keyed by the header row.
# Uses FileAccess.get_csv_line() so quoted fields containing commas parse
# correctly. Blank lines are skipped. Missing file -> empty array + warning.
static func parse(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		push_warning("CsvTable: file not found: %s" % path)
		return rows
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CsvTable: could not open: %s" % path)
		return rows
	var headers: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and values[0] == "":
			continue
		var row: Dictionary = {}
		for i in range(headers.size()):
			row[headers[i]] = values[i] if i < values.size() else ""
		rows.append(row)
	return rows
