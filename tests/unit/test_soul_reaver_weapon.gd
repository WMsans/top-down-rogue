extends GdUnitTestSuite

const SoulReaver = preload("res://src/weapons/soul_reaver_weapon.gd")

func test_kill_raises_effective_dig_power_by_one_stack() -> void:
	var w := SoulReaver.new()
	w.dig_power = 5.0
	var base: float = w.get_effective_stats()["dig_power"]
	w._native_on_kill(null, null)
	assert_float(w.get_effective_stats()["dig_power"]).is_equal_approx(base + SoulReaver.STACK_GAIN, 0.001)

func test_stacks_cap() -> void:
	var w := SoulReaver.new()
	w.dig_power = 5.0
	for i in range(100):
		w._native_on_kill(null, null)
	assert_float(w.get_effective_stats()["dig_power"]).is_equal_approx(5.0 + SoulReaver.STACK_CAP, 0.001)

func test_decay_after_delay_reduces_stacks() -> void:
	var w := SoulReaver.new()
	w.dig_power = 5.0
	w._native_on_kill(null, null)
	w._native_on_kill(null, null)            # 2 stacks * gain
	var before: float = w.get_effective_stats()["dig_power"]
	w._tick_impl(SoulReaver.DECAY_DELAY + 0.01)   # cross the decay threshold (drops one step)
	assert_float(w.get_effective_stats()["dig_power"]).is_less(before)
