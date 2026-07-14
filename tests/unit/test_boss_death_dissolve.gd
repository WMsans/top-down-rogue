extends GdUnitTestSuite

const BossDeathSequencer = preload("res://src/core/boss_death_sequencer.gd")

class FakeBoss extends BossEnemy:
	func _ready() -> void:
		pass


func test_play_dissolves_and_clears_and_frees() -> void:
	var boss : FakeBoss = auto_free(FakeBoss.new())
	var tex : Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tex.fill(Color(1, 1, 1, 1))
	boss.global_position = Vector2.ZERO
	var sprite : Sprite2D = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = ImageTexture.create_from_image(tex)
	boss.add_child(sprite)
	var seq : BossDeathSequencer = auto_free(BossDeathSequencer.new())
	seq.configure(null, null, null, true)
	seq.play(boss, Vector2.ZERO, Color(1.0, 0.6, 0.15), null)
	assert_bool(sprite.material is ShaderMaterial).is_true()
	await get_tree().create_timer(0.5).timeout
	assert_bool(is_instance_valid(boss)).is_false()
