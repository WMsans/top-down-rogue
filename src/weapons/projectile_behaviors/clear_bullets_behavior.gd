class_name ClearBulletsBehavior
extends ProjectileBehavior

func on_enemy_projectile_overlap(_proj, enemy_proj) -> void:
	if not is_instance_valid(enemy_proj):
		return
	ProjectileBlockFX.play(enemy_proj.global_position, -enemy_proj.direction)
	enemy_proj.queue_free()
