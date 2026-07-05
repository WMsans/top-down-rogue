extends GdUnitTestSuite


func test_base_enemy_does_not_move_during_attack() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(e)
	assert_bool(e._moves_during_attack()).is_false()


# --- Task 2: skeleton ---

func _lunge_at(origin: Vector2, player_pos: Vector2) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	return e

func test_ready_sets_lunge_attack_range() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_float(e._attack_range).is_equal(e.lunge_range)

func test_begin_dash_locks_direction_toward_player() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._begin_dash()
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.01)
	assert_float(e._dash_timer).is_equal(e.dash_duration)
	assert_bool(e._dash_hit).is_false()

func test_moves_during_attack_tracks_state_and_dash_done() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.CHASE
	assert_bool(e._moves_during_attack()).is_false()
	e._state = Enemy.State.ATTACK
	e._dash_done = false
	assert_bool(e._moves_during_attack()).is_true()
	e._dash_done = true
	assert_bool(e._moves_during_attack()).is_false()


# --- Task 3: dash tick + body-check + termination ---

func _make_recording_player(pos: Vector2) -> Node2D:
	var script := GDScript.new()
	script.source_code = '\n'.join([
		"extends Node2D",
		"var hits: Array = []",
		"func on_hit_impact(_pos: Vector2, _dir: Vector2, dmg: int) -> void:",
		"\thits.push_back({_pos = _pos, _dir = _dir, dmg = dmg})",
	])
	var err := script.reload()
	assert_int(err).is_equal(OK)
	var p: Node2D = auto_free(Node2D.new())
	p.set_script(script)
	add_child(p)
	p.global_position = pos
	return p

func _lunge_to_recording(origin: Vector2, player_pos: Vector2) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	add_child(e)
	e.global_position = origin
	e._player_ref = _make_recording_player(player_pos)
	return e

func test_dash_sets_velocity_along_lock_dir() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	e._process_attack(0.05)
	assert_float(e.velocity.x).is_equal_approx(e.dash_speed, 0.01)
	assert_float(e.velocity.y).is_equal_approx(0.0, 0.01)

func test_dash_terminates_into_cooldown() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	assert_int(e._state).is_equal(Enemy.State.COOLDOWN)
	assert_bool(e._dash_done).is_true()

func test_body_check_hits_once_within_contact_radius() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(5, 0))
	e.dash_damage = 7.0
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	var hits: Array = e._player_ref.hits
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0]["dmg"]).is_equal(7)

func test_sidestepped_player_takes_no_hit() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(200, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	assert_int(e._player_ref.hits.size()).is_equal(0)

func test_dash_done_blocks_restart() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(5, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = true
	e._process_attack(0.05)
	assert_int(e._state).is_equal(Enemy.State.COOLDOWN)
	assert_int(e._player_ref.hits.size()).is_equal(0)


# --- Task 4: windup reset + telegraph ---

func test_entering_windup_resets_dash_done() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._dash_done = true
	e._change_state(Enemy.State.WINDUP)
	assert_bool(e._dash_done).is_false()
	assert_int(e._state).is_equal(Enemy.State.WINDUP)

func test_entering_windup_runs_telegraph_without_error() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._change_state(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal(e.windup_duration)


# --- Task 5: scene ---

func test_scene_instantiates_as_lunge_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is LungeEnemy).is_true()
	assert_float(e._attack_range).is_equal(e.lunge_range)


# --- Task 3: weaponless dash damage ---

func test_lunge_enemy_has_no_weapon() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_object(e.weapon).is_null()

func test_lunge_enemy_carries_weapon_is_false() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_bool(e.carries_weapon).is_false()

# --- Task 4: larger scale ---

func test_lunge_enemy_scales_up() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_vector(e.scale).is_equal(Vector2(1.6, 1.6))

# --- Task 6: dash fire VFX wiring ---

func test_lunge_enemy_has_fire_vfx_child() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_object(e._fire_vfx).is_not_null()
	assert_bool(e._fire_vfx is DashFireVfx).is_true()

func test_begin_dash_starts_fire_vfx_along_lock_dir() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._begin_dash()
	var particles: CPUParticles2D = e._fire_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_true()
	assert_float(e._fire_vfx.rotation).is_equal_approx(e._lock_dir.angle(), 0.01)

func test_dash_end_stops_fire_vfx() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	var particles: CPUParticles2D = e._fire_vfx.get_node("Particles")
	assert_bool(particles.emitting).is_false()

func test_body_check_uses_dash_damage_scaled_by_damage_scale() -> void:
	var e := _lunge_to_recording(Vector2.ZERO, Vector2(5, 0))
	e.dash_damage = 7.0
	e.damage_scale = 2.0
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	for i in range(20):
		if e._state != Enemy.State.ATTACK:
			break
		e._process_attack(0.05)
	var hits: Array = e._player_ref.hits
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0]["dmg"]).is_equal(14)


# --- Enemy Visual Identity: dash-hold frame ---

func _lunge_from_scene() -> LungeEnemy:
	var scene: PackedScene = load("res://scenes/enemies/lunge_enemy.tscn")
	var e: LungeEnemy = auto_free(scene.instantiate())
	add_child(e)
	return e

func test_windup_holds_breathe_frame() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.BREATHE)
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_brute2")

func test_attack_holds_normal_frame() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.NORMAL)
	var sprite: Sprite2D = e.get_node("Sprite2D")
	assert_str(sprite.texture.resource_path).contains("caves_brute1")

func test_cooldown_releases_hold() -> void:
	var e := _lunge_from_scene()
	await get_tree().process_frame
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._change_state(Enemy.State.COOLDOWN)
	var animator: EnemyAnimator = e.get_node("EnemyAnimator")
	assert_int(animator._hold).is_equal(EnemyAnimator.Hold.NONE)
