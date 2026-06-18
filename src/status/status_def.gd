class_name StatusDef
extends RefCounted

enum Category { HARMFUL, NEUTRAL, BENEFICIAL }
enum Mode { STAIN, TIMED }

var id: String
var display_name: String
var tint_color: Color
var decay_rate: float       # stain lost per second
var active_threshold: float # active once stain >= this
var category: int
var burn_dps: float         # > 0 means deals burn damage while active
var blocks_movement: bool   # true => immobile while active
var slow_multiplier: float  # movement speed multiplier while active (1.0 = none)
var icon_path: String       # res:// path to the above-head status icon (or "")
var mode: int = Mode.STAIN
var default_duration: float = 0.0


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
	p_icon_path: String = "",
	p_mode: int = Mode.STAIN,
	p_default_duration: float = 0.0
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
	icon_path = p_icon_path
	mode = p_mode
	default_duration = p_default_duration
