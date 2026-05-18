extends GdUnitTestSuite

const RegionPoint = preload("res://src/core/regions/region_point.gd")
const RegionDisc = preload("res://src/core/regions/region_disc.gd")
const RegionRing = preload("res://src/core/regions/region_ring.gd")
const RegionArc = preload("res://src/core/regions/region_arc.gd")

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	return r

func test_point_sample_is_offset() -> void:
	var p := RegionPoint.new()
	p.offset = Vector2(10, -5)
	assert_that(p.sample(_rng())).is_equal(Vector2(10, -5))

func test_disc_sample_within_radius() -> void:
	var d := RegionDisc.new()
	d.center = Vector2(0, 0)
	d.radius = 100.0
	var rng := _rng()
	for i in 64:
		var s: Vector2 = d.sample(rng)
		assert_that(s.length()).is_less_equal(100.0)

func test_ring_sample_in_annulus() -> void:
	var r := RegionRing.new()
	r.center = Vector2.ZERO
	r.r_min = 50.0
	r.r_max = 100.0
	var rng := _rng()
	for i in 64:
		var s: Vector2 = r.sample(rng)
		var d := s.length()
		assert_that(d).is_greater_equal(50.0)
		assert_that(d).is_less_equal(100.0)

func test_arc_sample_within_angle_span() -> void:
	var a := RegionArc.new()
	a.center = Vector2.ZERO
	a.angle = 0.0
	a.span = PI / 2.0       # 90°
	a.r_min = 100.0
	a.r_max = 200.0
	var rng := _rng()
	for i in 64:
		var s: Vector2 = a.sample(rng)
		var theta: float = atan2(s.y, s.x)
		# normalize theta into [-span/2, span/2]
		assert_that(theta).is_greater_equal(-a.span / 2.0 - 1e-3)
		assert_that(theta).is_less_equal(a.span / 2.0 + 1e-3)
		var d := s.length()
		assert_that(d).is_greater_equal(100.0)
		assert_that(d).is_less_equal(200.0)
