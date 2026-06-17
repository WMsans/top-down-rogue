extends GdUnitTestSuite

class _ExpireRecorder extends ProjectileBehavior:
	var expired: int = 0
	func on_expire(_proj) -> void:
		expired += 1

func test_base_on_expire_is_noop() -> void:
	var b: ProjectileBehavior = ProjectileBehavior.new()
	var p: Projectile = auto_free(Projectile.new())
	b.on_expire(p)  # must not error

func test_projectile_calls_on_expire_at_lifetime_end() -> void:
	var b := _ExpireRecorder.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.lifetime = 0.1
	p._process(0.2)  # age exceeds lifetime -> expire
	assert_int(b.expired).is_equal(1)

func test_projectile_does_not_expire_before_lifetime() -> void:
	var b := _ExpireRecorder.new()
	var p: Projectile = auto_free(Projectile.new())
	p.behaviors = [b]
	p.lifetime = 10.0
	p._process(0.1)
	assert_int(b.expired).is_equal(0)
