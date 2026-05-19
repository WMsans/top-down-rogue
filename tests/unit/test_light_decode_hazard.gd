extends GdUnitTestSuite

const LIGHT_CELL_COUNT := 16
const LIGHT_CELL_BYTES := 12
const LIGHT_OUTPUT_SIZE := LIGHT_CELL_COUNT * LIGHT_CELL_BYTES

func _make_buffer(hazard_per_cell: Array[int]) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(LIGHT_OUTPUT_SIZE)
	buf.fill(0)
	for i in range(LIGHT_CELL_COUNT):
		var off := i * LIGHT_CELL_BYTES
		buf.encode_u32(off + 8, hazard_per_cell[i])
	return buf

func test_decoder_extracts_hazard_mask() -> void:
	var device := ComputeDevice.new()
	var hazards: Array[int] = []
	hazards.resize(LIGHT_CELL_COUNT)
	for i in range(LIGHT_CELL_COUNT):
		hazards[i] = 0
	hazards[0] = MaterialRegistry.HAZARD_LAVA
	hazards[5] = MaterialRegistry.HAZARD_FIRE | MaterialRegistry.HAZARD_OIL
	var data := _make_buffer(hazards)
	var decoded := device.decode_light_ssbo(data)
	assert_that(decoded.size()).is_equal(LIGHT_CELL_COUNT)
	assert_that(int(decoded[0]["hazard"])).is_equal(MaterialRegistry.HAZARD_LAVA)
	assert_that(int(decoded[5]["hazard"])).is_equal(MaterialRegistry.HAZARD_FIRE | MaterialRegistry.HAZARD_OIL)
	assert_that(int(decoded[1]["hazard"])).is_equal(0)
