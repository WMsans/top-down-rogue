extends GdUnitTestSuite

const BossEncounter = preload("res://src/core/boss_encounter.gd")

class FakeBoss extends BossEnemy:
	func _ready() -> void:
		pass


func _new_controller() -> BossEncounter:
	var c: BossEncounter = auto_free(BossEncounter.new())
	get_tree().root.add_child(c)
	# Inject stub camera_fx so it doesn't need a real Camera2D.
	c._camera_fx = null
	c._sequencer._fast = true
	return c


func test_notify_spawned_attaches_hud_and_starts_intro() -> void:
	var c: BossEncounter = _new_controller()
	var boss: FakeBoss = auto_free(FakeBoss.new())
	boss.boss_name = "Test"
	boss.max_health = 100
	boss.health = 100
	boss.phase_count = 3
	get_tree().root.add_child(boss)
	c.notify_spawned(boss, Vector2.ZERO)
	assert_bool(c.is_fight_active()).is_true()


func test_notify_died_runs_death_and_clears_active() -> void:
	var c: BossEncounter = _new_controller()
	var boss: FakeBoss = auto_free(FakeBoss.new())
	boss.boss_name = "Test"
	boss.max_health = 100
	boss.health = 100
	boss.phase_count = 3
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	boss.add_child(sprite)
	get_tree().root.add_child(boss)
	c.notify_spawned(boss, Vector2.ZERO)
	c.notify_died(boss, Vector2.ZERO)
	await get_tree().create_timer(0.6).timeout
	assert_bool(c.is_fight_active()).is_false()
	assert_bool(is_instance_valid(boss)).is_false()


func test_second_spawn_while_active_is_ignored() -> void:
	var c: BossEncounter = _new_controller()
	var boss1: FakeBoss = auto_free(FakeBoss.new())
	boss1.boss_name = "B1"; boss1.max_health = 100; boss1.health = 100; boss1.phase_count = 3
	get_tree().root.add_child(boss1)
	c.notify_spawned(boss1, Vector2.ZERO)
	var boss2: FakeBoss = auto_free(FakeBoss.new())
	boss2.boss_name = "B2"; boss2.max_health = 100; boss2.health = 100; boss2.phase_count = 3
	get_tree().root.add_child(boss2)
	c.notify_spawned(boss2, Vector2.ZERO)  # should be ignored
	assert_bool(c.current_boss() == boss1).is_true()
