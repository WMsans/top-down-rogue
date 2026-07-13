extends Node
## Saltmire FX — one-line 2D sprite shader effects for Godot 4.
## Dissolve, appear, outline, hit-flash, freeze, hologram — drop-in, no setup.
## Autoloaded as `FX`. MIT licensed. https://saltmire.itch.io
##
## Quick use:
##   FX.dissolve($Sprite2D)            # burn away with glowing edge
##   FX.appear($Sprite2D)              # reverse dissolve (materialize)
##   FX.hit_flash($Sprite2D)           # white damage flash
##   FX.outline($Sprite2D, Color.YELLOW, 2.0)
##   FX.freeze($Sprite2D)              # icy tint
##   FX.hologram($Sprite2D)            # animated sci-fi look
##   FX.clear($Sprite2D)               # remove any FX material
##
## Each call assigns a ShaderMaterial to the target's `material`. Effects are
## applied one at a time (the last one wins). `clear()` restores the default.

const DISSOLVE := preload("res://addons/saltmire_fx/shaders/dissolve.gdshader")
const OUTLINE := preload("res://addons/saltmire_fx/shaders/outline.gdshader")
const HIT_FLASH := preload("res://addons/saltmire_fx/shaders/hit_flash.gdshader")
const FREEZE := preload("res://addons/saltmire_fx/shaders/freeze.gdshader")
const HOLOGRAM := preload("res://addons/saltmire_fx/shaders/hologram.gdshader")

# ---------------------------------------------------------------------------
# Internal: get (or make) a ShaderMaterial for `target` using `shader`.
# ---------------------------------------------------------------------------
func _mat(target: CanvasItem, shader: Shader) -> ShaderMaterial:
	var m := target.material as ShaderMaterial
	if m == null or m.shader != shader:
		m = ShaderMaterial.new()
		m.shader = shader
		target.material = m
	return m

# ---------------------------------------------------------------------------
# Dissolve — burn the sprite away. progress 0 -> 1. Returns the Tween.
# ---------------------------------------------------------------------------
func dissolve(target: CanvasItem, duration: float = 0.5,
		edge_color: Color = Color(1.0, 0.6, 0.15)) -> Tween:
	if target == null:
		return null
	var m := _mat(target, DISSOLVE)
	m.set_shader_parameter("edge_color", edge_color)
	m.set_shader_parameter("progress", 0.0)
	var t := target.create_tween()
	t.tween_method(func(v): m.set_shader_parameter("progress", v), 0.0, 1.0, duration)
	return t

# ---------------------------------------------------------------------------
# Appear — reverse dissolve (materialize in). progress 1 -> 0.
# ---------------------------------------------------------------------------
func appear(target: CanvasItem, duration: float = 0.5,
		edge_color: Color = Color(1.0, 0.6, 0.15)) -> Tween:
	if target == null:
		return null
	var m := _mat(target, DISSOLVE)
	m.set_shader_parameter("edge_color", edge_color)
	m.set_shader_parameter("progress", 1.0)
	var t := target.create_tween()
	t.tween_method(func(v): m.set_shader_parameter("progress", v), 1.0, 0.0, duration)
	return t

# ---------------------------------------------------------------------------
# Hit flash — blend toward a color then fade back. amount 1 -> 0.
# ---------------------------------------------------------------------------
func hit_flash(target: CanvasItem, color: Color = Color.WHITE,
		duration: float = 0.15) -> Tween:
	if target == null:
		return null
	var m := _mat(target, HIT_FLASH)
	m.set_shader_parameter("flash_color", color)
	m.set_shader_parameter("amount", 1.0)
	var t := target.create_tween()
	t.tween_method(func(v): m.set_shader_parameter("amount", v), 1.0, 0.0, duration)
	return t

# ---------------------------------------------------------------------------
# Outline — persistent border. Call clear() to remove.
# ---------------------------------------------------------------------------
func outline(target: CanvasItem, color: Color = Color.WHITE,
		width: float = 1.0) -> void:
	if target == null:
		return
	var m := _mat(target, OUTLINE)
	m.set_shader_parameter("outline_color", color)
	m.set_shader_parameter("outline_width", width)

# ---------------------------------------------------------------------------
# Freeze — icy tint. amount 0 -> `to`. Persistent (tween in).
# ---------------------------------------------------------------------------
func freeze(target: CanvasItem, to: float = 1.0, duration: float = 0.2,
		ice_color: Color = Color(0.6, 0.85, 1.0)) -> Tween:
	if target == null:
		return null
	var m := _mat(target, FREEZE)
	m.set_shader_parameter("ice_color", ice_color)
	m.set_shader_parameter("amount", 0.0)
	var t := target.create_tween()
	t.tween_method(func(v): m.set_shader_parameter("amount", v), 0.0, to, duration)
	return t

# ---------------------------------------------------------------------------
# Hologram — animated sci-fi look. Persistent; amount controls strength.
# ---------------------------------------------------------------------------
func hologram(target: CanvasItem, amount: float = 1.0,
		holo_color: Color = Color(0.4, 0.8, 1.0)) -> void:
	if target == null:
		return
	var m := _mat(target, HOLOGRAM)
	m.set_shader_parameter("holo_color", holo_color)
	m.set_shader_parameter("amount", amount)

# ---------------------------------------------------------------------------
# Clear — remove any Saltmire FX material from the target.
# ---------------------------------------------------------------------------
func clear(target: CanvasItem) -> void:
	if target == null:
		return
	if target.material is ShaderMaterial:
		var s := (target.material as ShaderMaterial).shader
		if s == DISSOLVE or s == OUTLINE or s == HIT_FLASH or s == FREEZE or s == HOLOGRAM:
			target.material = null
