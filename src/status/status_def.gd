class_name StatusDef
extends RefCounted

enum Category { HARMFUL, NEUTRAL, BENEFICIAL }

var id: String
var display_name: String
var tint_color: Color
var decay_rate: float       # stain lost per second
var active_threshold: float # active once stain >= this
var category: int
var burn_dps: float         # > 0 means deals burn damage while active
var blocks_movement: bool   # true => immobile while active
var slow_multiplier: float  # movement speed multiplier while active (1.0 = none)


func _init(
	p_id: String,
	p_display_name: String,
	p_tint_color: Color,
	p_decay_rate: float,
	p_active_threshold: float,
	p_category: int = Category.NEUTRAL,
	p_burn_dps: float = 0.0,
	p_blocks_movement: bool = false,
	p_slow_multiplier: float = 1.0,
) -> void:
	id = p_id
	display_name = p_display_name
	tint_color = p_tint_color
	decay_rate = p_decay_rate
	active_threshold = p_active_threshold
	category = p_category
	burn_dps = p_burn_dps
	blocks_movement = p_blocks_movement
	slow_multiplier = p_slow_multiplier
