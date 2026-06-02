extends GdUnitTestSuite

const _FlickerLight = preload("res://src/core/flicker_light.gd")

func test_is_point_light() -> void:
	var f := _FlickerLight.new()
	assert_that(f is PointLight2D).is_true()

func test_ready_captures_base_energy() -> void:
	var f := _FlickerLight.new()
	f.energy = 1.2
	f.amplitude = 0.1
	var orig_energy := f.energy
	add_child(f)            # triggers _ready
	assert_that(f.base_energy).is_equal(orig_energy)

func test_flicker_stays_within_amplitude_bounds() -> void:
	var f := _FlickerLight.new()
	f.energy = 1.0
	f.amplitude = 0.1
	add_child(f)
	# Advance the flicker manually a few ticks; energy must stay within base +/- amplitude.
	for i in range(20):
		f._process(0.05)
		assert_that(f.energy >= 0.9 - 0.0001 and f.energy <= 1.1 + 0.0001).is_true()

func test_zero_amplitude_holds_steady_energy() -> void:
	var f := _FlickerLight.new()
	f.energy = 2.0
	f.amplitude = 0.0
	add_child(f)
	f._process(0.05)
	assert_that(f.energy).is_equal(2.0)
