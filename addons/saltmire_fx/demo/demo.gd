extends Node2D
## Self-playing showcase: cycles through every Saltmire FX effect on a sprite.
## Click or press Space to jump to the next effect.

@onready var sprite: Sprite2D = $Sprite
@onready var label: Label = $UI/Effect
var _i := 0
var _skip := false

const EFFECTS := ["HIT FLASH", "DISSOLVE / APPEAR", "OUTLINE", "FREEZE", "HOLOGRAM"]


func _ready() -> void:
	_loop()


func _loop() -> void:
	while true:
		var name: String = EFFECTS[_i % EFFECTS.size()]
		label.text = name
		FX.clear(sprite)
		await _pause(0.4)
		match name:
			"HIT FLASH":
				for n in 3:
					await FX.hit_flash(sprite, Color.WHITE, 0.14).finished
					await _pause(0.12)
			"DISSOLVE / APPEAR":
				await FX.dissolve(sprite, 0.8).finished
				await _pause(0.2)
				await FX.appear(sprite, 0.8).finished
			"OUTLINE":
				FX.outline(sprite, Color(1.0, 0.9, 0.2), 2.0)
				await _pause(1.4)
			"FREEZE":
				await FX.freeze(sprite, 1.0, 0.4).finished
				await _pause(0.8)
				await FX.freeze(sprite, 0.0, 0.4).finished
			"HOLOGRAM":
				FX.hologram(sprite, 1.0)
				await _pause(1.6)
		await _pause(0.5)
		_i += 1


func _pause(seconds: float) -> void:
	# a pause that can be cut short by user input
	var t := 0.0
	while t < seconds and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
	_skip = false


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_skip = true
