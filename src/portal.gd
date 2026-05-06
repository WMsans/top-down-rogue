class_name Portal
extends Area2D

const PROMPT_TEXT := "Press [E] to enter portal"

@onready var _prompt_label: Label = $PromptLabel
@onready var _color_rect: ColorRect = $ColorRect


func _ready() -> void:
	modulate.a = 0.0
	var fow := get_tree().get_first_node_in_group("fog_of_war")
	if fow and fow is FogOfWar:
		fow.register(self)
	if _prompt_label:
		_prompt_label.text = PROMPT_TEXT
		_prompt_label.visible = false


func _exit_tree() -> void:
	var fow := get_tree().get_first_node_in_group("fog_of_war")
	if fow and fow is FogOfWar:
		fow.unregister(self)


func get_pickup_type() -> int:
	return Drop.PickupType.PORTAL


func get_pickup_payload():
	return null


func should_auto_pickup() -> bool:
	return false


func interact(_player: Node) -> void:
	LevelManager.advance_floor()
	queue_free()


func set_highlighted(enabled: bool) -> void:
	if _color_rect and _color_rect.material is ShaderMaterial:
		(_color_rect.material as ShaderMaterial).set_shader_parameter("outline_width", 1.0 if enabled else 0.0)
	if _prompt_label:
		_prompt_label.visible = enabled
