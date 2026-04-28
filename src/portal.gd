class_name Portal
extends Area2D

const PROMPT_TEXT := "Press [E] to enter portal"

var _player_inside: bool = false
@onready var _prompt_label: Label = $PromptLabel


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if _prompt_label:
		_prompt_label.text = PROMPT_TEXT
		_prompt_label.visible = false


func _process(_delta: float) -> void:
	if _player_inside and Input.is_action_just_pressed("interact"):
		LevelManager.advance_floor()
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if _prompt_label:
			_prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		if _prompt_label:
			_prompt_label.visible = false
