extends GdUnitTestSuite

const SoulReaver = preload("res://src/weapons/soul_reaver_weapon.gd")

func test_kill_raises_effective_damage_by_one_stack() -> void:
	var w := SoulReaver.new()
	w.damage = 5.0
	var base: float = w.get_effective_stats()["damage"]
	w._native_on_kill(null, null)
	assert_float(w.get_effective_stats()["damage"]).is_equal_approx(base + SoulReaver.STACK_GAIN, 0.001)

func test_stacks_cap() -> void:
	var w := SoulReaver.new()
	w.damage = 5.0
	for i in range(100):
		w._native_on_kill(null, null)
	assert_float(w.get_effective_stats()["damage"]).is_equal_approx(5.0 + SoulReaver.STACK_CAP, 0.001)

func test_decay_after_delay_reduces_stacks() -> void:
	var w := SoulReaver.new()
	w.damage = 5.0
	w._native_on_kill(null, null)
	w._native_on_kill(null, null)            # 2 stacks * gain
	var before: float = w.get_effective_stats()["damage"]
	w._tick_impl(SoulReaver.DECAY_DELAY + 0.01)   # cross the decay threshold (drops one step)
	assert_float(w.get_effective_stats()["damage"]).is_less(before)
