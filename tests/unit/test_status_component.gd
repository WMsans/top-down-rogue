extends GdUnitTestSuite

const StatusComponentScript = preload("res://src/status/status_component.gd")

class FakeOwner extends Node:
	var taken: int = 0
	func apply_status_damage(amount: int) -> void:
		taken += amount

# Fake WorldManager exposing a .chunks dict so TerrainPhysical.prepare_probe_batch
# can bin probes; only cells in loaded chunks get probed (matches the real gate).
class FakeWM extends Node2D:
	var chunks: Dictionary = {}

class FakeBody extends Node2D:
	var velocity: Vector2 = Vector2.ZERO

# Drives the REAL TerrainPhysical probe pipeline (no GPU) with the exact ordering
# of world_manager: physics polls (queues probes), then _process reads back the
# PREVIOUS dispatch and dispatches the current pending set. Probe results are
# synthesised so every probed cell reads back as `material_id`. This reproduces
# the real two-frame read-back latency, TTL, budget cap, and chunk gating, so the
# stationary-vs-moving cache behaviour matches the running game.
func _make_terrain(material_id: int) -> TerrainPhysical:
	var wm: FakeWM = auto_free(FakeWM.new())
	add_child(wm)
	# Load a 3x3 block of chunks around the origin so all sampled cells are valid.
	for cx in range(-1, 2):
		for cy in range(-1, 2):
			wm.chunks[Vector2i(cx, cy)] = true
	var tp: TerrainPhysical = auto_free(TerrainPhysical.new())
	tp.world_manager = wm
	tp.set_meta("synth_mat", material_id)
	return tp

# Mirrors world_manager._run_terrain_probes, minus the GPU dispatch: read back the
# previous dispatch, then drain+record the current pending set for next frame.
func _process_probes(tp: TerrainPhysical) -> void:
	var prev_batch: Array = tp._last_batch
	var prev_total: int = tp._last_total_count
	if prev_total > 0:
		var raw := PackedByteArray()
		raw.resize(prev_total * 4)
		var mat: int = tp.get_meta("synth_mat")
		for i in prev_total:
			raw.encode_u32(i * 4, mat)
		tp.apply_probe_results(prev_batch, raw)
	var batch := tp.prepare_probe_batch(64)
	var total: int = 0
	for entry in batch:
		total += int(entry["count"])
	tp.record_dispatched_batch(batch, total)

func _make_poll_setup(material_id: int, vel: Vector2) -> Array:
	var body: FakeBody = auto_free(FakeBody.new())
	add_child(body)
	body.velocity = vel
	var tp := _make_terrain(material_id)
	var c: StatusComponent = StatusComponentScript.new()
	body.add_child(c)
	c._owner_node = body
	c._terrain_physical = tp
	return [c, body, tp]

# One game frame: physics poll first, then the _process probe pipeline, then move.
func _drive(c: StatusComponent, body: FakeBody, tp: TerrainPhysical, frames: int, dt: float = 1.0 / 60.0) -> void:
	for _i in frames:
		c._poll_terrain(dt)
		_process_probes(tp)
		body.global_position += body.velocity * dt

func _make_comp(owner: Node) -> StatusComponent:
	var c: StatusComponent = StatusComponentScript.new()
	owner.add_child(c)
	return c

func test_add_and_get_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 2.5)
	assert_float(c.get_stain("wet")).is_equal_approx(2.5, 0.001)

func test_has_status_threshold() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 0.5)
	assert_that(c.has_status("on_fire")).is_false()
	c.add_stain("on_fire", 1.0)  # total 1.5 >= 1.0
	assert_that(c.has_status("on_fire")).is_true()

func test_decay_reduces_stain() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 5.0)  # decay_rate 0.5
	c.tick(1.0)
	assert_float(c.get_stain("wet")).is_equal_approx(4.5, 0.001)

func test_frozen_blocks_movement() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("frozen", 5.0)
	assert_that(c.is_movement_blocked()).is_true()
	assert_float(c.get_move_speed_multiplier()).is_equal_approx(0.0, 0.001)

func test_chilly_slows_movement() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("chilly", 2.0)
	assert_that(c.is_movement_blocked()).is_false()
	assert_float(c.get_move_speed_multiplier()).is_equal_approx(0.6, 0.001)

func test_burn_calls_owner_damage() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	c.add_stain("on_fire", 5.0)  # burn_dps 4
	c.tick(1.0)  # decay -1 -> 4 (still active); burn 4*1=4 delivered
	assert_that(owner.taken).is_equal(4)

func test_active_ids_lists_active_only() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("wet", 2.0)
	c.add_stain("on_fire", 0.2)  # below threshold
	var ids: Array = c.get_active_ids()
	assert_that(ids.has("wet")).is_true()
	assert_that(ids.has("on_fire")).is_false()


func test_blended_tint_white_when_none() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	assert_that(c.get_blended_tint()).is_equal(Color.WHITE)


func test_blended_tint_shifts_with_status() -> void:
	var c: StatusComponent = auto_free(StatusComponentScript.new())
	c.add_stain("on_fire", 5.0)  # active, orange tint
	var tint: Color = c.get_blended_tint()
	assert_that(tint).is_not_equal(Color.WHITE)
	assert_bool(tint.r > tint.b).is_true()  # warm tint

func test_burn_tick_emitted_on_whole_damage() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	var flag := [false]
	c.burn_tick.connect(func() -> void: flag[0] = true)
	c.add_stain("on_fire", 5.0)  # burn_dps 4
	c.tick(1.0)
	assert_bool(flag[0]).is_true()

func test_burn_tick_not_emitted_without_fire() -> void:
	var owner: FakeOwner = auto_free(FakeOwner.new())
	add_child(owner)
	var c: StatusComponent = _make_comp(owner)
	var flag := [false]
	c.burn_tick.connect(func() -> void: flag[0] = true)
	c.add_stain("wet", 5.0)
	c.tick(1.0)
	assert_bool(flag[0]).is_false()


func test_standing_in_lava_accumulates_fire() -> void:
	var s: Array = _make_poll_setup(MaterialRegistry.MAT_LAVA, Vector2.ZERO)
	var c: StatusComponent = s[0]
	_drive(c, s[1], s[2], 6)
	assert_float(c.get_stain("on_fire")).is_greater(0.0)


func test_walking_through_lava_accumulates_fire() -> void:
	# 200 px/s steps the owner onto a fresh probe cell every frame; the bug was
	# that those cold cells read AIR and stain never accumulated while moving.
	var s: Array = _make_poll_setup(MaterialRegistry.MAT_LAVA, Vector2(200.0, 0.0))
	var c: StatusComponent = s[0]
	_drive(c, s[1], s[2], 12)
	assert_float(c.get_stain("on_fire")).is_greater(0.0)


func test_walking_through_blood_accumulates_bloody() -> void:
	var s: Array = _make_poll_setup(MaterialRegistry.MAT_BLOOD, Vector2(200.0, 0.0))
	var c: StatusComponent = s[0]
	_drive(c, s[1], s[2], 12)
	assert_float(c.get_stain("bloody")).is_greater(0.0)


func test_walking_diagonally_through_lava_accumulates_fire() -> void:
	var s: Array = _make_poll_setup(MaterialRegistry.MAT_LAVA, Vector2(140.0, 140.0))
	var c: StatusComponent = s[0]
	_drive(c, s[1], s[2], 12)
	assert_float(c.get_stain("on_fire")).is_greater(0.0)
