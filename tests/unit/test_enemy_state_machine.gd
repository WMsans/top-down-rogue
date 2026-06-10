extends GdUnitTestSuite

class MockEnemy extends Enemy:
	var attack_called: bool = false
	func _execute_attack() -> void:
		attack_called = true

func test_starts_in_wander() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	assert_that(e._state).is_equal(Enemy.State.WANDER)

func test_transitions_to_chase_when_player_in_range() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._player_in_range = true
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e._process(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)

func test_transitions_to_wander_when_player_leaves() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._player_in_range = false
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(200, 0)
	e._state = Enemy.State.CHASE
	e._process(0.1)
	assert_that(e._state).is_equal(Enemy.State.WANDER)

func test_hurt_re_staggerable() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.health = 100
	e._state = Enemy.State.CHASE
	e._state_timer = 0.1
	e.hit(5)
	assert_that(e._state).is_equal(Enemy.State.HURT)
	var timer_after_first: float = e._state_timer
	e.hit(5)
	assert_that(e._state_timer).is_equal(e.hurt_duration)

func test_death_on_zero_health() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.health = 5
	e.hit(10)
	assert_that(e._state).is_equal(Enemy.State.DEATH)

func test_elite_stat_scaling() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.health = e.max_health
	e.speed = 100.0
	e.is_elite = true
	e._apply_elite_scaling()
	assert_that(e.max_health).is_equal(60)
	assert_that(e.speed).is_greater(100.0)

func test_elite_tank_speed() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.health = e.max_health
	e.speed = 100.0
	e._speed_base = 100.0
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.TANK
	e._apply_elite_scaling()
	assert_that(e.speed).is_equal(70.0)

func test_elite_fast_windup_floor() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.health = e.max_health
	e.windup_duration = 0.3
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.FAST
	e._apply_elite_scaling()
	assert_that(e.windup_duration).is_equal(0.2)

func test_wander_enters_pause_after_move() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._state = Enemy.State.WANDER
	e._wander_is_paused = false
	e._wander_timer = 0.01
	e._process(0.1)
	assert_that(e._wander_is_paused).is_true()
	assert_that(e.velocity).is_equal(Vector2.ZERO)

func test_wander_stays_wander_without_player() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e._state = Enemy.State.WANDER
	e._player_in_range = false
	e._player_ref = null
	e._process(0.1)
	assert_that(e._state).is_equal(Enemy.State.WANDER)

func test_exclaim_shown_on_windup() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._state = Enemy.State.CHASE
	e._change_state(Enemy.State.WINDUP)
	await get_tree().process_frame
	if e._exclaim_label:
		assert_that(e._exclaim_label.scale).is_not_equal(Vector2.ZERO)

func test_exclaim_hidden_on_attack() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._state = Enemy.State.WINDUP
	e._change_state(Enemy.State.ATTACK)
	await get_tree().process_frame
	if e._exclaim_label:
		assert_that(e._exclaim_label.scale).is_equal(Vector2.ZERO)

func test_parry_stun_blocks_ai_tick() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	await get_tree().process_frame
	var player_ref: Node2D = auto_free(Node2D.new())
	add_child(player_ref)
	e._player_ref = player_ref
	e._parry_stun_remaining = 0.2
	# Force state to CHASE so we'd normally see velocity change.
	e._state = Enemy.State.CHASE
	e.global_position = Vector2.ZERO
	e.velocity = Vector2.ZERO
	e._process(0.05)
	# While stunned, AI should not have driven velocity toward player.
	assert_that(e.velocity).is_equal(Vector2.ZERO)
	assert_that(e._parry_stun_remaining).is_less(0.2)

func test_parry_stun_extends_cooldown() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	await get_tree().process_frame
	e.cooldown_duration = 0.1
	e._change_state(Enemy.State.COOLDOWN)
	e._parry_stun_remaining = 0.5
	e._process(0.05)
	# After 0.05s, normal cooldown would be ~0.05 remaining; stun should keep it >= 0.4.
	assert_that(e._state_timer).is_greater(0.3)

# Minimal stand-in for WorldManager exposing a swarm_grid for separation tests.
class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)

func test_separation_uses_grid_neighbors_only() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.global_position = Vector2(0, 0)
	e.separation_radius = 16.0

	# A crowding neighbour up-right from self.
	var other: MockEnemy = auto_free(MockEnemy.new())
	add_child(other)
	other.global_position = Vector2(8, 4)

	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	world.swarm_grid.rebuild([e, other])
	e._world_manager = world

	# Moving right; separation should bend the vector away from +X
	# (its x-component drops below the raw 1.0).
	var result: Vector2 = e._apply_separation(Vector2.RIGHT)
	assert_bool(result.x < 1.0).is_true()

func test_separation_without_world_returns_input() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = null
	var result: Vector2 = e._apply_separation(Vector2.RIGHT)
	assert_vector(result).is_equal(Vector2.RIGHT)


