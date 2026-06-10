extends GdUnitTestSuite

const PASS_SLOT_U32 := 1024
const PASS_SLOT_BYTES := 4096

func _buffer(slot_count: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(slot_count * PASS_SLOT_BYTES)
	b.fill(0)
	return b

func test_decodes_solid_cell_in_slot() -> void:
	var device := ComputeDevice.new()
	var data := _buffer(3)
	# slot 2, cell index 33 (cell (1,1)) marked solid
	data.encode_u32(2 * PASS_SLOT_BYTES + 33 * 4, 1)
	var tile := device.decode_passability_slice(data, 2)
	assert_that(tile.size()).is_equal(PASS_SLOT_U32)
	assert_that(tile[33]).is_equal(1)
	assert_that(tile[0]).is_equal(0)

func test_slot_beyond_buffer_returns_zero_tile() -> void:
	var device := ComputeDevice.new()
	var data := _buffer(1)
	var tile := device.decode_passability_slice(data, 5)
	assert_that(tile.size()).is_equal(PASS_SLOT_U32)
	assert_that(tile[0]).is_equal(0)
