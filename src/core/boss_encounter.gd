class_name BossEncounter
extends Node

const BOSS_HUD_SCENE := preload("res://scenes/ui/boss_hud.tscn")
const PORTAL_SCENE := preload("res://scenes/portal.tscn")
const WEAPON_DROP_SCENE := preload("res://scenes/weapon_drop.tscn")

var _hud = null
var _camera_fx = null
var _sequencer: BossDeathSequencer = null
var _boss: BossEnemy = null
var _arena_center: Vector2 = Vector2.ZERO
var _intro_tween: Tween = null


func _ready() -> void:
	add_to_group("boss_encounter")
	_sequencer = BossDeathSequencer.new()
	add_child(_sequencer)
	_camera_fx = null  # Lazy-created on first notify_spawned if a camera exists.


func is_fight_active() -> bool:
	return _boss != null and is_instance_valid(_boss)


func current_boss() -> BossEnemy:
	return _boss


func notify_spawned(boss: BossEnemy, arena_center: Vector2) -> void:
	if is_fight_active():
		push_warning("BossEncounter: a boss is already active; ignoring extra spawn.")
		return
	_boss = boss
	_arena_center = arena_center
	if _hud == null:
		_hud = BOSS_HUD_SCENE.instantiate()
		add_child(_hud)
	var thresholds: Array[int] = []
	for p in range(1, boss.phase_count + 1):
		thresholds.append(boss._phase_threshold(p))
	_hud.setup(boss.boss_name, boss.max_health, boss.phase_count, thresholds)
	_hud.show_hud()
	# Camera setup (lazy, best-effort).
	if _camera_fx == null:
		var cam := get_tree().get_first_node_in_group("player_camera")
		if cam is Camera2D:
			var fx := CameraEffect.new()
			add_child(fx)
			fx.setup(cam)
			_camera_fx = fx
	_sequencer._spawn_parent = _spawn_container()
	_sequencer._portal_scene = PORTAL_SCENE
	_sequencer.camera_fx = _camera_fx
	_sequencer.shake_callback = Callable(self, "shake")
	# Signals.
	boss.phase_changed.connect(_on_phase_changed)
	boss.health_changed.connect(_on_health_changed)
	boss.died.connect(_on_died_signal)
	# Intro.
	boss.set_encounter_active(false)
	var edge := _biome_edge_color()
	var sprite := boss.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		FX.appear(sprite, 1.2, edge)
	if _camera_fx:
		_camera_fx.pan_to(boss.global_position, 1.2, Vector2(1.1, 1.1))
	_intro_tween = create_tween()
	_intro_tween.tween_interval(1.5)
	_intro_tween.tween_callback(func():
		if not is_instance_valid(boss): return
		boss.set_encounter_active(true)
		if _camera_fx: _camera_fx.pan_back(0.8))


func notify_died(boss: BossEnemy, arena_center: Vector2) -> void:
	var actual := boss if boss != null else _boss
	if _boss != actual:
		return
	if _hud:
		_hud.hide_hud()
	var edge := _biome_edge_color()
	_sequencer.play(actual, arena_center, edge, WEAPON_DROP_SCENE)


func _on_phase_changed(phase: int) -> void:
	if _hud:
		_hud.set_phase(phase)


func _on_health_changed(current: int, _maximum: int) -> void:
	if _hud:
		_hud.update_health(current)


func _on_died_signal() -> void:
	if _boss == null:
		return
	# notify_died was triggered by the dispatcher via group call; this is a backup.
	pass


func shake(intensity: float, duration: float) -> void:
	if _camera_fx:
		_camera_fx.shake(intensity, duration)


func clear() -> void:
	if _boss and is_instance_valid(_boss):
		if _boss.phase_changed.is_connected(_on_phase_changed):
			_boss.phase_changed.disconnect(_on_phase_changed)
		if _boss.health_changed.is_connected(_on_health_changed):
			_boss.health_changed.disconnect(_on_health_changed)
	_boss = null
	if _hud:
		_hud.hide_hud()


func _biome_edge_color() -> Color:
	var biome = LevelManager.current_biome
	if biome and biome.has_method("get") and "ui_accent" in biome:
		return biome.ui_accent
	return Color(1.0, 0.6, 0.15)


func _spawn_container() -> Node:
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm and is_instance_valid(wm):
		return wm.get_chunk_container()
	return get_tree().root