func test_player_in_range_true_when_close() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.detection_radius = 100.0
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e.global_position = Vector2.ZERO
	e._player_ref.global_position = Vector2(50, 0)
	e._update_player_in_range()
	assert_bool(e._player_in_range).is_true()

func test_player_in_range_false_when_far() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.detection_radius = 100.0
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e.global_position = Vector2.ZERO
	e._player_ref.global_position = Vector2(200, 0)
	e._update_player_in_range()
	assert_bool(e._player_in_range).is_false()

func test_player_in_range_false_when_no_player() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._player_ref = null
	e._update_player_in_range()
	assert_bool(e._player_in_range).is_false()


const _Director = preload("res://src/core/encounter_director.gd")

func test_is_pursuing_reflects_aggro() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	assert_bool(e.is_pursuing()).is_false()
	e._aggroed = true
	assert_bool(e.is_pursuing()).is_true()

func test_aggroed_enemy_does_not_leash_when_far() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10000, 0)  # well beyond leash_radius
	e.global_position = Vector2.ZERO
	e._aggroed = true
	e._state = Enemy.State.CHASE
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)  # never gives up once aggroed

func test_die_unregisters_from_director() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	var d = _Director.new()
	e._director = d
	e._aggroed = true
	d._active = [e]
	d.try_claim_attack(e, false)
	e.die()
	assert_bool(d.is_active(e)).is_false()


func test_effective_speed_capped_below_player_when_far() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.speed = 60.0
	e._speed_base = 60.0
	e._aggroed = true
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.set("max_speed", 120.0)
	e._player_ref.global_position = Vector2(2000, 0)  # far -> ramps to cap
	e.global_position = Vector2.ZERO
	var s := e._get_effective_speed()
	assert_float(s).is_equal_approx(114.0, 0.001)  # 120 * 0.95

func test_effective_speed_uses_base_when_not_aggroed() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.speed = 60.0
	e._speed_base = 60.0
	e._aggroed = false
	e._player_ref = null
	assert_float(e._get_effective_speed()).is_equal_approx(60.0, 0.001)


class _FakeWorld extends Node:
	var swarm_grid
	var encounter_director

func test_contagion_aggros_idle_enemy_near_pursuer() -> void:
	var d = _Director.new()
	var world: Node = auto_free(_FakeWorld.new())
	add_child(world)
	world.encounter_director = d
	world.swarm_grid = preload("res://src/core/swarm_grid.gd").new(64.0)

	var idle: MockEnemy = auto_free(MockEnemy.new())
	idle.global_position = Vector2.ZERO
	idle._world_manager = world
	idle._director = d
	idle._state = Enemy.State.WANDER
	idle._player_ref = null

	var pursuer: MockEnemy = auto_free(MockEnemy.new())
	pursuer.global_position = Vector2(30, 0)  # within CONTAGION_RADIUS (48)
	pursuer._aggroed = true

	world.swarm_grid.rebuild([idle, pursuer])
	idle._process_idle(0.1)
	assert_bool(idle._aggroed).is_true()
	assert_that(idle._state).is_equal(Enemy.State.CHASE)


func test_chase_attacks_when_token_available() -> void:
	var d = _Director.new()
	d.melee_token_count = 1
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._director = d
	e._aggroed = true
	e._state = Enemy.State.CHASE
	d._active = [e]
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 32.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.WINDUP)

func test_chase_holds_when_no_token() -> void:
	var d = _Director.new()
	d.melee_token_count = 0  # no tokens available
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._director = d
	e._aggroed = true
	e._state = Enemy.State.CHASE
	d._active = [e]
	e._player_ref = auto_free(Node2D.new())
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e.global_position = Vector2.ZERO
	e._attack_range = 32.0
	e._settle_timer = e.min_attack_settle_time + 1.0
	e._process_chase(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)  # cannot commit, keeps circling

func test_damage_scale_multiplies_weapon_damage_on_ready() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.weapon = MeleeWeapon.new()
	e.weapon.damage = 5.0
	e.damage_scale = 2.0
	e._apply_damage_scale()
	assert_float(e.weapon.damage).is_equal_approx(10.0, 0.001)

func test_change_state_releases_token_on_return_to_chase() -> void:
	var d = _Director.new()
	d.melee_token_count = 1
	var holder: MockEnemy = auto_free(MockEnemy.new())
	var waiter: MockEnemy = auto_free(MockEnemy.new())
	add_child(holder)
	add_child(waiter)
	holder._director = d
	waiter._director = d
	d._active = [holder, waiter]
	assert_bool(holder._try_claim_attack()).is_true()
	assert_bool(waiter._try_claim_attack()).is_false()
	holder._change_state(Enemy.State.CHASE)  # leaving the attack cycle
	assert_bool(waiter._try_claim_attack()).is_true()  # token released
