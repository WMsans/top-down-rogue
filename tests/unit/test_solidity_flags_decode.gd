extends GdUnitTestSuite

const SIM_FLAG_SLOT_BYTES := 4

func _make_buffer(slot_count: int, flagged_slots: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(slot_count * SIM_FLAG_SLOT_BYTES)
	buf.fill(0)
	for slot in flagged_slots:
		buf.encode_u32(slot * SIM_FLAG_SLOT_BYTES, 1)
	return buf

func _manifest(triples: Array) -> PackedInt32Array:
	var m := PackedInt32Array()
	for t in triples:
		m.append(t[0]); m.append(t[1]); m.append(t[2])
	return m

func _loaded(coords: Array) -> Dictionary:
	var d: Dictionary = {}
	for c in coords:
		d[c] = true
	return d

func test_empty_manifest_returns_empty() -> void:
	var device := ComputeDevice.new()
	var out := device.decode_solidity_flags(PackedByteArray(), PackedInt32Array(), {})
	assert_that(out.size()).is_equal(0)

func test_only_flagged_slots_returned() -> void:
	var device := ComputeDevice.new()
	var manifest := _manifest([[1, 2, 0], [3, 4, 1], [5, 6, 2]])
	var data := _make_buffer(3, [0, 2])
	var loaded := _loaded([Vector2i(1, 2), Vector2i(3, 4), Vector2i(5, 6)])
	var out := device.decode_solidity_flags(data, manifest, loaded)
	assert_that(out).contains_exactly_in_any_order([Vector2i(1, 2), Vector2i(5, 6)])

func test_unloaded_coords_filtered_out() -> void:
	var device := ComputeDevice.new()
	var manifest := _manifest([[1, 2, 0], [3, 4, 1]])
	var data := _make_buffer(2, [0, 1])
	var loaded := _loaded([Vector2i(1, 2)])
	var out := device.decode_solidity_flags(data, manifest, loaded)
	assert_that(out).contains_exactly_in_any_order([Vector2i(1, 2)])

func test_slot_beyond_buffer_is_skipped() -> void:
	var device := ComputeDevice.new()
	var manifest := _manifest([[7, 8, 5]])
	var data := _make_buffer(1, [0])
	var loaded := _loaded([Vector2i(7, 8)])
	var out := device.decode_solidity_flags(data, manifest, loaded)
	assert_that(out.size()).is_equal(0)
