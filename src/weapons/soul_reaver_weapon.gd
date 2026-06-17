class_name SoulReaverWeapon
extends MeleeWeapon

const STACK_GAIN := 0.5
const STACK_CAP := 8.0
const DECAY_DELAY := 3.0
const DECAY_STEP := 1.0

var _kill_stacks: float = 0.0
var _decay_timer: float = 0.0

func _init() -> void:
	super._init()
	weapon_reach = 34.0
	arc_angle = deg_to_rad(100.0)

func _seed_effective_stats() -> Dictionary:
	var s := super._seed_effective_stats()
	s["damage"] += _kill_stacks
	return s

func _native_on_kill(_user: Node, _target: Node) -> void:
	_kill_stacks = minf(_kill_stacks + STACK_GAIN, STACK_CAP)
	_decay_timer = 0.0
	invalidate_effective_stats()

func _tick_impl(delta: float) -> void:
	super._tick_impl(delta)
	if _kill_stacks <= 0.0:
		return
	_decay_timer += delta
	if _decay_timer >= DECAY_DELAY:
		_kill_stacks = maxf(0.0, _kill_stacks - DECAY_STEP)
		_decay_timer = 0.0
		invalidate_effective_stats()
