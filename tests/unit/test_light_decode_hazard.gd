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


func _make_coalesced_buffer(hazards_per_slice: Array) -> PackedByteArray:
	var slice_count := hazards_per_slice.size()
	var buf := PackedByteArray()
	buf.resize(slice_count * LIGHT_OUTPUT_SIZE)
	buf.fill(0)
	for s in range(slice_count):
		var slice_off := s * LIGHT_OUTPUT_SIZE
		var hazards: Array = hazards_per_slice[s]
		for i in range(LIGHT_CELL_COUNT):
			var off := slice_off + i * LIGHT_CELL_BYTES
			buf.encode_u32(off + 8, hazards[i])
	return buf


func test_slice_decoder_extracts_hazard_mask_for_slice() -> void:
	var device := ComputeDevice.new()
	var slice0: Array = []
	var slice1: Array = []
	slice0.resize(LIGHT_CELL_COUNT)
	slice1.resize(LIGHT_CELL_COUNT)
	for i in range(LIGHT_CELL_COUNT):
		slice0[i] = 0
		slice1[i] = 0
	slice0[3] = MaterialRegistry.HAZARD_LAVA
	slice1[7] = MaterialRegistry.HAZARD_FIRE
	var data := _make_coalesced_buffer([slice0, slice1])

	var decoded0 := device.decode_light_ssbo_slice(data, 0)
	var decoded1 := device.decode_light_ssbo_slice(data, 1)
	assert_that(decoded0.size()).is_equal(LIGHT_CELL_COUNT)
	assert_that(decoded1.size()).is_equal(LIGHT_CELL_COUNT)
	assert_that(int(decoded0[3]["hazard"])).is_equal(MaterialRegistry.HAZARD_LAVA)
	assert_that(int(decoded1[7]["hazard"])).is_equal(MaterialRegistry.HAZARD_FIRE)
	assert_that(int(decoded0[7]["hazard"])).is_equal(0)
