extends Node

# Data-only registry: status definitions, reaction rules, and material->status
# mapping. Shared by every StatusComponent. Adding a status = one entry here.

const StatusDefScript = preload("res://src/status/status_def.gd")

# Terrain top-up: stain added per second while standing in a source material.
const TERRAIN_STAIN_RATE := 6.0

# Above-head icon intensity mapping: alpha ramps from ICON_MIN_ALPHA (at the
# active threshold) to 1.0 once stain reaches threshold + ICON_ALPHA_RAMP.
const ICON_MIN_ALPHA := 0.15
const ICON_ALPHA_RAMP := 4.0

var _defs: Dictionary = {}  # id -> StatusDef
var _icon_cache: Dictionary = {}  # id -> Texture2D (lazy)


func _ready() -> void:
	_register_defs()


func _register_defs() -> void:
	_add(StatusDefScript.new(
		"on_fire", "On Fire", Color(1.0, 0.45, 0.1, 1.0),
		1.0, 1.0, StatusDef.Category.HARMFUL, 4.0, false, 1.0,
		"res://textures/ui/status/Effect_on_fire.png"))
	_add(StatusDefScript.new(
		"wet", "Wet", Color(0.35, 0.55, 0.95, 1.0),
		0.5, 1.0, StatusDef.Category.NEUTRAL, 0.0, false, 1.0,
		"res://textures/ui/status/Effect_wet.png"))
	_add(StatusDefScript.new(
		"oiled", "Oiled", Color(0.25, 0.18, 0.1, 1.0),
		0.3, 1.0, StatusDef.Category.NEUTRAL, 0.0, false, 1.0,
		"res://textures/ui/status/Effect_oiled.png"))
	_add(StatusDefScript.new(
		"chilly", "Chilly", Color(0.6, 0.8, 0.95, 1.0),
		0.8, 1.0, StatusDef.Category.HARMFUL, 0.0, false, 0.6,
		"res://textures/ui/status/Effect_ingestion_freezing.png"))
	_add(StatusDefScript.new(
		"frozen", "Frozen", Color(0.7, 0.9, 1.0, 1.0),
		0.4, 3.0, StatusDef.Category.HARMFUL, 0.0, true, 0.0,
		"res://textures/ui/status/Effect_frozen.png"))
	_add(StatusDefScript.new(
		"bloody", "Bloody", Color(0.75, 0.08, 0.08, 1.0),
		0.4, 1.0, StatusDef.Category.NEUTRAL, 0.0, false, 1.0,
		"res://textures/ui/status/Effect_bloody.png"))
	_add(StatusDefScript.new(
		"poisoned", "Poisoned", Color(0.3, 0.85, 0.25, 1.0),
		0.4, 0.3, StatusDef.Category.HARMFUL, 2.0, false, 0.6,
		"res://textures/ui/status/Effect_poisoned.png"))


func _add(def: StatusDef) -> void:
	_defs[def.id] = def


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> StatusDef:
	return _defs.get(id, null)


func get_threshold(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.active_threshold if d != null else 1.0


func get_decay_rate(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.decay_rate if d != null else 1.0


func get_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var d: StatusDef = _defs.get(id, null)
	var tex: Texture2D = null
	if d != null and d.icon_path != "":
		tex = load(d.icon_path) as Texture2D
	_icon_cache[id] = tex
	return tex


func get_icon_alpha(id: String, stain: float) -> float:
	var threshold := get_threshold(id)
	if stain < threshold:
		return 0.0
	var t: float = clampf((stain - threshold) / ICON_ALPHA_RAMP, 0.0, 1.0)
	return lerpf(ICON_MIN_ALPHA, 1.0, t)


func get_tint(id: String) -> Color:
	var d: StatusDef = _defs.get(id, null)
	return d.tint_color if d != null else Color(1, 1, 1, 1)


func get_burn_dps(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.burn_dps if d != null else 0.0


func blocks_movement(id: String) -> bool:
	var d: StatusDef = _defs.get(id, null)
	return d.blocks_movement if d != null else false


func get_slow_multiplier(id: String) -> float:
	var d: StatusDef = _defs.get(id, null)
	return d.slow_multiplier if d != null else 1.0


func stain_for_material(material_id: int) -> String:
	if material_id == MaterialRegistry.MAT_LAVA or material_id == MaterialRegistry.MAT_EXPLODE_WAVE:
		return "on_fire"
	if material_id == MaterialRegistry.MAT_WATER:
		return "wet"
	if material_id == MaterialRegistry.MAT_OIL:
		return "oiled"
	if material_id == MaterialRegistry.MAT_BLOOD:
		return "bloody"
	if material_id == MaterialRegistry.MAT_GAS:
		return "poisoned"
	return ""


# --- Reaction tuning constants ---
const WET_EXTINGUISH_RATE := 4.0   # fire stain drained/sec while wet
const WET_EVAP_BONUS := 1.0        # extra wet evaporation/sec while extinguishing
const BLOODY_DAMPEN_RATE := 1.5    # fire stain drained/sec while bloody
const OIL_FEED_RATE := 2.0         # oiled stain consumed/sec while burning
const OIL_FIRE_GAIN := 1.5         # fire gained per oiled consumed
const WET_FREEZE_RATE := 2.0       # wet+chilly converted to frozen/sec
const FIRE_MELT_RATE := 3.0        # chilly/frozen drained/sec while on fire
const CHILLY_FREEZE_THRESHOLD := 4.0
const CHILLY_RAMP_RATE := 1.0      # chilly->frozen conversion/sec past threshold


func apply_reactions(c: StatusComponent, delta: float) -> void:
	# 1. Wet extinguishes Fire.
	if c.get_stain("wet") > 0.0 and c.get_stain("on_fire") > 0.0:
		c.reduce_stain("on_fire", WET_EXTINGUISH_RATE * delta)
		c.reduce_stain("wet", WET_EVAP_BONUS * delta)
	# 2. Bloody dampens Fire (weaker than wet).
	if c.get_stain("bloody") > 0.0 and c.get_stain("on_fire") > 0.0:
		c.reduce_stain("on_fire", BLOODY_DAMPEN_RATE * delta)
	# 3. Oiled feeds Fire (only when not wet).
	if c.get_stain("oiled") > 0.0 and c.get_stain("on_fire") > 0.0 and c.get_stain("wet") <= 0.0:
		var conv: float = OIL_FEED_RATE * delta
		c.reduce_stain("oiled", conv)
		c.add_stain("on_fire", conv * OIL_FIRE_GAIN)
	# 4. Wet + Chilly -> Frozen.
	if c.get_stain("wet") > 0.0 and c.get_stain("chilly") > 0.0:
		var fconv: float = minf(minf(c.get_stain("wet"), c.get_stain("chilly")), WET_FREEZE_RATE * delta)
		if fconv > 0.0:
			c.reduce_stain("wet", fconv)
			c.reduce_stain("chilly", fconv)
			c.add_stain("frozen", fconv)
	# 5. Fire melts cold.
	if c.get_stain("on_fire") > 0.0:
		c.reduce_stain("chilly", FIRE_MELT_RATE * delta)
		c.reduce_stain("frozen", FIRE_MELT_RATE * delta)
	# 6. Sustained Chilly ramps into Frozen.
	if c.get_stain("chilly") >= CHILLY_FREEZE_THRESHOLD:
		var rconv: float = CHILLY_RAMP_RATE * delta
		c.reduce_stain("chilly", rconv)
		c.add_stain("frozen", rconv)
