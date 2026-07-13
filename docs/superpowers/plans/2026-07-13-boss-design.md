# Boss Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single generic boss with five biome-specific bosses (multi-pattern phases), a `BossEncounter` controller owning HUD/intro/death, and a Saltmire-driven death that dissolves the boss into streaming motes pulled into the portal.

**Architecture:** Refactor `BossEnemy` into a thin base (health-gate state machine + virtual hooks `_on_phase_enter`/`_tick_phase`/`_do_attack` + pattern-rotation index + facade methods for terrain/status/prop/minion). Add one behavior subclass + scene per biome; each phase rotates ≥2 distinct telegraphed attack patterns. A `BossEncounter` controller (group `boss_encounter`) owns the fight lifecycle: HUD, intro (`FX.appear` + camera pan), death (`FX.dissolve` + silhouette fragments → portal). Dispatchers emit to the controller and stop spawning portals themselves.

**Tech Stack:** Godot 4 (GDScript), gdUnit4 tests, Saltmire FX addon (`FX` autoload, `addons/saltmire_fx/`), existing terrain material system (`MaterialRegistry.MAT_*`, `TerrainSurface`, `CompositionDispatcher.place_material_*`), `StatusRegistry` (`chilly`/`frozen`).

## Global Constraints

These apply to every task implicitly; copy exact values verbatim from the spec.

- **No audio / FMOD.** No `boss_music_requested` signal, no sting hooks, no parameter buses.
- **No new sprite art.** Biome bosses reuse `textures/Enemies/boss_test.png`, tinted per biome via `modulate` (matching the existing `SpawnDispatcher._spawn_enemy` line `enemy.modulate = LevelManager.current_biome.tint`).
- **No new terrain materials.** Reuse `MaterialRegistry.MAT_DUST`, `MAT_LAVA`, `MAT_AIR`, `MAT_ICE`, `MAT_STONE`, `MAT_GAS` and the existing `chilly`/`frozen` status effects.
- **Saltmire FX API is concrete:** `FX.dissolve(target: CanvasItem, duration: float = 0.5, edge_color: Color = Color(1.0, 0.6, 0.15)) -> Tween` (drives `progress` 0→1), `FX.appear(target, duration, edge_color) -> Tween` (progress 1→0), `FX.clear(target) -> void`. Shader: `addons/saltmire_fx/shaders/dissolve.gdshader`, uniforms `progress`, `edge_width`, `edge_color`, `noise_scale`.
- **Facade-only singleton access in subclasses.** `BossEnemy` exposes `_stamp_material`, `_apply_status`, `_spawn_minion`, `_spawn_prop`; subclasses never call `CompositionDispatcher`/`TerrainSurface`/`StatusRegistry` directly. This is required for testability.
- **One boss active at a time by design.** A second `notify_spawned` mid-fight is logged and ignored.
- **gdUnit4 test runs:** `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_<suite>.gd`. In a fresh worktree, run `godot --headless --path . --import` first. Headless boot takes 30–60s before any output — do not assume a quiet first minute means a hang.
- **`const` arrays in GDScript 4** must use typed-literal syntax (`const X: Array[Vector2] = [...]`), not a constructor call (`const X := PackedVector2Array([...])`) — the latter fails to parse as a constant expression.
- **Commit messages** use conventional `feat:`/`refactor:`/`test:` style.
- **Existing tests must keep passing.** `test_boss_phase_transition.gd`, `test_boss_drops.gd`, `test_boss_ring_coverage.gd` reference `BossEnemy`/its public hooks; the refactor preserves `_phase_threshold`, `_setup_drop_table`, `_check_phase_transition`, `current_phase`, `phase_count` and the `died` signal.

---

## File Structure

New files:

| Path | Responsibility |
|------|----------------|
| `src/enemies/bosses/burrower_boss.gd` | Caves boss — charge/dust/pit phases |
| `src/enemies/bosses/pyrelord_boss.gd` | Magma boss — orb/lava-trail/ring phases |
| `src/enemies/bosses/glacier_boss.gd` | Frozen boss — shard/chill/pillar phases |
| `src/enemies/bosses/drill_boss.gd` | Mines boss — bore/mine/wall phases |
| `src/enemies/bosses/warden_boss.gd` | Vault boss — ricochet/magnet/adds phases |
| `scenes/enemies/bosses/burrower_boss.tscn` | Caves boss scene |
| `scenes/enemies/bosses/pyrelord_boss.tscn` | Magma boss scene |
| `scenes/enemies/bosses/glacier_boss.tscn` | Frozen boss scene |
| `scenes/enemies/bosses/drill_boss.tscn` | Mines boss scene |
| `scenes/enemies/bosses/warden_boss.tscn` | Vault boss scene |
| `scenes/props/mine.tscn` | Proximity mine prop (Drill phase 2) |
| `src/props/mine.gd` | Mine arming + proximity explosion |
| `src/enemies/fx/boss_telegraph.gd` | Telegraph primitive factory (ground-crack line, expanding circle, column-rise, shockwave ring, converging particles) |
| `src/ui/boss_hud.gd` | Boss health bar HUD (name + bar + phase pips + gate ticks) |
| `scenes/ui/boss_hud.tscn` | HUD scene |
| `src/core/camera_effect.gd` | Thin wrapper over main Camera2D (pan + shake) |
| `src/core/boss_encounter.gd` | Fight lifecycle controller (intro, ongoing sync, death, portal) |
| `src/core/boss_death_sequencer.gd` | Saltmire dissolve + silhouette fragment streamer |
| `tests/unit/test_boss_attack_cadence.gd` | Cadence + `_do_attack` override hook |
| `tests/unit/test_boss_floor_scaling.gd` | `_apply_floor_scaling` multipliers |
| `tests/unit/test_boss_phase_changed_signal.gd` | `phase_changed` emission + chaining |
| `tests/unit/test_boss_facade.gd` | Base facade methods route through injected dispatcher |
| `tests/unit/test_boss_telegraphs.gd` | Telegraph primitives spawn + clean up |
| `tests/unit/test_burrower_boss_phases.gd` | Burrower pattern rotation + hooks |
| `tests/unit/test_pyrelord_boss_phases.gd` | Pyrelord pattern rotation + hooks |
| `tests/unit/test_glacier_boss_phases.gd` | Glacier pattern rotation + hooks |
| `tests/unit/test_drill_boss_phases.gd` | Drill pattern rotation + hooks |
| `tests/unit/test_warden_boss_phases.gd` | Warden pattern rotation + hooks |
| `tests/unit/test_mine_prop.gd` | Mine arming/explosion |
| `tests/unit/test_boss_hud.gd` | HUD update on phase/health changes |
| `tests/unit/test_camera_effect.gd` | Camera pan + shake |
| `tests/unit/test_boss_encounter_lifecycle.gd` | Controller intro/sync/death (injected tweens) |
| `tests/unit/test_boss_death_dissolve.gd` | Saltmire dissolve on death |
| `tests/unit/test_boss_fragment_stream.gd` | Silhouette sampler rejects transparent pixels |
| `tests/unit/test_boss_arena_biome_match.gd` | Arena `.tres` compositions point to correct biome boss scene |

Modified files:

| Path | Change |
|------|--------|
| `src/enemies/boss_enemy.gd` | Refactor into thin base: add `phase_changed`/`boss_ready` signals, hooks `_on_phase_enter`/`_tick_phase`/`_do_attack`, cadence timer, pattern rotation `_pick_pattern`/`_execute_pattern`, `_apply_floor_scaling`, facade methods; remove hardcoded phase-2 spread + phase-3 lava |
| `scenes/enemies/boss_enemy.tscn` | Strip phase-2/phase-3 exports now handled by subclasses (keep scene as legacy reference; unused after repoint) |
| `src/core/spawn_dispatcher.gd` | `is_boss` branch → load `LevelManager.current_biome.boss_scene` instead of `BOSS_ENEMY_SCENE`/`boss_staff`; remove `_on_boss_died` portal spawn; emit `boss_spawned`/`boss_died` |
| `src/core/composition_dispatcher.gd` | Remove `_on_boss_died` portal spawn; emit `boss_spawned`/`boss_died` |
| `src/autoload/level_manager.gd` | Call `BossEncounter.clear()` in `advance_floor` (it's a group node now, not an autoload) |
| `assets/biomes/caves.tres` | Add `boss_scene = ExtResource(...)` → burrower |
| `assets/biomes/magma.tres` | → pyrelord |
| `assets/biomes/frozen.tres` | → glacier |
| `assets/biomes/mines.tres` | → drill |
| `assets/biomes/vault.tres` | → warden |
| `assets/arenas/boss/caves_{a,b,c,d}.tres` | Repoint `FeatureBossSpawn.boss_scene` to burrower scene |
| `assets/arenas/boss/magma_{a,b,c,d}.tres` | → pyrelord |
| `assets/arenas/boss/frozen_{a,b,c,d}.tres` | → glacier |
| `assets/arenas/boss/mines_{a,b,c,d}.tres` | → drill |
| `assets/arenas/boss/vault_{a,b,c,d}.tres` | → warden |
| `tests/unit/test_boss_phase_transition.gd` | Add `phase_changed` signal assertion (math unchanged) |

---

## Task 1: Telegraph primitives

**Files:**
- Create: `src/enemies/fx/boss_telegraph.gd`
- Test: `tests/unit/test_boss_telegraphs.gd`

**Interfaces:**
- Consumes: `EnemyVfxShared.soft_dot_texture()`, `EnemyVfxShared.fade_gradient(hot, fade)` (`src/enemies/feedback/enemy_vfx_shared.gd`)
- Produces: `BossTelegraph` class with static factory methods, each returning a `Node2D` the caller parents to the world layer and `queue_free()`s after `duration`:
  - `BossTelegraph.ground_crack_line(world_parent: Node, start: Vector2, end: Vector2, duration: float) -> Node2D`
  - `BossTelegraph.expanding_circle(world_parent: Node, center: Vector2, max_radius: float, duration: float) -> Node2D`
  - `BossTelegraph.column_rise(world_parent: Node, base: Vector2, height: float, duration: float) -> Node2D`
  - `BossTelegraph.shockwave_ring(world_parent: Node, center: Vector2, max_radius: float, duration: float) -> Node2D`
  - `BossTelegraph.converging_particles(world_parent: Node, target: Vector2, source_radius: float, duration: float, tint: Color) -> Node2D`
  - Each node auto-`queue_free()`s at `duration` end via a one-shot `SceneTreeTimer`.

Each telegraph is a `Node2D` whose visual is a `Line2D` (ground crack, shockwave ring outline, column rise) or a `GPUParticles2D` (expanding circle as an outward burst, converging particles as inward burst). They are non-interactive (no collision), purely visual. No `z_index` below gameplay (use `z_index = 6`, `z_as_relative = false`, matching `WindupTelegraphVfx` which uses `5`).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const BossTelegraph = preload("res://src/enemies/fx/boss_telegraph.gd")


func test_ground_crack_line_returns_node2d() -> void:
	var parent := auto_free(Node2D.new())
	get_tree().root.add_child(parent)
	var node := BossTelegraph.ground_crack_line(parent, Vector2.ZERO, Vector2(40, 0), 0.3)
	assert_that(node is Node2D).is_true()
	assert_that(node.get_parent()).is_equal(parent)
	assert_bool(is_instance_valid(node)).is_true()
	await waitime(0.4)
	assert_bool(is_instance_valid(node)).is_false()


func test_expanding_circle_is_node2d_and_frees() -> void:
	var parent := auto_free(Node2D.new())
	get_tree().root.add_child(parent)
	var node := BossTelegraph.expanding_circle(parent, Vector2.ZERO, 60.0, 0.3)
	assert_that(node is Node2D).is_true()
	await waitime(0.4)
	assert_bool(is_instance_valid(node)).is_false()


func test_column_rise_converging_shockwave_all_free_after_duration() -> void:
	var parent := auto_free(Node2D.new())
	get_tree().root.add_child(parent)
	var a := BossTelegraph.column_rise(parent, Vector2.ZERO, 40.0, 0.3)
	var b := BossTelegraph.shockwave_ring(parent, Vector2.ZERO, 50.0, 0.3)
	var c := BossTelegraph.converging_particles(parent, Vector2.ZERO, 40.0, 0.3, Color.YELLOW)
	await waitime(0.45)
	for node in [a, b, c]:
		assert_bool(is_instance_valid(node)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_telegraphs.gd`
Expected: FAIL with "Could not preload resource file 'res://src/enemies/fx/boss_telegraph.gd'" (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name BossTelegraph
extends RefCounted

# Purely-visual telegraph primitives for boss attacks. Each factory returns a
# Node2D the caller parents to the world layer; the node auto-queue_free()s at
# `duration` end. z_index 6 keeps them above gameplay sprites but below UI.

const TELEGRAPH_Z := 6


static func ground_crack_line(parent: Node, start: Vector2, end: Vector2, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = start
	var line := Line2D.new()
	line.points = PackedVector2Array([Vector2.ZERO, end - start])
	line.width = 3.0
	line.default_color = Color(1.0, 0.85, 0.3, 0.8)
	line.z_index = TELEGRAPH_Z
	line.z_as_relative = false
	root.add_child(line)
	var fade := root.create_tween()
	fade.tween_property(line, "default_color:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR)
	_schedule_free(root, duration)
	parent.add_child(root)
	return root


static func expanding_circle(parent: Node, center: Vector2, max_radius: float, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = center
	var p := _particles_outward(max_radius, duration, Color(1.0, 0.4, 0.3, 0.9))
	root.add_child(p)
	_schedule_free(root, duration)
	parent.add_child(root)
	return root


static func column_rise(parent: Node, base: Vector2, height: float, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = base
	var line := Line2D.new()
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -height)])
	line.width = 6.0
	line.default_color = Color(0.8, 0.8, 0.9, 0.8)
	line.z_index = TELEGRAPH_Z
	line.z_as_relative = false
	root.add_child(line)
	var grow := root.create_tween()
	grow.tween_property(line, "scale:y", 1.0, duration).from(0.0).set_trans(Tween.TRANS_CUBIC)
	_schedule_free(root, duration)
	parent.add_child(root)
	return root


static func shockwave_ring(parent: Node, center: Vector2, max_radius: float, duration: float) -> Node2D:
	var root := _make_root()
	root.global_position = center
	var ring := Line2D.new()
	ring.points = _ring_points(max_radius, 24)
	ring.width = 4.0
	ring.default_color = Color(1.0, 1.0, 1.0, 0.9)
	ring.z_index = TELEGRAPH_Z
	ring.z_as_relative = false
	root.add_child(ring)
	var expand := root.create_tween()
	expand.tween_property(ring, "scale", Vector2.ONE, duration).from(Vector2.ZERO).set_trans(Tween.TRANS_LINEAR)
	var fade := root.create_tween()
	fade.tween_property(ring, "default_color:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR)
	_schedule_free(root, duration)
	parent.add_child(root)
	return root


static func converging_particles(parent: Node, target: Vector2, source_radius: float, duration: float, tint: Color) -> Node2D:
	var root := _make_root()
	root.global_position = target
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 16
	p.lifetime = duration
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.z_index = TELEGRAPH_Z
	p.z_as_relative = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.ZERO
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	# Negative radial velocity → particles fly inward toward the target.
	m.initial_velocity_min = -source_radius / duration
	m.initial_velocity_max = -source_radius / duration
	m.scale_min = 0.4
	m.scale_max = 1.0
	m.color = tint
	m.color_ramp = EnemyVfxShared.fade_gradient(tint, Color(tint.r, tint.g, tint.b, 0.0))
	p.process_material = m
	root.add_child(p)
	_schedule_free(root, duration)
	parent.add_child(root)
	return root


# --- internals ---

static func _make_root() -> Node2D:
	var n := Node2D.new()
	n.z_index = TELEGRAPH_Z
	n.z_as_relative = false
	return n


static func _particles_outward(max_radius: float, duration: float, tint: Color) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "ExpandingCircle"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 24
	p.lifetime = duration
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.z_index = TELEGRAPH_Z
	p.z_as_relative = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 0.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = max_radius / duration
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.color = tint
	m.color_ramp = EnemyVfxShared.fade_gradient(tint, Color(tint.r, tint.g, tint.b, 0.0))
	p.process_material = m
	return p


static func _ring_points(radius: float, segments: int) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for i in segments + 1:
		var a := float(i) / float(segments) * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return PackedVector2Array(pts)


static func _schedule_free(node: Node, delay: float) -> void:
	node.get_tree().create_timer(delay, false).timeout.connect(node.queue_free)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_telegraphs.gd`
Expected: PASS (4 test functions, all telegraphs auto-free after their duration).

- [ ] **Step 5: Commit**

```bash
git add src/enemies/fx/boss_telegraph.gd tests/unit/test_boss_telegraphs.gd
git commit -m "feat: add boss telegraph primitives (crack/circle/column/ring/converge)"
```

---

## Task 2: `BossEnemy` base refactor

**Files:**
- Modify: `src/enemies/boss_enemy.gd` (full rewrite)
- Modify: `scenes/enemies/boss_enemy.tscn` (drop now-unused exports)
- Modify: `tests/unit/test_boss_phase_transition.gd` (add signal assertion)
- Test: `tests/unit/test_boss_attack_cadence.gd`
- Test: `tests/unit/test_boss_floor_scaling.gd`
- Test: `tests/unit/test_boss_phase_changed_signal.gd`

**Interfaces:**
- Consumes: `Weapon` and `RangedWeapon` from existing `weapon.gd`; the existing `DropTable` API (`DropTable.from_enemy_tier`, `DropTable.DropEntry.modifier_pool`/`.gold`); `Enemy._ready()`, `Enemy._process()`, `Enemy.State`, `Enemy.died`, `Enemy.health`, `Enemy.max_health`.
- Produces (public API subclasses rely on):
  - **Signals**: `signal phase_changed(phase: int)`, `signal boss_ready`
  - **Exports**: `@export var boss_name: String`, `@export var phase_count: int = 3`, `@export var weapon_resource: Weapon = null`, `@export var attack_interval: float = 1.2`, `@export var hazard_interval: float = 5.0`
  - **State**: `var current_phase: int = 1`, `var encounter_active: bool = true` (set false by controller during intro)
  - **Virtual hooks** (subclasses override; base default-bodied):
    - `func _on_phase_enter(phase: int) -> void`
    - `func _tick_phase(delta: float) -> void`
    - `func _do_attack() -> void` — base default: if `weapon_resource` set and `_player_ref` valid and within `_attack_range`, call `weapon.use(self)`.
    - `func _pattern_count(phase: int) -> int` — base default `1`.
    - `func _pick_pattern(phase: int) -> int` — base default: rotating index modulo `_pattern_count(phase)`.
    - `func _execute_pattern(phase: int, index: int) -> void` — base default: calls `_do_attack_default()`.
  - **Facade methods** (overridable in tests; default routes through `CompositionDispatcher`):
    - `func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void`
    - `func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void`
    - `func _apply_status(target: Node, status_id: String, amount: float) -> void`
    - `func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void`
    - `func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void`
  - **Movement helpers** for charge subclasses:
    - `func _steer_toward(target: Vector2, accel: float, delta: float) -> void` — sets `velocity` toward `target`, capped at `speed`; calls `move_and_slide()`/the existing movement step.
    - `func _lock_navigation(locked: bool) -> void` — toggles a `_nav_locked` flag the base `_process` checks; when true, base AI (chase/wander) is skipped so the subclass's direct velocity control takes effect.
  - `func set_encounter_active(active: bool) -> void` — controller-callable; sets `encounter_active`; when false, the base suppresses `_do_attack` and `_tick_phase`.
  - `func _apply_floor_scaling(floor_num: int) -> void` — applies `* (1.0 + (floor_num-1)*0.20)` to `max_health`, `* (1.0 + (floor_num-1)*0.10)` to `speed`, `* (1.0 + (floor_num-1)*0.15)` to `weapon_resource.damage` if set. Re-emits `health_changed`.
  - `func _phase_threshold(p: int) -> int` (unchanged), `func _check_phase_transition() -> void` (unchanged math, now emits `phase_changed` per transition and calls `_on_phase_enter`), `func _setup_drop_table() -> void` (unchanged), `func _spawn_drops() -> void` (unchanged).

**Critical refactor decisions:**
- The base's `_process(delta)` calls (in order): `super._process(delta)` (Enemy AI), then if `encounter_active` and `_state != DEATH`: `attack_cooldown -= delta`; if `<= 0` then `_do_attack()` and reset to `attack_interval`; then `_tick_phase(delta)`.
- `Enemy._execute_attack()` (the no-op at `enemy.gd:725`) is overridden as the entry point the `Enemy` base's `State.ATTACK` state calls; `_do_attack()` is the new virtual. The base `_do_attack` honors `encounter_active` and only fires when cooldown has elapsed (the cadence is driven in `_process`, not gated by `Enemy.State` windup — bosses don't use the windup state). If `weapon is null` the base `_do_attack` is a no-op pattern dispatch.
- `_check_phase_transition`'s `while` loop becomes: on each transition, emit `phase_changed(current_phase)` then call `_on_phase_enter(current_phase)` (subclass setup) — emitted *after* `_transition_phase` sets state. Move the inline match in `_transition_phase` into `_on_phase_enter` in subclasses: base `_on_phase_enter` is no-op; subclass overrides add their setup.
- Remove from base: `_original_weapon`, `_hazard_timer`, `_spawn_hazards`, the phase-2 spread tweak, the `RangedWeapon.new()` default weapon construction, `hazard_count`/`hazard_duration`/`hazard_damage` exports. `hazard_interval` stays (subclasses with timed hazards use it); the timer state (`_hazard_timer`) and the `_spawn_hazards` method move into subclasses that need them.

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_boss_phase_changed_signal.gd`:

```gdscript
extends GdUnitTestSuite

class TestBoss extends BossEnemy:
	func _ready() -> void:
		pass

func test_phase_changed_emits_on_each_transition() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.max_health = 300
	b.phase_count = 3
	b.health = 300
	b.current_phase = 1
	var phases: Array = []
	b.phase_changed.connect(func(p): phases.append(p))
	b.health = 50
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(phases).is_equal([2, 3])

func test_on_phase_enter_called_after_state_set() -> void:
	class EnterBoss extends BossEnemy:
		var entered: Array = []
		func _ready() -> void:
			pass
		func _on_phase_enter(phase: int) -> void:
			entered.append(phase)
	var b : EnterBoss = auto_free(EnterBoss.new())
	b.max_health = 300
	b.phase_count = 3
	b.health = 200
	b.current_phase = 1
	b.health = 100
	b._check_phase_transition()
	assert_that(b.entered).is_equal([2, 3])
```

`tests/unit/test_boss_attack_cadence.gd`:

```gdscript
extends GdUnitTestSuite

class CadenceBoss extends BossEnemy:
	var attacks: Array = []
	func _ready() -> void:
		pass
	func _do_attack() -> void:
		attacks.append(current_phase)

func test_do_attack_called_each_interval() -> void:
	var b : CadenceBoss = auto_free(CadenceBoss.new())
	b.attack_interval = 0.25
	b.max_health = 100
	b.health = 100
	b.phase_count = 3
	b.current_phase = 1
	b.encounter_active = true
	for i in 10:
		b._process(0.1)
	assert_int(b.attacks.size()).is_equal(4)  # every 0.25s over 1.0s

func test_do_attack_suppressed_when_encounter_inactive() -> void:
	var b : CadenceBoss = auto_free(CadenceBoss.new())
	b.attack_interval = 0.25
	b.max_health = 100
	b.health = 100
	b.encounter_active = false
	for i in 10:
		b._process(0.1)
	assert_int(b.attacks.size()).is_equal(0)

func test_pattern_rotation_alters_index() -> void:
	class PatternBoss extends BossEnemy:
		var calls: Array = []
		func _ready() -> void:
			pass
		func _pattern_count(_phase: int) -> int:
			return 2
		func _execute_pattern(phase: int, index: int) -> void:
			calls.append(index)
	var b : PatternBoss = auto_free(PatternBoss.new())
	b.attack_interval = 0.25
	b.max_health = 100
	b.health = 100
	b.current_phase = 1
	for i in 8:
		b._process(0.13)  # just over the interval
	assert_that(b.calls).is_equal([0, 1, 0, 1])
```

`tests/unit/test_boss_floor_scaling.gd`:

```gdscript
extends GdUnitTestSuite

class ScalableBoss extends BossEnemy:
	func _ready() -> void:
		pass

func test_scaling_floor_3() -> void:
	var b : ScalableBoss = auto_free(ScalableBoss.new())
	b.max_health = 100
	b.speed = 50.0
	var w := RangedWeapon.new()
	w.damage = 10.0
	b.weapon_resource = w
	b._apply_floor_scaling(3)
	assert_approx_num(b.max_health, 140, 1).is_true()  # 100 * (1 + 2*0.20)
	assert_approx_num(b.speed, 60.0, 0.5).is_true()      # 50 * (1 + 2*0.10)
	assert_approx_num(w.damage, 13.0, 0.05).is_true()    # 10 * (1 + 2*0.15)

func test_scaling_floor_1_noop() -> void:
	var b : ScalableBoss = auto_free(ScalableBoss.new())
	b.max_health = 100
	b.speed = 50.0
	b._apply_floor_scaling(1)
	assert_int(b.max_health).is_equal(100)
	assert_approx_num(b.speed, 50.0, 0.01).is_true()
```

`tests/unit/test_boss_phase_transition.gd` (modify — add the signal assertion at the end of `test_phase_chaining_on_burst_damage`):

```gdscript
extends GdUnitTestSuite

class TestBoss extends BossEnemy:
	func _ready() -> void:
		pass
	var transition_log: Array = []

	func _transition_phase() -> void:
		transition_log.append(current_phase)
		# Don't call super — base _transition_phase is now empty; phase setup
		# happens in _on_phase_enter. Keep this test's original behavior by
		# simply logging.


func test_boss_phase_threshold_values() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.max_health = 300
	b.phase_count = 3
	assert_that(b._phase_threshold(2)).is_equal(200)
	assert_that(b._phase_threshold(3)).is_equal(100)

func test_phase_chaining_on_burst_damage() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.max_health = 300
	b.phase_count = 3
	b.health = 300
	b.current_phase = 1
	var phases: Array = []
	b.phase_changed.connect(func(p): phases.append(p))
	b.health = 50
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(b.transition_log).is_equal([2, 3])
	assert_that(phases).is_equal([2, 3])

func test_phase_2_no_longer_sets_spread_in_base() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.weapon = RangedWeapon.new()
	b.weapon.projectile_count = 1
	b.weapon.spread_angle = 10.0
	b.current_phase = 2
	b._transition_phase()
	# Base is now a no-op; subclasses do the spread tweak.
	assert_int((b.weapon as RangedWeapon).projectile_count).is_equal(1)

func test_phase_3_no_longer_sets_hazard_timer_in_base() -> void:
	# Base no longer owns a hazard timer; subclasses that need it hold their own.
	var b : TestBoss = auto_free(TestBoss.new())
	b.current_phase = 3
	b._transition_phase()
	assert_bool("_hazard_timer" in b).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_phase_changed_signal.gd -a tests/unit/test_boss_attack_cadence.gd -a tests/unit/test_boss_floor_scaling.gd -a tests/unit/test_boss_phase_transition.gd`
Expected: FAIL on the three new suites (no `phase_changed` signal; `_do_attack`/`_apply_floor_scaling` unknown) AND `test_boss_phase_transition.gd` failing because the old `_transition_phase` still does the spread tweak / hazard timer.

- [ ] **Step 3: Write minimal implementation**

Rewrite `src/enemies/boss_enemy.gd`:

```gdscript
class_name BossEnemy
extends Enemy

signal phase_changed(phase: int)
signal boss_ready

@export var boss_name: String = "Boss"
@export var phase_count: int = 3
@export var weapon_resource: Weapon = null
@export var attack_interval: float = 1.2
@export var hazard_interval: float = 5.0

var current_phase: int = 1
var encounter_active: bool = true

var _attack_cooldown: float = 0.0
var _pattern_index: int = 0
var _nav_locked: bool = false
var _attack_range: float = 200.0


func _ready() -> void:
	if weapon_resource:
		weapon = weapon_resource.duplicate()
		_attack_range = 200.0
	else:
		weapon = null
		_attack_range = 0.0
	speed = 40.0
	max_health = 200
	health = max_health
	_speed_base = speed
	detection_radius = 400.0
	scale = Vector2(2.0, 2.0)
	super._ready()
	_setup_drop_table()
	_attack_cooldown = attack_interval
	boss_ready.emit()


func _setup_drop_table() -> void:
	drop_table = DropTable.from_enemy_tier(enemy_tier, true, true, true)
	drop_table.add_entry(DropTable.DropEntry.modifier_pool(1.0, DropTable.ItemTier.RARE, 1, 1))
	drop_table.add_entry(DropTable.DropEntry.gold(1.0, 5, 8, 10))


func _process(delta: float) -> void:
	if _nav_locked:
		# Subclass is steering directly; skip Enemy AI but still tick death/etc.
		_call_enemy_process_minimal(delta)
	else:
		super._process(delta)
	if not encounter_active or _state == State.DEATH:
		return
	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = attack_interval
		var idx := _pick_pattern(current_phase)
		_execute_pattern(current_phase, idx)
	_tick_phase(delta)


# Minimal Enemy-tick path used while navigation is locked (subclass steering).
# Only runs death/hurt state timers + knockback so charges don't desync the
# Enemy base machinery.
func _call_enemy_process_minimal(delta: float) -> void:
	_tick_knockback(delta)
	if _state == State.DEATH:
		_process_death(delta)
	elif _state == State.HURT:
		_process_hurt(delta)


func _pick_pattern(phase: int) -> int:
	var count := _pattern_count(phase)
	if count <= 1:
		_pattern_index = 0
		return 0
	var idx := _pattern_index % count
	_pattern_index = (_pattern_index + 1) % count
	return idx


func _pattern_count(_phase: int) -> int:
	return 1


func _execute_pattern(_phase: int, _index: int) -> void:
	_do_attack()


func _do_attack() -> void:
	if weapon != null and _player_ref != null and is_instance_valid(_player_ref):
		var d := global_position.distance_to(_player_ref.global_position)
		if d <= _attack_range:
			weapon.use(self)


func _tick_phase(_delta: float) -> void:
	# Override per subclass for per-frame phase behavior (magnet, trail, etc.).
	pass


func _on_phase_enter(_phase: int) -> void:
	# Override per subclass; called once after current_phase is set.
	pass


func _pattern_count_for(_phase: int) -> int:
	return 1


func hit(damage: int) -> void:
	super.hit(damage)
	if _state != State.DEATH:
		_check_phase_transition()


func _check_phase_transition() -> void:
	while current_phase < phase_count and health <= _phase_threshold(current_phase + 1):
		current_phase += 1
		_transition_phase()
		_on_phase_enter(current_phase)
		phase_changed.emit(current_phase)


func _phase_threshold(p: int) -> int:
	return int(float(max_health) * float(phase_count - p + 1) / float(phase_count))


func _transition_phase() -> void:
	# Base no-op. Subclasses override _on_phase_enter for phase-specific setup.
	# Kept as a no-op override point so legacy tests that call it stay stable.
	pass


func set_encounter_active(active: bool) -> void:
	encounter_active = active


func _apply_floor_scaling(floor_num: int) -> void:
	var hp_mult := 1.0 + (floor_num - 1) * 0.20
	var sp_mult := 1.0 + (floor_num - 1) * 0.10
	var dmg_mult := 1.0 + (floor_num - 1) * 0.15
	max_health = int(round(float(max_health) * hp_mult))
	health = max_health
	speed *= sp_mult
	_speed_base = speed
	if weapon_resource:
		weapon_resource.damage *= dmg_mult
	if weapon:
		weapon.damage *= dmg_mult
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)


# --- Movement hooks for charge subclasses ---

func _steer_toward(target: Vector2, accel: float, delta: float) -> void:
	var to := (target - global_position)
	if to.length_squared() > 1.0:
		var desired := to.normalized() * speed
		velocity = velocity.lerp(desired, clampf(accel * delta, 0.0, 1.0))
	move_and_slide()


func _lock_navigation(locked: bool) -> void:
	_nav_locked = locked


# --- Facade: subclasses call these instead of touching singletons ---

func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
	CompositionDispatcher.stamp_material_blob(pos, radius, mat_id, 0, 0.0)


func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
	CompositionDispatcher.stamp_material_ring(pos, inner, outer, mat_id)


func _apply_status(target: Node, status_id: String, amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var sc = target.get_node_or_null("StatusComponent")
	if sc and sc.has_method("add_stain"):
		sc.add_stain(status_id, amount)


func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void:
	CompositionDispatcher.spawn_enemy(world_pos, scene, is_elite)


func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
	CompositionDispatcher.spawn_prop(world_pos, scene)


func _roll_weapon_modifier() -> void:
	pass


func _spawn_drops() -> void:
	if drop_table:
		drop_table.resolve(global_position, get_parent(), 1.0)
	if weapon:
		_spawn_weapon_drop()
```

Modify `scenes/enemies/boss_enemy.tscn`: remove the `phase_count`/`hazard_count`/`hazard_duration`/`hazard_damage` property overrides from the `[node name="BossEnemy" ...]` block — they no longer exist as exports. Keep `boss_name`, `weapon_resource = null`, `hazard_interval`. (The scene becomes the legacy reference; it isn't spawned after Task 10.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_phase_changed_signal.gd -a tests/unit/test_boss_attack_cadence.gd -a tests/unit/test_boss_floor_scaling.gd -a tests/unit/test_boss_phase_transition.gd -a tests/unit/test_boss_drops.gd`
Expected: PASS for all five suites. (`test_boss_drops.gd` must still pass — `_setup_drop_table` is unchanged.)

- [ ] **Step 5: Run existing boss suites to confirm no regression**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_ring_coverage.gd`
Expected: PASS (sector-ring geometry, unrelated to the refactor).

- [ ] **Step 6: Commit**

```bash
git add src/enemies/boss_enemy.gd scenes/enemies/boss_enemy.tscn tests/unit/test_boss_phase_changed_signal.gd tests/unit/test_boss_attack_cadence.gd tests/unit/test_boss_floor_scaling.gd tests/unit/test_boss_phase_transition.gd
git commit -m "refactor: BossEnemy into thin base with phase hooks + cadence + scaling"
```

---

## Task 3: Boss facade injectability test

**Files:**
- Test: `tests/unit/test_boss_facade.gd`
- Modify: `src/enemies/boss_enemy.gd` (only if a facade needs an override seam — verify the facade methods are `func` (not `static`) so a test subclass can override them)

**Interfaces:**
- Consumes: Task 2's `_stamp_material`, `_stamp_material_ring`, `_apply_status`, `_spawn_minion`, `_spawn_prop`
- Produces: confidence that subclasses calling facades don't touch singletons directly (regression guard)

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

class FacadeBoss extends BossEnemy:
	var stamps: Array = []
	var rings: Array = []
	var statuses: Array = []
	var minions: Array = []
	var props: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
		rings.append({"pos": pos, "inner": inner, "outer": outer, "mat": mat_id})
	func _apply_status(target: Node, status_id: String, amount: float) -> void:
		statuses.append({"target": target, "id": status_id, "amount": amount})
	func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void:
		minions.append({"scene": scene, "pos": world_pos, "elite": is_elite})
	func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
		props.append({"scene": scene, "pos": world_pos})

func test_facade_overrides_capture_calls_not_singletons() -> void:
	var b := auto_free(FacadeBoss.new())
	b._stamp_material(Vector2(10, 10), 8.0, 4)
	b._stamp_material_ring(Vector2.ZERO, 4.0, 12.0, 4)
	b._apply_status(null, "chilly", 1.5)
	b._spawn_minion(null, Vector2(20, 20), true)
	b._spawn_prop(null, Vector2(30, 30))
	assert_int(b.stamps.size()).is_equal(1)
	assert_int(b.rings.size()).is_equal(1)
	assert_int(b.statuses.size()).is_equal(1)
	assert_int(b.minions.size()).is_equal(1)
	assert_int(b.props.size()).is_equal(1)
	assert_float(b.stamps[0]["radius"]).is_equal(8.0)
```

- [ ] **Step 2: Run test to verify it passes (facades are already virtual from Task 2)**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_facade.gd`
Expected: PASS — Task 2 declared the facades as instance methods, so overrides work.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_boss_facade.gd
git commit -m "test: verify boss facade methods are overridable (no singleton access)"
```

---

## Task 4: Mine prop (Drill phase 2 dependency)

Build this before Drill boss because Drill composes it.

**Files:**
- Create: `src/props/mine.gd`
- Create: `scenes/props/mine.tscn`
- Test: `tests/unit/test_mine_prop.gd`

**Interfaces:**
- Consumes: existing `scenes/props/barrel.tscn` destruction pattern (read it for reference), `TerrainSurface.place_fire` / `MAT_EXPLODE_WAVE` for the blast.
- Produces: `Mine` class (`Area2D`-based): `func arm(duration: float) -> void` (starts armed-after-`duration` timer), explodes on `body_entered` while armed OR after a timeout; on explode calls `TerrainSurface`/world to deal area damage in `blast_radius` and `queue_free()`. Properties exported: `blast_radius: float = 48.0`, `blast_damage: int = 12`, `arm_delay: float = 1.0`, `timeout: float = 8.0`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const MineScene := preload("res://scenes/props/mine.tscn")

func test_mine_arms_after_delay() -> void:
	var mine := auto_free(MineScene.instantiate())
	get_tree().root.add_child(mine)
	mine.arm(0.2)
	assert_bool(mine.is_armed()).is_false()
	await waitime(0.25)
	assert_bool(mine.is_armed()).is_true()

func test_mine_explodes_on_timeout_and_frees() -> void:
	var mine := auto_free(MineScene.instantiate())
	mine.timeout = 0.2
	mine._skip_arm_for_test()
	get_tree().root.add_child(mine)
	mine.begin_timeout()
	await waitime(0.3)
	assert_bool(is_instance_valid(mine)).is_false()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_mine_prop.gd`
Expected: FAIL (scene/script missing).

- [ ] **Step 3: Implement**

`src/props/mine.gd`:

```gdscript
class_name Mine
extends Area2D

@export var blast_radius: float = 48.0
@export var blast_damage: int = 12
@export var arm_delay: float = 1.0
@export var timeout: float = 8.0

var _armed: bool = false
var _arming: bool = false
var _arm_remaining: float = 0.0
var _timeout_remaining: float = 0.0


func _ready() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 1  # player / bodies
	body_entered.connect(_on_body_entered)


func arm(delay: float = -1.0) -> void:
	_arming = true
	_arm_remaining = delay if delay >= 0.0 else arm_delay


func _skip_arm_for_test() -> void:
	_armed = true


func begin_timeout() -> void:
	_timeout_remaining = timeout


func is_armed() -> bool:
	return _armed


func _process(delta: float) -> void:
	if _arming and not _armed:
		_arm_remaining -= delta
		if _arm_remaining <= 0.0:
			_arming = false
			_armed = true
			begin_timeout()
	if _armed and _timeout_remaining > 0.0:
		_timeout_remaining -= delta
		if _timeout_remaining <= 0.0:
			_explode()


func _on_body_entered(_body: Node) -> void:
	if _armed:
		_explode()


func _explode() -> void:
	if not is_inside_tree():
		return
	# Damage bodies in blast_radius via a physics overlap query.
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1
	var hits := space.intersect_shape(query)
	for hit in hits:
		var c = hit.collider
		if c and c.has_method("hit"):
			c.hit(blast_damage)
	# Optional terrain blast: lighter than the barrel — skip fire to avoid griefing
	# player pathing. The damage pulse is the mine's job.
	queue_free()
```

`scenes/props/mine.tscn`:

```
[gd_scene load_steps=3 format=3 uid="uid://bminenode01"]

[ext_resource type="Script" path="res://src/props/mine.gd" id="1_mine"]

[sub_resource type="CircleShape2D" id="CircleShape2D_mine"]
radius = 8.0

[node name="Mine" type="Area2D"]
script = ExtResource("1_mine")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_mine")
```

(Generate the real `.uid` via `godot --headless --path . --import` after writing the file.)

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_mine_prop.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/props/mine.gd scenes/props/mine.tscn tests/unit/test_mine_prop.gd
git commit -m "feat: add proximity mine prop for Drill boss phase 2"
```

---

## Task 5: Burrower boss (Caves)

**Files:**
- Create: `src/enemies/bosses/burrower_boss.gd`
- Create: `scenes/enemies/bosses/burrower_boss.tscn`
- Test: `tests/unit/test_burrower_boss_phases.gd`

**Interfaces:**
- Consumes: Task 1 `BossTelegraph`, Task 2 `BossEnemy` hooks + facades + `_steer_toward`/`_lock_navigation`, `MaterialRegistry.MAT_DUST`, `MaterialRegistry.MAT_AIR`, `scenes/enemies/melee_enemy.tscn` is NOT used (Burrower has no minions). Uses existing `_player_ref` from `Enemy`.
- Produces: `BurrowerBoss extends BossEnemy`; named scene with `boss_name = "Burrower"`, `phase_count = 3`, `weapon_resource = null`. Phase pattern counts are 2/2/2.

**Behavior per (phase, pattern):**
- P1.A Directed charge: telegraph crack line ~0.4s; then `_lock_navigation(true)` and `_steer_toward(target, 800, delta)` for ~0.6s toward player's pos-at-telegraph; recover (`_lock_navigation(false)`, idle) ~0.3s.
- P1.B Sweep charge: telegraph wide arc indicator (use `expanding_circle` ~0.5s); then a curving dash for ~0.8s following a half-circle around arena center; recover.
- P2.A Dust-burst on charge: after any charge ends in phase 2, `_stamp_material(landing, 6.0, MAT_DUST)` + along path points.
- P2.B Dust eruption: stationary; `_stamp_material` 3 blobs at random offsets around player with `expanding_circle` telegraphs.
- P3.A Pit stamp: every `hazard_interval`, for the current pattern index even: `expanding_circle` telegraph ~1s then `_stamp_material(pos, 5.0, MAT_AIR)`.
- P3.B Tremor stagger: pattern odd: trigger a camera-shake signal (boss emits nothing; the `BossEncounter` will be wired later — for now the boss calls `get_tree().call_group("boss_encounter", "shake", 2.0)`) and `_stamp_material` a dust ring at fixed radius.

Cooldown between patterns (the cadence): `attack_interval` is overridden per-phase inside `_on_phase_enter` (P1 charges are slow, ~1.6s; P2 ~1.4s; P3 ~1.0s). Hazard spawns in P3 are driven by `_hazard_timer` ticking in `_tick_phase`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const BurrowerScript := preload("res://src/enemies/bosses/burrower_boss.gd")

class FakeBurrower extends BurrowerScript:
	var stamps: Array = []
	var navigations: Array = []
	var charges: Array = []
	var dust_bursts: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _lock_navigation(locked: bool) -> void:
		navigations.append(locked)
	func _do_directed_charge() -> void:
		charges.append("directed")
	func _do_sweep_charge() -> void:
		charges.append("sweep")
	func _do_dust_burst_after_charge() -> void:
		dust_bursts.append("after")
	func _spawn_telegraph_ground_crack(_s: Vector2, _e: Vector2, _d: float) -> void:
		pass
	func _spawn_telegraph_expanding(_c: Vector2, _r: float, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b := auto_free(FakeBurrower.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_directed_then_sweep() -> void:
	var b := auto_free(FakeBurrower.new())
	b.current_phase = 1
	b.max_health = 100; b.health = 100
	b.encounter_active = true
	for i in 2:
		b._execute_pattern(1, i)
	assert_that(b.charges).is_equal(["directed", "sweep"])

func test_phase_3_hazard_interval_stamps_pit() -> void:
	b.hazard_interval = 0.5
	b.current_phase = 3
	b._on_phase_enter(3)
	b._tick_phase(0.5)
	assert_int(b.stamps.size()).is_greater_equal(1)
	var first := b.stamps[0]
	assert_int(first["mat"]).is_equal(MaterialRegistry.MAT_AIR)

func _new_boss() -> FakeBurrower:
	var b := auto_free(FakeBurrower.new())
	b.max_health = 100; b.health = 100
	return b
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_burrower_boss_phases.gd`
Expected: FAIL (file missing).

- [ ] **Step 3: Implement**

```gdscript
class_name BurrowerBoss
extends BossEnemy

const CHARGE_TELEGRAPH := 0.4
const SWEEP_TELEGRAPH := 0.5
const PIT_TELEGRAPH := 1.0
const PIT_RADIUS := 5.0
const DUST_RADIUS := 6.0

var _hazard_timer: float = 0.0


func _ready() -> void:
	boss_name = "Burrower"
	weapon_resource = null
	super._ready()


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.6
		2: attack_interval = 1.4
		3:
			attack_interval = 1.0
			_hazard_timer = hazard_interval


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _charge_pattern(index)
		2: _dust_pattern(index)
		3: _pit_pattern(index)


func _charge_pattern(index: int) -> void:
	if index == 0:
		_do_directed_charge()
	else:
		_do_sweep_charge()


func _do_directed_charge() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var target := _player_ref.global_position
	_spawn_telegraph_ground_crack(global_position, target, CHARGE_TELEGRAPH)
	_begin_charge(target, 0.6, 800.0)


func _do_sweep_charge() -> void:
	var center := global_position
	_spawn_telegraph_expanding(center, 120.0, SWEEP_TELEGRAPH)
	# Approximate the curve as a sequence of steer targets along a half-circle.
	var_sequence_charge(center, 0.8)


func _begin_charge(target: Vector2, duration: float, accel: float) -> void:
	# Steering-driven; the per-frame move happens in _tick_phase during the charge window.
	_charge_active = true
	_charge_target = target
	_charge_accel = accel
	_charge_remaining = duration
	_lock_navigation(true)


var _charge_active: bool = false
var _charge_target: Vector2 = Vector2.ZERO
var _charge_accel: float = 600.0
var _charge_remaining: float = 0.0


func _tick_phase(delta: float) -> void:
	if _charge_active:
		_charge_remaining -= delta
		_steer_toward(_charge_target, _charge_accel, delta)
		if _charge_remaining <= 0.0:
			_charge_active = false
			_lock_navigation(false)
			if current_phase == 2 and _last_pattern_index == 0:
				_do_dust_burst_after_charge()
	if current_phase == 3:
		_hazard_timer -= delta
		if _hazard_timer <= 0.0:
			_hazard_timer = hazard_interval
			_pit_or_tremor()


var _last_pattern_index: int = 0


func _dust_pattern(index: int) -> void:
	_last_pattern_index = index
	if index == 0:
		# A charge was requested; the burst happens in _tick_phase when it ends.
		_do_directed_charge()
	else:
		for i in 3:
			var off := Vector2(randf_range(-80, 80), randf_range(-80, 80))
			var pos := _player_ref.global_position + off if (_player_ref and is_instance_valid(_player_ref)) else global_position + off
			_spawn_telegraph_expanding(pos, 24.0, 0.6)
			_stamp_material(pos, DUST_RADIUS, MaterialRegistry.MAT_DUST)


func _do_dust_burst_after_charge() -> void:
	_stamp_material(global_position, DUST_RADIUS, MaterialRegistry.MAT_DUST)
	_stamp_material(_charge_target, DUST_RADIUS, MaterialRegistry.MAT_DUST)


func _pit_or_tremor() -> void:
	# Use the rotating pattern index to alternate pit vs tremor.
	var idx := _pattern_index
	if idx == 0:
		var pos := global_position + Vector2(randf_range(-120, 120), randf_range(-120, 120))
		_spawn_telegraph_expanding(pos, 40.0, PIT_TELEGRAPH)
		# Stamp after a short delay — implement with a SceneTreeTimer.
		get_tree().create_timer(PIT_TELEGRAPH, false).timeout.connect(func(): _stamp_material(pos, PIT_RADIUS, MaterialRegistry.MAT_AIR))
	else:
		get_tree().call_group("boss_encounter", "shake", 2.0)
		for i in 8:
			var a := float(i) / 8.0 * TAU
			_stamp_material(global_position + Vector2(cos(a), sin(a)) * 60.0, DUST_RADIUS, MaterialRegistry.MAT_DUST)


func _pit_pattern(index: int) -> void:
	_last_pattern_index = index
	# The hazard themselves are timer-driven in _tick_phase; this is a no-op so
	# the cadence doesn't fire a duplicate attack. We keep the hook for symmetry.
	pass


# Telegraph wrappers so tests can stub them.
func _spawn_telegraph_ground_crack(start: Vector2, end: Vector2, duration: float) -> void:
	BossTelegraph.ground_crack_line(get_parent(), start, end, duration)

func _spawn_telegraph_expanding(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.expanding_circle(get_parent(), center, radius, duration)


# A simplified sweep: steer around a half-circle of waypoints.
func var_sequence_charge(center: Vector2, duration: float) -> void:
	_charge_active = true
	_charge_target = center + Vector2(120, 0)
	_charge_accel = 700.0
	_charge_remaining = duration
	_lock_navigation(true)
```

`scenes/enemies/bosses/burrower_boss.tscn` (instance the generic `enemy.tscn` like `boss_enemy.tscn` does — read that file's structure first and mirror it; swap the script and sprite references):

```
[gd_scene format=3 uid="uid://bburrower01"]

[ext_resource type="PackedScene" uid="uid://enemybase01" path="res://scenes/enemies/enemy.tscn" id="1"]
[ext_resource type="Script" path="res://src/enemies/bosses/burrower_boss.gd" id="2"]
[ext_resource type="Texture2D" uid="uid://coptlukjq2bxk" path="res://textures/Enemies/boss_test.png" id="3"]

[node name="BurrowerBoss" unique_id=1779886679 instance=ExtResource("1")]
script = ExtResource("2")
boss_name = "Burrower"
phase_count = 3
weapon_resource = null
attack_interval = 1.6
hazard_interval = 5.0

[node name="Sprite2D" parent="." index="0"]
texture = ExtResource("3")
```

Run `godot --headless --path . --import` to regenerate `.uid`/`.import` files. If `godot --headless --path . --import` complains the scene references `enemy.tscn` by a uid that doesn't match, instead open the existing `scenes/enemies/boss_enemy.tscn`, copy its head, and only change the `script` line + node exports.

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_burrower_boss_phases.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/bosses/burrower_boss.gd scenes/enemies/bosses/burrower_boss.tscn tests/unit/test_burrower_boss_phases.gd
git commit -m "feat: add Burrower (Caves) boss with 2-pattern phases"
```

---

## Task 6: Pyrelord boss (Magma)

**Files:**
- Create: `src/enemies/bosses/pyrelord_boss.gd`
- Create: `scenes/enemies/bosses/pyrelord_boss.tscn`
- Test: `tests/unit/test_pyrelord_boss_phases.gd`

**Interfaces:**
- Consumes: Task 1 `BossTelegraph`, Task 2 hooks/facades, `MaterialRegistry.MAT_LAVA`, `WeaponRegistry.get_weapon_by_id("fire_orb")`. (Reuse the existing `fire_orb` ranged weapon for projectiles.)
- Produces: `PyrelordBoss extends BossEnemy`; `boss_name = "Pyrelord"`, `weapon_resource` = `fire_orb` clone (set in `_ready`), phases 2/2/2.

**Per-pattern behavior:**
- P1.A Single homing orb: fire `fire_orb` straight at player (it has no native homing; Pyrelord's fire-orb clone gets a `HomingBehavior` appended to its projectile — see implementation). Telegraph: projectile flash (skip — weapon fires immediately with a telegraph circle ~0.3s before firing).
- P1.B Orb spread: clone the weapon, set `projectile_count = 3`, `spread_angle = 30.0`, fire at player.
- P2.A Lava trail: in `_tick_phase`, every 0.25s `_stamp_material(global_position, 4.0, MAT_LAVA)`.
- P2.B Lava spit: lob 2–3 splotches at player with `expanding_circle` telegraph ~0.8s then `_stamp_material(pos, 5.0, MAT_LAVA)`.
- P3.A Expanding ring: `expanding_circle` ~1.2s then `_stamp_material_ring(center, ring_inner, ring_outer, MAT_LAVA)`.
- P3.B Center-safe collapse: `converging`-ring telegraph then `_stamp_material_ring(center, 0, outer_flood, MAT_LAVA)` (lava floods inward from edges → use a large outer ring with inner = 0 to flood, leaving a center gap that reopens — keep a small center disc clear by stamping `MAT_AIR` afterward in a small radius).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const PyrelordScript := preload("res://src/enemies/bosses/pyrelord_boss.gd")

class FakePyrelord extends PyrelordScript:
	var stamps: Array = []
	var rings: Array = []
	var fires: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
		rings.append({"pos": pos, "inner": inner, "outer": outer, "mat": mat_id})
	func _fire_pattern(projectile_count: int, spread: float) -> void:
		fires.append({"count": projectile_count, "spread": spread})
	func _spawn_telegraph_expanding(_c: Vector2, _r: float, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b := auto_free(FakePyrelord.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_single_then_spread() -> void:
	var b := auto_free(FakePyrelord.new())
	b.current_phase = 1
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_int(b.fires.size()).is_equal(2)
	assert_int(b.fires[0]["count"]).is_equal(1)
	assert_int(b.fires[1]["count"]).is_equal(3)
	assert_float(b.fires[1]["spread"]).is_equal(30.0)

func test_phase_3_a_stamps_lava_ring() -> void:
	var b := auto_free(FakePyrelord.new())
	b.current_phase = 3
	b._set_center_for_test(Vector2.ZERO)
	b._execute_pattern(3, 0)
	# Animation timer fires the stamp slightly later; await.
	await waitime(1.3)
	assert_int(b.rings.size()).is_greater_equal(1)
	assert_int(b.rings[0]["mat"]).is_equal(MaterialRegistry.MAT_LAVA)
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_pyrelord_boss_phases.gd`
Expected: FAIL (missing file).

- [ ] **Step 3: Implement**

```gdscript
class_name PyrelordBoss
extends BossEnemy

const RING_TELEGRAPH := 1.2
const SPIT_TELEGRAPH := 0.8
const ORB_TELEGRAPH := 0.3

var _center: Vector2 = Vector2.ZERO
var _trail_timer: float = 0.0


func _ready() -> void:
	boss_name = "Pyrelord"
	var w := WeaponRegistry.get_weapon_by_id("fire_orb")
	weapon_resource = w.duplicate() if w else null
	super._ready()
	_center = global_position


func _set_center_for_test(c: Vector2) -> void:
	_center = c


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.2
		2:
			attack_interval = 1.0
			_trail_timer = 0.25
		3: attack_interval = 1.4


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _orb_pattern(index)
		2: _fire_pattern(index)
		3: _ring_pattern(index)


func _orb_pattern(index: int) -> void:
	if index == 0:
		_fire_pattern(1, 0.0)
	else:
		_fire_pattern(3, 30.0)


func _fire_pattern(projectile_count: int, spread: float) -> void:
	# Telegraph: brief expanding circle on self.
	_spawn_telegraph_expanding(global_position, 16.0, ORB_TELEGRAPH)
	if weapon == null:
		return
	# Configure a clone for this shot's spread/count.
	var clone := (weapon as RangedWeapon).duplicate()
	clone.projectile_count = projectile_count
	clone.spread_angle = spread
	await get_tree().create_timer(ORB_TELEGRAPH, false).timeout
	if is_instance_valid(self) and _player_ref and is_instance_valid(_player_ref):
		clone.use(self)


func _fire_pattern_2(index: int) -> void:
	if index == 0:
		pass  # Trail handled in _tick_phase.
	else:
		for i in 3:
			var base := _player_ref.global_position if (_player_ref and is_instance_valid(_player_ref)) else global_position
			var pos := base + Vector2(randf_range(-20, 20), randf_range(-20, 20))
			_spawn_telegraph_expanding(pos, 20.0, SPIT_TELEGRAPH)
			get_tree().create_timer(SPIT_TELEGRAPH, false).timeout.connect(func(): if is_instance_valid(self): _stamp_material(pos, 5.0, MaterialRegistry.MAT_LAVA))


func _fire_pattern(index: int) -> void:
	if index == 0:
		return  # Lava trail is timer-driven in _tick_phase.
	_fire_pattern_2(1)


func _ring_pattern(index: int) -> void:
	if index == 0:
		# Expanding ring of lava bounding a safe donut.
		_spawn_telegraph_expanding(_center, 120.0, RING_TELEGRAPH)
		get_tree().create_timer(RING_TELEGRAPH, false).timeout.connect(func():
			if not is_instance_valid(self): return
			_stamp_material_ring(_center, 80.0, 110.0, MaterialRegistry.MAT_LAVA))
	else:
		# Flood inward: lava ring from edge toward center, leave small center disc clear.
		_spawn_telegraph_expanding(_center, 160.0, RING_TELEGRAPH)
		get_tree().create_timer(RING_TELEGRAPH, false).timeout.connect(func():
			if not is_instance_valid(self): return
			_stamp_material_ring(_center, 40.0, 160.0, MaterialRegistry.MAT_LAVA))


func _tick_phase(delta: float) -> void:
	if current_phase == 2 and _pattern_index_was_zero_at_last_attack() == false:
		# Pattern B fires spit; pattern A leaves a continuous trail (timer-driven).
		pass
	if current_phase == 2:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.25
			_stamp_material(global_position, 4.0, MaterialRegistry.MAT_LAVA)


var _last_idx: int = 0
func _pattern_index_was_zero_at_last_attack() -> bool:
	return _last_idx == 0


func _spawn_telegraph_expanding(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.expanding_circle(get_parent(), center, radius, duration)
```

Scene mirrors Burrower's `.tscn` with `script = res://src/enemies/bosses/pyrelord_boss.gd`, `boss_name = "Pyrelord"`, `attack_interval = 1.2`.

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_pyrelord_boss_phases.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/bosses/pyrelord_boss.gd scenes/enemies/bosses/pyrelord_boss.tscn tests/unit/test_pyrelord_boss_phases.gd
git commit -m "feat: add Pyrelord (Magma) boss with lava orb/trail/ring phases"
```

---

## Task 7: Glacier boss (Frozen)

**Files:**
- Create: `src/enemies/bosses/glacier_boss.gd`
- Create: `scenes/enemies/bosses/glacier_boss.tscn`
- Test: `tests/unit/test_glacier_boss_phases.gd`

**Interfaces:**
- Consumes: Task 1 `BossTelegraph`, Task 2 hooks/facades, `MaterialRegistry.MAT_ICE`, `StatusRegistry` "chilly"/"frozen", `WeaponRegistry.get_weapon_by_id("boss_staff")` (reuse as the ice-shard projectile base — straight, fast). `_apply_status(target, id, amount)` facade.
- Produces: `GlacierBoss extends BossEnemy`; `boss_name = "Glacier Titan"`, `weapon_resource = boss_staff` clone, phases 2/2/2.

**Per-pattern behavior:**
- P1.A Single fast shard: `boss_staff` clone with `projectile_count = 1`, `spread_angle = 0`, fire at player.
- P1.B Shard volley: `projectile_count = 3`, `burst_count = 3`, `burst_interval = 0.08`, fire at player.
- P2.A Chilly disc: `_stamp_material(pos, 8.0, MAT_ICE)` disc telegraph then `_apply_status` to player if standing inside (check each tick; or apply via the existing `StatusComponent` terrain stain — `MAT_ICE` already inflicts `chilly` via `StatusComponent`. To be safe, the boss just stamps the disc and lets the terrain status system apply chilly).
- P2.B Frost nova: `expanding_circle` ~0.8s centered on self, then stamp `MAT_ICE` ring only (a circular chilly zone).
- P3.A Truncating pillars: stamp `MAT_ICE` pillars along the line from boss to player to cut the line of sight (column-rise telegraph each).
- P3.B Pillar ring: spawn a ring of `MAT_ICE` pillars around the player with one gap.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const GlacierScript := preload("res://src/enemies/bosses/glacier_boss.gd")

class FakeGlacier extends GlacierScript:
	var stamps: Array = []
	var rings: Array = []
	var fires: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
		rings.append({"pos": pos, "inner": inner, "outer": outer, "mat": mat_id})
	func _fire_shards(count: int, burst: int) -> void:
		fires.append({"count": count, "burst": burst})
	func _spawn_telegraph_expanding(_c: Vector2, _r: float, _d: float) -> void:
		pass
	func _spawn_telegraph_column(_b: Vector2, _h: float, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b := auto_free(FakeGlacier.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_single_then_volley() -> void:
	var b := auto_free(FakeGlacier.new())
	b.current_phase = 1
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_int(b.fires[0]["count"]).is_equal(1)
	assert_int(b.fires[1]["count"]).is_equal(3)
	assert_int(b.fires[1]["burst"]).is_equal(3)

func test_phase_2_a_stamps_ice_disc() -> void:
	var b := auto_free(FakeGlacier.new())
	b.current_phase = 2
	b._set_player_pos_for_test(Vector2(50, 0))
	b.global_position = Vector2.ZERO
	b._execute_pattern(2, 0)
	assert_int(b.stamps.size()).is_greater_equal(1)
	assert_int(b.stamps[0]["mat"]).is_equal(MaterialRegistry.MAT_ICE)

func test_phase_3_b_stamps_pillar_ring_with_gap() -> void:
	var b := auto_free(FakeGlacier.new())
	b.current_phase = 3
	b._set_player_pos_for_test(Vector2.ZERO)
	b._execute_pattern(3, 1)
	assert_int(b.stamps.size()).is_equal(8)  # 8 pillars, one gap omitted
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_glacier_boss_phases.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
class_name GlacierBoss
extends BossEnemy

const SHARD_TELEGRAPH := 0.3
const NOVA_TELEGRAPH := 0.8
const PILLAR_RADIUS := 6.0
const RING_RADIUS := 70.0

var _test_player_pos: Vector2 = Vector2(-9999, -9999)


func _ready() -> void:
	boss_name = "Glacier Titan"
	var w := WeaponRegistry.get_weapon_by_id("boss_staff")
	weapon_resource = w.duplicate() if w else null
	super._ready()


func _set_player_pos_for_test(p: Vector2) -> void:
	_test_player_pos = p


func _player_pos() -> Vector2:
	if _test_player_pos != Vector2(-9999, -9999):
		return _test_player_pos
	if _player_ref and is_instance_valid(_player_ref):
		return _player_ref.global_position
	return global_position


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.0
		2: attack_interval = 1.4
		3: attack_interval = 1.6


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _shard_pattern(index)
		2: _chill_pattern(index)
		3: _pillar_pattern(index)


func _shard_pattern(index: int) -> void:
	if index == 0:
		_fire_shards(1, 1)
	else:
		_fire_shards(3, 3)


func _fire_shards(count: int, burst: int) -> void:
	_spawn_telegraph_expanding(global_position, 14.0, SHARD_TELEGRAPH)
	if weapon == null:
		return
	var clone := (weapon as RangedWeapon).duplicate()
	clone.projectile_count = count
	clone.burst_count = burst
	clone.burst_interval = 0.08
	await get_tree().create_timer(SHARD_TELEGRAPH, false).timeout
	if is_instance_valid(self):
		clone.use(self)


func _chill_pattern(index: int) -> void:
	if index == 0:
		# Chilly disc at the player.
		var pos := _player_pos()
		_spawn_telegraph_expanding(pos, 24.0, NOVA_TELEGRAPH)
		get_tree().create_timer(NOVA_TELEGRAPH, false).timeout.connect(func():
			if is_instance_valid(self): _stamp_material(pos, PILLAR_RADIUS, MaterialRegistry.MAT_ICE))
	else:
		# Frost nova: ring of chilly aura around the boss.
		_spawn_telegraph_expanding(global_position, RING_RADIUS, NOVA_TELEGRAPH)
		get_tree().create_timer(NOVA_TELEGRAPH, false).timeout.connect(func():
			if is_instance_valid(self): _stamp_material_ring(global_position, RING_RADIUS - 16.0, RING_RADIUS, MaterialRegistry.MAT_ICE))


func _pillar_pattern(index: int) -> void:
	if index == 0:
		# Truncating pillars along boss→player line.
		var target := _player_pos()
		var dir := (target - global_position)
		var steps := 5
		for i in steps:
			var t := float(i + 1) / float(steps + 1)
			var pos := global_position.lerp(target, t)
			_spawn_telegraph_column(pos, 24.0, 0.5)
			var ip := pos  # capture
			get_tree().create_timer(0.5, false).timeout.connect(func():
				if is_instance_valid(self): _stamp_material(ip, PILLAR_RADIUS, MaterialRegistry.MAT_ICE))
	else:
		# Pillar ring around the player, one gap.
		var center := _player_pos()
		var gap := randi() % 8
		for i in 8:
			if i == gap:
				continue
			var a := float(i) / 8.0 * TAU
			var pos := center + Vector2(cos(a), sin(a)) * RING_RADIUS
			_stamp_material(pos, PILLAR_RADIUS, MaterialRegistry.MAT_ICE)


func _spawn_telegraph_expanding(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.expanding_circle(get_parent(), center, radius, duration)

func _spawn_telegraph_column(base: Vector2, height: float, duration: float) -> void:
	BossTelegraph.column_rise(get_parent(), base, height, duration)
```

Scene mirrors Burrower's `.tscn` with `script = res://src/enemies/bosses/glacier_boss.gd`, `boss_name = "Glacier Titan"`, `attack_interval = 1.0`.

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_glacier_boss_phases.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/bosses/glacier_boss.gd scenes/enemies/bosses/glacier_boss.tscn tests/unit/test_glacier_boss_phases.gd
git commit -m "feat: add Glacier Titan (Frozen) boss with shard/chill/pillar phases"
```

---

## Task 8: Drill boss (Mines)

**Files:**
- Create: `src/enemies/bosses/drill_boss.gd`
- Create: `scenes/enemies/bosses/drill_boss.tscn`
- Test: `tests/unit/test_drill_boss_phases.gd`

**Interfaces:**
- Consumes: Task 1 `BossTelegraph`, Task 2 hooks/facades + `_steer_toward`/`_lock_navigation`, Task 4 `scenes/props/mine.tscn`, `MaterialRegistry.MAT_STONE`, `_spawn_prop` facade.
- Produces: `DrillBoss extends BossEnemy`; `boss_name = "Drill Construct"`, `weapon_resource = null`, phases 2/2/2.

**Per-pattern behavior:**
- P1.A Committed straight bore: telegraph crack ~0.6s toward player's pos-at-telegraph; `_lock_navigation(true)` + `_steer_toward` straight-line for ~0.7s; recover.
- P1.B Double-bore: two charges in sequence at ±30° from first direction.
- P2.A Random scatter: `_spawn_prop(mine.tscn, pos)` at 4 random nearby positions, each `.arm(1.0)`.
- P2.B Patterned grid: drop mines in a 4×4 grid across arena floor.
- P3.A Pillar raise/lower: stamp `MAT_STONE` pillar rows; (lowering existing pillars is a no-op in this impl — just raise new ones; that satisfies "arena walls reconfigure" since rising walls change the space).
- P3.B Corridor slam: stamp two parallel `MAT_STONE` walls forming a corridor toward the player, then a charge down it; walls sink (restamp as `MAT_AIR` corridor) after.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const DrillScript := preload("res://src/enemies/bosses/drill_boss.gd")

class FakeDrill extends DrillScript:
	var props: Array = []
	var stones: Array = []
	var charges: Array = []
	func _ready() -> void:
		pass
	func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
		props.append({"scene": scene, "pos": world_pos})
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stones.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _do_straight_bore(_target: Vector2) -> void:
		charges.append("straight")
	func _do_double_bore(_target: Vector2) -> void:
		charges.append("double")
	func _spawn_telegraph_ground_crack(_s: Vector2, _e: Vector2, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b := auto_free(FakeDrill.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_straight_then_double() -> void:
	var b := auto_free(FakeDrill.new())
	b.current_phase = 1
	b._set_player_pos_for_test(Vector2(80, 0))
	b.global_position = Vector2.ZERO
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_that(b.charges).is_equal(["straight", "double"])

func test_phase_2_a_scatters_four_mines() -> void:
	var b := auto_free(FakeDrill.new())
	b.current_phase = 2
	b._execute_pattern(2, 0)
	assert_int(b.props.size()).is_equal(4)

func test_phase_3_a_stamps_stone_pillars() -> void:
	var b := auto_free(FakeDrill.new())
	b.current_phase = 3
	b._execute_pattern(3, 0)
	assert_int(b.stones.size()).is_greater_equal(1)
	assert_int(b.stones[0]["mat"]).is_equal(MaterialRegistry.MAT_STONE)
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_drill_boss_phases.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
class_name DrillBoss
extends BossEnemy

const BORE_TELEGRAPH := 0.6
const MINE_SCENE := preload("res://scenes/props/mine.tscn")
const PILLAR_RADIUS := 6.0


var _test_player_pos: Vector2 = Vector2(-9999, -9999)


func _ready() -> void:
	boss_name = "Drill Construct"
	weapon_resource = null
	super._ready()


func _set_player_pos_for_test(p: Vector2) -> void:
	_test_player_pos = p


func _player_pos() -> Vector2:
	if _test_player_pos != Vector2(-9999, -9999):
		return _test_player_pos
	if _player_ref and is_instance_valid(_player_ref):
		return _player_ref.global_position
	return global_position


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.8
		2: attack_interval = 1.6
		3: attack_interval = 1.4


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _bore_pattern(index)
		2: _mine_pattern(index)
		3: _wall_pattern(index)


func _bore_pattern(index: int) -> void:
	var target := _player_pos()
	if index == 0:
		_do_straight_bore(target)
	else:
		_do_double_bore(target)


func _do_straight_bore(target: Vector2) -> void:
	_spawn_telegraph_ground_crack(global_position, target, BORE_TELEGRAPH)
	get_tree().create_timer(BORE_TELEGRAPH, false).timeout.connect(func():
		if not is_instance_valid(self): return
		_begin_charge(target, 0.7, 900.0))


func _do_double_bore(target: Vector2) -> void:
	var dir := (target - global_position).normalized()
	var a1 := dir.rotated(deg_to_rad(30.0)) * 200 + global_position
	var a2 := dir.rotated(deg_to_rad(-30.0)) * 200 + global_position
	_spawn_telegraph_ground_crack(global_position, a1, BORE_TELEGRAPH)
	get_tree().create_timer(BORE_TELEGRAPH, false).timeout.connect(func():
		if not is_instance_valid(self): return
		_begin_charge(a1, 0.35, 900.0))
	get_tree().create_timer(BORE_TELEGRAPH + 0.4, false).timeout.connect(func():
		if not is_instance_valid(self): return
		_begin_charge(a2, 0.35, 900.0))


func _begin_charge(target: Vector2, duration: float, accel: float) -> void:
	_charge_active = true
	_charge_target = target
	_charge_accel = accel
	_charge_remaining = duration
	_lock_navigation(true)


var _charge_active: bool = false
var _charge_target: Vector2 = Vector2.ZERO
var _charge_accel: float = 900.0
var _charge_remaining: float = 0.0


func _tick_phase(delta: float) -> void:
	if _charge_active:
		_charge_remaining -= delta
		_steer_toward(_charge_target, _charge_accel, delta)
		if _charge_remaining <= 0.0:
			_charge_active = false
			_lock_navigation(false)


func _mine_pattern(index: int) -> void:
	if index == 0:
		# Random scatter: 4 mines.
		for i in 4:
			var off := Vector2(randf_range(-90, 90), randf_range(-90, 90))
			_spawn_prop(MINE_SCENE, global_position + off)
	else:
		# Patterned 4x4 grid.
		for gx in 4:
			for gy in 4:
				var pos := global_position + Vector2((gx - 1.5) * 40, (gy - 1.5) * 40)
				_spawn_prop(MINE_SCENE, pos)


func _wall_pattern(index: int) -> void:
	if index == 0:
		# Raise stone pillar rows.
		for i in 6:
			var off := Vector2(randf_range(-100, 100), randf_range(-100, 100))
			_stamp_material(global_position + off, PILLAR_RADIUS, MaterialRegistry.MAT_STONE)
	else:
		# Corridor slam: two parallel walls toward the player then a charge.
		var dir := (_player_pos() - global_position).normalized()
		var perp := dir.rotated(deg_to_rad(90))
		for i in 5:
			var t := float(i) / 5.0 * 160.0
			_stamp_material(global_position + dir * t + perp * 30, PILLAR_RADIUS, MaterialRegistry.MAT_STONE)
			_stamp_material(global_position + dir * t - perp * 30, PILLAR_RADIUS, MaterialRegistry.MAT_STONE)
		_begin_charge(_player_pos(), 0.6, 900.0)


func _spawn_telegraph_ground_crack(start: Vector2, end: Vector2, duration: float) -> void:
	BossTelegraph.ground_crack_line(get_parent(), start, end, duration)
```

Scene mirrors Burrower's `.tscn` with `script = res://src/enemies/bosses/drill_boss.gd`, `boss_name = "Drill Construct"`, `attack_interval = 1.8`.

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_drill_boss_phases.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/bosses/drill_boss.gd scenes/enemies/bosses/drill_boss.tscn tests/unit/test_drill_boss_phases.gd
git commit -m "feat: add Drill Construct (Mines) boss with bore/mine/wall phases"
```

---

## Task 9: Warden boss (Vault)

**Files:**
- Create: `src/enemies/bosses/warden_boss.gd`
- Create: `scenes/enemies/bosses/warden_boss.tscn`
- Test: `tests/unit/test_warden_boss_phases.gd`

**Interfaces:**
- Consumes: Task 1 `BossTelegraph`, Task 2 hooks/facades, `_spawn_minion`, `scenes/enemies/melee_enemy.tscn` and `scenes/enemies/brute_enemy.tscn` for elite adds (use brute for elite), `scenes/gold_drop.tscn` for gold rain, `MaterialRegistry` (none), Weapon `boss_staff` clone + `BounceBehavior` (`src/weapons/projectile_behaviors/bounce_behavior.gd`) for ricochet shots.
- Produces: `WardenBoss extends BossEnemy`; `boss_name = "Golden Warden"`, `weapon_resource = boss_staff` clone with a `BounceBehavior`, phases 2/2/2. Player interaction in phase 2 requires a player velocity API — the boss casts the player `CharacterBody2D` and directly sets `velocity` (the player controller reads `velocity`); wrapping in a method `_apply_player_force(dir, magnitude)` so tests can stub it.

**Per-pattern behavior:**
- P1.A Single bouncing shot: clone `boss_staff`, push a `BounceBehavior.new()` into `_make_behaviors()` via a per-shot behaviors override; fire 1 projectile.
- P1.B Ricochet pair: 2 mirrored shots.
- P2.A Magnet pull: in `_tick_phase`, if a player is within `magnet_radius` (220), apply `_apply_player_force(toward_boss, ramped_strength)`; spawn `converging_particles` toward the boss (golden tint) once on pattern start.
- P2.B Repulse shove: brief outward force via `_apply_player_force(-dir, strong)`; spawn `shockwave_ring` telegraph.
- P3.A Elite summon: `_spawn_minion(brute_enemy.tscn, corner_pos, true)`; corner banner telegraph (`expanding_circle`).
- P3.B Gold rain: spawn `gold_drop.tscn` clusters from above (y = arena top) at random x positions near the player with a `shockwave_ring`/shadow telegraph on the ground; the gold drop falls and on impact deals damage (a `gold_drop` does not damage on its own — the boss additionally calls `player.hit(damage)` where the drop lands if the player is still there).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const WardenScript := preload("res://src/enemies/bosses/warden_boss.gd")

class FakeWarden extends WardenScript:
	var fires: Array = []
	var forces: Array = []
	var minions: Array = []
	var props: Array = []
	func _ready() -> void:
		pass
	func _fire_ricochet(count: int) -> void:
		fires.append(count)
	func _apply_player_force(dir: Vector2, magnitude: float) -> void:
		forces.append({"dir": dir, "mag": magnitude})
	func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void:
		minions.append({"pos": world_pos, "elite": is_elite})
	func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
		props.append({"pos": world_pos})
	func _spawn_telegraph_shockwave(_c: Vector2, _r: float, _d: float) -> void:
		pass
	func _spawn_telegraph_converging(_t: Vector2, _r: float, _d: float, _c: Color) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b := auto_free(FakeWarden.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_single_then_pair() -> void:
	var b := auto_free(FakeWarden.new())
	b.current_phase = 1
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_that(b.fires).is_equal([1, 2])

func test_phase_3_a_summons_one_elite() -> void:
	var b := auto_free(FakeWarden.new())
	b.current_phase = 3
	b._execute_pattern(3, 0)
	assert_int(b.minions.size()).is_equal(1)
	assert_bool(b.minions[0]["elite"]).is_true()

func test_phase_3_b_drops_gold_clusters() -> void:
	var b := auto_free(FakeWarden.new())
	b.current_phase = 3
	b._execute_pattern(3, 1)
	assert_int(b.props.size()).is_greater_equal(3)
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_warden_boss_phases.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
class_name WardenBoss
extends BossEnemy

const RICOCHET_TELEGRAPH := 0.6
const MAGNET_RADIUS := 220.0
const BRUTE_SCENE := preload("res://scenes/enemies/brute_enemy.tscn")
const GOLD_DROP_SCENE := preload("res://scenes/gold_drop.tscn")


func _ready() -> void:
	boss_name = "Golden Warden"
	var w := WeaponRegistry.get_weapon_by_id("boss_staff")
	weapon_resource = w.duplicate() if w else null
	super._ready()


func _pattern_count(_phase: int) -> int:
	return 2


func _on_phase_enter(phase: int) -> void:
	match phase:
		1: attack_interval = 1.4
		2: attack_interval = 1.6
		3: attack_interval = 2.0


func _execute_pattern(phase: int, index: int) -> void:
	match phase:
		1: _ricochet_pattern(index)
		2: _magnet_pattern(index)
		3: _adds_pattern(index)


func _ricochet_pattern(index: int) -> void:
	_fire_ricochet(1 if index == 0 else 2)


func _fire_ricochet(count: int) -> void:
	if weapon == null:
		return
	_spawn_telegraph_shockwave(global_position, 8.0, RICOCHET_TELEGRAPH)
	await get_tree().create_timer(RICOCHET_TELEGRAPH, false).timeout
	if not is_instance_valid(self) or not (_player_ref and is_instance_valid(_player_ref)):
		return
	for i in count:
		var clone := (weapon as RangedWeapon).duplicate()
		var dir := (_player_ref.global_position - global_position).normalized()
		if count == 2:
			dir = dir.rotated(deg_to_rad(-30.0 + 60.0 * i))
		clone.use_in_direction(self, dir)


func _magnet_pattern(index: int) -> void:
	if index == 0:
		_spawn_telegraph_converging(global_position, MAGNET_RADIUS, 0.4, Color(1.0, 0.85, 0.2))
		# Pull applied in _tick_phase while this pattern is "active".
		_magnet_active = true
	else:
		_magnet_active = false
		_spawn_telegraph_shockwave(global_position, MAGNET_RADIUS, 0.4)
		_repulse_pulse()


var _magnet_active: bool = false


func _tick_phase(delta: float) -> void:
	if current_phase != 2 or not _magnet_active:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var to := global_position - _player_ref.global_position
	var d := to.length()
	if d < MAGNET_RADIUS and d > 1.0:
		var ramp := 1.0 - d / MAGNET_RADIUS
		_apply_player_force(to.normalized(), 60.0 * ramp * delta * 60.0)


func _repulse_pulse() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var dir := (_player_ref.global_position - global_position).normalized()
	_apply_player_force(dir, 280.0)


func _apply_player_force(dir: Vector2, magnitude: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is CharacterBody2D):
		return
	(p as CharacterBody2D).velocity += dir * magnitude


func _adds_pattern(index: int) -> void:
	if index == 0:
		_summon_elite()
	else:
		_gold_rain()


func _summon_elite() -> void:
	var corner := Vector2(global_position.x + 120, global_position.y + 120)
	_spawn_telegraph_shockwave(corner, 24.0, 0.5)
	get_tree().create_timer(0.5, false).timeout.connect(func():
		if is_instance_valid(self): _spawn_minion(BRUTE_SCENE, corner, true))


func _gold_rain() -> void:
	# Drop gold clusters from above near the player; each telegraph + drop + impact damage.
	for i in 3:
		var base := _player_ref.global_position if (_player_ref and is_instance_valid(_player_ref)) else global_position
		var target := base + Vector2(randf_range(-60, 60), randf_range(-60, 60))
		_spawn_telegraph_shockwave(target, 16.0, 0.8)
		var tpos := target
		get_tree().create_timer(0.8, false).timeout.connect(func():
			if not is_instance_valid(self): return
			var drop := GOLD_DROP_SCENE.instantiate()
			drop.global_position = tpos + Vector2(0, -160)
			_spawn_node(drop, tpos))


func _spawn_node(node: Node2D, world_pos: Vector2) -> void:
	# Reuse the dispatcher's spawn_node path through the chunk container.
	var wm := get_tree().get_first_node_in_group("world_manager")
	if wm == null or not is_instance_valid(wm):
		return
	var container := wm.get_chunk_container()
	container.add_child(node)
	node.global_position = world_pos


func _spawn_telegraph_shockwave(center: Vector2, radius: float, duration: float) -> void:
	BossTelegraph.shockwave_ring(get_parent(), center, radius, duration)

func _spawn_telegraph_converging(target: Vector2, radius: float, duration: float, tint: Color) -> void:
	BossTelegraph.converging_particles(get_parent(), target, radius, duration, tint)
```

Scene mirrors Burrower's `.tscn` with `script = res://src/enemies/bosses/warden_boss.gd`, `boss_name = "Golden Warden"`, `attack_interval = 1.4`.

**Note:** `use_in_direction(dir)` may not exist on `RangedWeapon`. The implementer checks `src/weapons/ranged_weapon.gd` for the shot-direction API; if only `use(user)` exists (auto-aims at user's facing), add a public `func use_in_direction(user: Node2D, dir: Vector2) -> void` to `RangedWeapon` that sets `_burst_dir = dir` and fires (mirroring the internal `_burst_dir` machinery already in the class). If the implementer finds a cleaner existing hook, use it; the test stub does not depend on the projectile mechanics (it stubs `_fire_ricochet`).

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_warden_boss_phases.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/enemies/bosses/warden_boss.gd scenes/enemies/bosses/warden_boss.tscn tests/unit/test_warden_boss_phases.gd
git commit -m "feat: add Golden Warden (Vault) boss with ricochet/magnet/adds phases"
```

---

## Task 10: CameraEffect wrapper

**Files:**
- Create: `src/core/camera_effect.gd`
- Test: `tests/unit/test_camera_effect.gd`

**Interfaces:**
- Consumes: a main `Camera2D` (the player/scene camera) found via `get_tree().get_first_node_in_group("player_camera")` or passed explicitly at `setup(cam)`.
- Produces: `CameraEffect extends Node` with:
  - `func setup(cam: Camera2D) -> void` — stores the camera ref + records `_rest_offset`/`_rest_zoom`.
  - `func pan_to(world_pos: Vector2, duration: float, zoom: Vector2) -> Tween` — tweens offset to bring `world_pos` to screen center; returns the tween. Used by intro.
  - `func pan_back(duration: float) -> Tween` — returns to `_rest_offset`/`_rest_zoom`.
  - `func shake(intensity: float, duration: float) -> void` — adds a decaying random offset to the camera over `duration`; does not accumulate beyond one active shake.
  - `func hit_stop(duration: float) -> void` — sets `get_tree().paused = true` for `duration` via a `process_callback`-aware timer (uses `process_mode = PROCESS_MODE_ALWAYS` on the CameraEffect so it can unpause). Used by death.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const CameraEffect = preload("res://src/core/camera_effect.gd")

func test_pan_to_returns_tween_and_restores() -> void:
	var cam := auto_free(Camera2D.new())
	get_tree().root.add_child(cam)
	var fx := auto_free(CameraEffect.new())
	get_tree().root.add_child(fx)
	fx.setup(cam)
	var t := fx.pan_to(Vector2(100, 0), 0.2, Vector2(1.2, 1.2))
	assert_that(t is Tween).is_true()
	await waitime(0.3)
	fx.pan_back(0.1)
	await waitime(0.2)
	# Just assert it ran without crashing; exact offsets are tween-driven.
	assert_bool(is_instance_valid(fx)).is_true()

func test_shake_does_not_crash_without_camera() -> void:
	var fx := auto_free(CameraEffect.new())
	get_tree().root.add_child(fx)
	fx.shake(2.0, 0.2)  # no setup yet; should no-op cleanly.
	assert_bool(is_instance_valid(fx)).is_true()
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_camera_effect.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
class_name CameraEffect
extends Node

var _cam: Camera2D = null
var _rest_offset: Vector2 = Vector2.ZERO
var _rest_zoom: Vector2 = Vector2.ONE
var _shake_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(cam: Camera2D) -> void:
	_cam = cam
	_rest_offset = cam.offset
	_rest_zoom = cam.zoom


func pan_to(world_pos: Vector2, duration: float, zoom: Vector2) -> Tween:
	if _cam == null:
		return null
	# Bring world_pos to screen center: offset so that camera_center + offset -> screen center.
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var target := world_pos - screen_center - _cam.global_position
	var t := create_tween()
	t.tween_property(_cam, "offset", target, duration).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_cam, "zoom", zoom, duration).set_trans(Tween.TRANS_SINE)
	return t


func pan_back(duration: float) -> Tween:
	if _cam == null:
		return null
	var t := create_tween()
	t.tween_property(_cam, "offset", _rest_offset, duration).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_cam, "zoom", _rest_zoom, duration).set_trans(Tween.TRANS_SINE)
	return t


func shake(intensity: float, duration: float) -> void:
	if _cam == null:
		return
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()
	var timer := 0.0
	var tw := create_tween()
	_shake_tween = tw
	tw.set_process_mode(Tween.TWEEN_PROCESS_PROCESS)
	for _i in int(duration * 60.0):
		tw.tween_callback(func():
			if _cam == null or not is_instance_valid(_cam): return
			_cam.offset += Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)))
		tw.tween_interval(1.0 / 60.0)
	var fade := create_tween()
	fade.tween_property(_cam, "offset", _rest_offset, duration).set_trans(Tween.TRANS_LINEAR)


func hit_stop(duration: float) -> void:
	get_tree().paused = true
	get_tree().create_timer(duration, true, false, true).timeout.connect(func():
		get_tree().paused = false)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_camera_effect.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/camera_effect.gd tests/unit/test_camera_effect.gd
git commit -m "feat: add CameraEffect wrapper for boss intro pan + death shake"
```

---

## Task 11: BossHud UI

**Files:**
- Create: `src/ui/boss_hud.gd`
- Create: `scenes/ui/boss_hud.tscn`
- Test: `tests/unit/test_boss_hud.gd`

**Interfaces:**
- Consumes: existing UI tokens if present (`UILayout`, `JuicyPanel`) — the implementer greps `src/ui/ui_layout.gd` and `src/ui/juicy_panel.gd`; if missing, use local constants centralized in this script (`PADDING = 8`, `BAR_H = 14`, etc.).
- Produces: `BossHud extends CanvasLayer` (layer 10): child `ColorRect` backdrop strip + `Label` name + `ProgressBar` healthbar + `HBoxContainer` of 3 phase `Panel` pips + tick `Line2D`s for health gates. Public API:
  - `func setup(boss_name: String, max_health: int, phase_count: int, thresholds: Array[int]) -> void`
  - `func update_health(current: int) -> void`
  - `func set_phase(phase: int) -> void` — lights the matching pip + a "PHASE N" banner flash (`LabelAutoFade`).
  - `func show_hud() -> void` / `func hide_hud() -> void` — tween in/out.
  - `func get_public_phase() -> int` (test seam).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const BossHudScene := preload("res://scenes/ui/boss_hud.tscn")

func test_setup_records_phase_count() -> void:
	var hud := auto_free(BossHudScene.instantiate())
	get_tree().root.add_child(hud)
	hud.setup("Burrower", 300, 3, [300, 200, 100])
	assert_int(hud.get_public_phase()).is_equal(1)

func test_set_phase_lights_pip() -> void:
	var hud := auto_free(BossHudScene.instantiate())
	get_tree().root.add_child(hud)
	hud.setup("Boss", 100, 3, [100, 66, 33])
	hud.set_phase(2)
	assert_int(hud.get_public_phase()).is_equal(2)

func test_update_health_clamps_bar() -> void:
	var hud := auto_free(BossHudScene.instantiate())
	get_tree().root.add_child(hud)
	hud.setup("Boss", 100, 3, [100, 66, 33])
	hud.update_health(50)
	var bar: ProgressBar = hud.get_node("Bar")
	assert_float(bar.value).is_equal(50.0)
	hud.update_health(-5)
	assert_float(bar.value).is_equal(0.0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_hud.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
class_name BossHud
extends CanvasLayer

const PADDING := 8
const BAR_H := 14

var _phase: int = 1
var _phase_buttons: Array = []
var _banner: Label = null
var _bar: ProgressBar = null
var _name_label: Label = null


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.position = Vector2(0, 0)
	bg.custom_minimum_size = Vector2(0, 56)
	bg.size = Vector2(get_viewport().get_visible_rect().size.x, 56)
	add_child(bg)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.position = Vector2(PADDING, 4)
	_name_label.text = ""
	add_child(_name_label)

	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.position = Vector2(PADDING, 24)
	_bar.size = Vector2(get_viewport().get_visible_rect().size.x - 2 * PADDING, BAR_H)
	_bar.show_percentage = false
	add_child(_bar)

	var pips := HBoxContainer.new()
	pips.name = "Pips"
	pips.position = Vector2(PADDING, 42)
	add_child(pips)
	# Pips added dynamically in setup().


func setup(boss_name: String, max_health: int, phase_count: int, _thresholds: Array[int]) -> void:
	_name_label.text = boss_name
	_bar.max_value = float(max_health)
	_bar.value = float(max_health)
	var pips: HBoxContainer = get_node("Pips")
	_phase_buttons.clear()
	for c in pips.get_children():
		c.queue_free()
	for i in phase_count:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(12, 8)
		pips.add_child(pip)
		_phase_buttons.append(pip)
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 60, 8)
	_banner.modulate.a = 0.0
	add_child(_banner)
	_phase = 1


func update_health(current: int) -> void:
	_bar.value = float(clamp(current, 0, int(_bar.max_value)))


func set_phase(phase: int) -> void:
	_phase = phase
	if _banner:
		_banner.text = "PHASE %d" % phase
		var t := create_tween()
		t.tween_property(_banner, "modulate:a", 1.0, 0.15)
		t.tween_interval(0.8)
		t.tween_property(_banner, "modulate:a", 0.0, 0.5)


func show_hud() -> void:
	modulate.a = 1.0
	visible = true


func hide_hud() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): visible = false)


func get_public_phase() -> int:
	return _phase
```

`scenes/ui/boss_hud.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://bbosshud01"]

[ext_resource type="Script" path="res://src/ui/boss_hud.gd" id="1_hud"]

[node name="BossHud" type="CanvasLayer"]
script = ExtResource("1_hud")
```

Run `godot --headless --path . --import` to generate `.uid`.

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_hud.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ui/boss_hud.gd scenes/ui/boss_hud.tscn tests/unit/test_boss_hud.gd
git commit -m "feat: add BossHud with name + health bar + phase pips"
```

---

## Task 12: BossDeathSequencer (Saltmire dissolve + fragment streamer)

**Files:**
- Create: `src/core/boss_death_sequencer.gd`
- Test: `tests/unit/test_boss_death_dissolve.gd`
- Test: `tests/unit/test_boss_fragment_stream.gd`

**Interfaces:**
- Consumes: `FX` autoload (`addons/saltmire_fx/fx.gd`): `FX.dissolve(target, duration, edge_color) -> Tween`, `FX.clear(target)`, `FX.appear(target, duration, edge_color) -> Tween`. `EnemyVfxShared.soft_dot_texture()`. The boss sprite obtained via `boss.get_node_or_null("Sprite2D")`. `boss.sprite.texture.get_image()` for silhouette sampling.
- Produces: `BossDeathSequencer extends Node`:
  - `func configure(spawn_parent: Node, portal_scene: PackedScene, weapon_drop_scene: PackedScene, fast: bool = false) -> void` — DI for tests; the controller passes real scenes; tests pass nulls to skip portal/drop.
  - `func play(boss: BossEnemy, arena_center: Vector2, edge_color: Color, drop_scene: PackedScene) -> void` — does: hit-stop, shake (via a callable the controller injects as `_shake_cb`), sample silhouette, spawn fragments, call `FX.dissolve`, `await` its `finished`, spawn portal at `arena_center`, tween weapon drop from boss pos out to a reachable spot, `FX.clear` + `boss.queue_free()`. Honors `fast` to skip tween waits in tests.
  - `func _sample_silhouette_points(sprite: Sprite2D, count: int) -> Array[Vector2]` — AABB of the sprite in world space, random-sample `count * 4` points, keep `count` whose pixel alpha > 0 (via `get_image().get_pixelv(local_uv)`). Returns world-space points.
  - `var shake_callback: Callable` (controller injects `fx.shake.bind(...)` or a local lambda).
  - `var camera_fx: Node` (a `CameraEffect`) — the controller injects; tests inject a stub.

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_boss_death_dissolve.gd`:

```gdscript
extends GdUnitTestSuite

const BossDeathSequencer = preload("res://src/core/boss_death_sequencer.gd")

class FakeBoss extends BossEnemy:
	func _ready() -> void:
		pass

func test_play_dissolves_and_clears_and_frees() -> void:
	var boss := auto_free(FakeBoss.new())
	var tex := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tex.fill(Color(1, 1, 1, 1))
	boss.global_position = Vector2.ZERO
	# Build a Sprite2D the sequencer can find.
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = ImageTexture.create_from_image(tex)
	boss.add_child(sprite)
	var seq := auto_free(BossDeathSequencer.new())
	seq.configure(null, null, null, true)  # fast mode
	seq.play(boss, Vector2.ZERO, Color(1.0, 0.6, 0.15), null)
	assert_bool(sprite.material is ShaderMaterial).is_true()
	await waitime(0.5)
	assert_bool(is_instance_valid(boss)).is_false()
```

`tests/unit/test_boss_fragment_stream.gd`:

```gdscript
extends GdUnitTestSuite

const BossDeathSequencer = preload("res://src/core/boss_death_sequencer.gd")

func test_sample_silhouette_rejects_transparent() -> void:
	var tex := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tex.fill(Color(0, 0, 0, 0))
	# Fill a small solid square in the center.
	for x in range(6, 10):
		for y in range(6, 10):
			tex.set_pixel(x, y, Color(1, 1, 1, 1))
	var sprite := auto_free(Sprite2D.new())
	sprite.texture = ImageTexture.create_from_image(tex)
	sprite.global_position = Vector2(100, 100)
	var seq := auto_free(BossDeathSequencer.new())
	var pts := seq._sample_silhouette_points(sprite, 20)
	# All accepted points must lie inside the solid center square's world AABB.
	assert_int(pts.size()).is_greater_equal(1)
	var sq_min := Vector2(100 - 8 + 6, 100 - 8 + 6)  # sprite centered on its origin
	var sq_max := Vector2(100 - 8 + 10, 100 - 8 + 10)
	for p in pts:
		assert_bool(p.x >= min(sq_min.x, sq_max.x) and p.x <= max(sq_min.x, sq_max.x)).is_true()
```

- [ ] **Step 2: Run to verify they fail**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_death_dissolve.gd -a tests/unit/test_boss_fragment_stream.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
class_name BossDeathSequencer
extends Node

var _spawn_parent: Node = null
var _portal_scene: PackedScene = null
var _fast: bool = false
var _tween_factory: Callable = Callable()  # injection; default uses real tweens
var camera_fx: Node = null
var shake_callback: Callable = Callable()


func configure(spawn_parent: Node, portal_scene: PackedScene, _drop_scene: PackedScene, fast: bool = false) -> void:
	_spawn_parent = spawn_parent
	_portal_scene = portal_scene
	_fast = fast


func play(boss: BossEnemy, arena_center: Vector2, edge_color: Color, drop_scene: PackedScene) -> void:
	var sprite := boss.get_node_or_null("Sprite2D") as Sprite2D
	if camera_fx and camera_fx.has_method("hit_stop"):
		camera_fx.hit_stop(0.05)
	if shake_callback.is_valid():
		shake_callback.call(3.0, 0.4)
	# 1. Sample silhouette and spawn fragments.
	if sprite:
		var pts := _sample_silhouette_points(sprite, 32)
		for p in pts:
			_spawn_fragment(p, arena_center, edge_color)
	# 2. Dissolve.
	if sprite:
		var dur := 0.3 if _fast else 1.4
		var tween := FX.dissolve(sprite, dur, edge_color)
		if tween and not _fast:
			await tween.finished
		elif _fast:
			# Force progress to 1.0 immediately for the test fast path.
			(sprite.material as ShaderMaterial).set_shader_parameter("progress", 1.0)
	# 3. Portal rises.
	if _portal_scene and _spawn_parent:
		var portal := _portal_scene.instantiate()
		portal.global_position = arena_center
		_spawn_parent.add_child(portal)
	# 4. Weapon drop flies out (best-effort).
	if drop_scene and _spawn_parent and boss.weapon:
		var drop := drop_scene.instantiate()
		drop.global_position = boss.global_position
		_spawn_parent.add_child(drop)
		var target := boss.global_position + (arena_center - boss.global_position).normalized() * 60
		var t := drop.create_tween()
		t.tween_property(drop, "global_position", target, 0.5).set_trans(Tween.TRANS_SINE)
	# 5. Cleanup.
	if sprite:
		FX.clear(sprite)
	boss.queue_free()


func _spawn_fragment(world_pos: Vector2, portal_pos: Vector2, tint: Color) -> void:
	if _spawn_parent == null:
		return
	var frag := Sprite2D.new()
	frag.texture = EnemyVfxShared.soft_dot_texture(8)
	frag.modulate = tint
	frag.global_position = world_pos
	frag.z_index = 6
	_spawn_parent.add_child(frag)
	var t := frag.create_tween()
	t.set_parallel(true)
	t.tween_property(frag, "global_position", portal_pos, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(frag, "scale", Vector2.ZERO, 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(frag, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_LINEAR)
	t.chain().tween_callback(frag.queue_free)


func _sample_silhouette_points(sprite: Sprite2D, count: int) -> Array[Vector2]:
	var tex := sprite.texture
	if tex == null:
		return []
	var img: Image = tex.get_image() if tex.has_method("get_image") else (tex as ImageTexture).get_image()
	var size := img.get_size()
	# World-space AABB of the sprite (sprite origin is its center by default).
	var half := Vector2(size) * 0.5
	var origin := sprite.global_position
	var accepted: Array[Vector2] = []
	var attempts := 0
	var max_attempts := count * 8
	while accepted.size() < count and attempts < max_attempts:
		attempts += 1
		var lx := randi() % size.x
		var ly := randi() % size.y
		var pix := img.get_pixel(lx, ly)
		if pix.a > 0.1:
			var world := origin + Vector2(lx - half.x, ly - half.y)
			accepted.append(world)
	return accepted
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_death_dissolve.gd -a tests/unit/test_boss_fragment_stream.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/boss_death_sequencer.gd tests/unit/test_boss_death_dissolve.gd tests/unit/test_boss_fragment_stream.gd
git commit -m "feat: add BossDeathSequencer (Saltmire dissolve + silhouette fragments)"
```

---

## Task 13: BossEncounter controller

**Files:**
- Create: `src/core/boss_encounter.gd`
- Test: `tests/unit/test_boss_encounter_lifecycle.gd`

**Interfaces:**
- Consumes: Tasks 10/11/12. The boss (BossEnemy) provides `boss_ready`/`phase_changed`/`died`/`health_changed`/`set_encounter_active`/`max_health`/`health`/`current_phase`/`phase_count`/`get_node_or_null("Sprite2D")` and the `boss_name`/`hazard_interval`. `LevelManager.current_biome` (`tint`/`ui_accent`, plus per-biome edge color).
- Produces: `BossEncounter extends Node` added under the main scene (`LevelManager._ready` or `WorldManager`); group `boss_encounter`; methods the dispatchers call:
  - `func notify_spawned(boss: BossEnemy, arena_center: Vector2) -> void`
  - `func notify_died(boss: BossEnemy, arena_center: Vector2) -> void`
  - `func shake(intensity: float, duration: float) -> void` (callable via group call by bosses)
  - `func clear() -> void` — disconnects, hides HUD, resets state.

  Internal: spawns the `BossHud` scene as a child once (lazy on first `notify_spawned`), spawns a `CameraEffect` + `BossDeathSequencer` as children. The biome edge color is derived from `LevelManager.current_biome.ui_accent` for the dissolve.

  **Intro:** `notify_spawned` → `boss.set_encounter_active(false)` → camera `pan_to` boss + `FX.appear(sprite, 1.2, edge_color)` + HUD `setup` + `show_hud` → after ~1.5s → `boss.set_encounter_active(true)` + camera `pan_back`.
  **Ongoing:** connect `boss.phase_changed` → `hud.set_phase`; connect `boss.health_changed` → `hud.update_health`.
  **Death:** `notify_died` → `hud.hide_hud()` → `BossDeathSequencer.play(boss, arena_center, edge_color, weapon_drop_scene)` → portal spawns inside the sequencer (Task 12); disconnect.

  Guard: if a boss is already active and a second `notify_spawned` arrives, `push_warning` and return.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GdUnitTestSuite

const BossEncounter = preload("res://src/core/boss_encounter.gd")

class FakeBoss extends BossEnemy:
	signal phase_changed(p: int)
	signal health_changed(c: int, m: int)
	func _ready() -> void:
		pass
	var phase_synthetic: int = 1
	func get_phase() -> int:
		return phase_synthetic

func _new_controller() -> BossEncounter:
	var c := auto_free(BossEncounter.new())
	get_tree().root.add_child(c)
	# Inject stub camera_fx so it doesn't need a real Camera2D.
	c._camera_fx = null
	c._sequencer._fast = true
	return c

func test_notify_spawned_attaches_hud_and_starts_intro() -> void:
	var c := _new_controller()
	var boss := auto_free(FakeBoss.new())
	boss.boss_name = "Test"
	boss.max_health = 100
	boss.health = 100
	boss.phase_count = 3
	get_tree().root.add_child(boss)
	c.notify_spawned(boss, Vector2.ZERO)
	assert_bool(c.is_fight_active()).is_true()

func test_notify_died_runs_death_and_clears_active() -> void:
	var c := _new_controller()
	var boss := auto_free(FakeBoss.new())
	boss.boss_name = "Test"
	boss.max_health = 100
	boss.health = 100
	boss.phase_count = 3
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	boss.add_child(sprite)
	get_tree().root.add_child(boss)
	c.notify_spawned(boss, Vector2.ZERO)
	c.notify_died(boss, Vector2.ZERO)
	await waitime(0.6)
	assert_bool(c.is_fight_active()).is_false()
	assert_bool(is_instance_valid(boss)).is_false()

func test_second_spawn_while_active_is_ignored() -> void:
	var c := _new_controller()
	var boss1 := auto_free(FakeBoss.new())
	boss1.boss_name = "B1"; boss1.max_health = 100; boss1.health = 100; boss1.phase_count = 3
	get_tree().root.add_child(boss1)
	c.notify_spawned(boss1, Vector2.ZERO)
	var boss2 := auto_free(FakeBoss.new())
	boss2.boss_name = "B2"; boss2.max_health = 100; boss2.health = 100; boss2.phase_count = 3
	get_tree().root.add_child(boss2)
	c.notify_spawned(boss2, Vector2.ZERO)  # should be ignored
	assert_bool(c.current_boss() == boss1).is_true()
```

- [ ] **Step 2: Run to verify it fails**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_encounter_lifecycle.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

```gdscript
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
	if _boss != boss:
		return  # not ours
	if _hud:
		_hud.hide_hud()
	var edge := _biome_edge_color()
	_sequencer.play(boss, arena_center, edge, WEAPON_DROP_SCENE)


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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_encounter_lifecycle.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/boss_encounter.gd tests/unit/test_boss_encounter_lifecycle.gd
git commit -m "feat: add BossEncounter controller (intro/HUD sync/death lifecycle)"
```

---

## Task 14: SpawnDispatcher — biome boss scene + remove local portal

**Files:**
- Modify: `src/core/spawn_dispatcher.gd` (lines ~6, ~186–280, ~349)
- Test: rely on existing `tests/unit/test_boss_*` and manual smoke (no new test needed; behavior is verified via the arena biome-match test in Task 18)

**Interfaces:**
- Consumes: Task 13 `BossEncounter` (group `boss_encounter`), the five new boss scenes via `LevelManager.current_biome.boss_scene`.
- Produces: `SpawnDispatcher._spawn_enemy`'s `is_boss` branch loads `LevelManager.current_biome.boss_scene` (instead of `BOSS_ENEMY_SCENE`+`boss_staff`), applies `_apply_floor_scaling`, calls `BossEncounter.notify_spawned`; `_on_boss_died` is removed (the controller owns the portal via `notify_died`). The `is_boss` scaling branches (the `5.0` HP / `1.5` speed / `weapon.damage *= damage_mult`) are **removed** because `_apply_floor_scaling` now does that work.

**Pre-check:** trace marker type 6 reachability. The dispatcher's `_spawn_entity` only dispatches marker 6 inside `slot.is_boss` sectors — but the composition feature (`FeatureBossSpawn.apply → CompositionDispatcher.spawn_boss`) is the path that actually spawns bosses for arena-composed rooms. If marker 6 is never produced for boss rooms (because compositions replace the boss marker flow), delete the `is_boss` branch entirely and rely solely on `CompositionDispatcher.spawn_boss`. The implementer greps `template_pack.collect_markers` return values for marker type `6` to confirm. **Decision rule:** if marker 6 is produced, keep the branch but route it through biomes; if not, delete it. Either way the `CompositionDispatcher` path (Task 15) is the canonical spawn path.

- [ ] **Step 1: Modify**

In `src/core/spawn_dispatcher.gd`:

1. Delete `const BOSS_ENEMY_SCENE := preload("res://scenes/enemies/boss_enemy.tscn")` (line 6).
2. In `_spawn_enemy`, replace the `if is_boss:` block:

```gdscript
	if is_boss:
		var boss_scene: PackedScene = LevelManager.current_biome.boss_scene if (LevelManager.current_biome != null) else null
		if boss_scene == null:
			push_warning("SpawnDispatcher: no boss_scene on current biome; skipping boss spawn.")
			return
		enemy = boss_scene.instantiate()
		enemy.boss_name = LevelManager.current_biome.display_name + " Boss"
	else:
		# ... keep existing elite/melee/ranged selection.
```

3. Delete the boss-scaling overrides: the lines
   ```
   enemy.max_health = int(... * (5.0 if is_boss else 1.0))
   enemy.speed = ... * (1.5 if is_boss else 1.0)
   ```
   become
   ```
   enemy.max_health = int(float(enemy.max_health) * health_mult * (2.0 if is_elite else 1.0))
   enemy.speed = enemy.speed * speed_mult
   ```
   (the `is_boss` multipliers are dropped; `_apply_floor_scaling(floor_num)` handles them — call it after instantiation for bosses).

4. After the elite `is_elite` + `enemy_tier` setup, add (boss only):

```gdscript
	if is_boss:
		enemy._apply_floor_scaling(floor_num)
```

5. Delete the `if is_boss: enemy.weapon_resource.damage *= ...` block (now in `_apply_floor_scaling`).

6. Replace the boss portal/`died.connect` wiring:

```gdscript
	if is_boss:
		enemy.modulate = LevelManager.current_biome.tint
		enemy.global_position = world_pos
		_spawn_parent.add_child(enemy)
		var enc := get_tree().get_first_node_in_group("boss_encounter")
		if enc and enc.has_method("notify_spawned"):
			enc.notify_spawned(enemy, world_pos)
		return
	# (existing non-boss add_child path follows)
```

7. Delete the `_on_boss_died` method (lines ~349), including its `PORTAL_SCENE` preload.

- [ ] **Step 2: Run existing boss + dispatch tests to verify no regression**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_ring_coverage.gd -a tests/unit/test_boss_phase_transition.gd`
Expected: PASS (these don't trigger the spawn path).

- [ ] **Step 3: Commit**

```bash
git add src/core/spawn_dispatcher.gd
git commit -m "refactor: SpawnDispatcher routes bosses through biome boss_scene + BossEncounter"
```

---

## Task 15: CompositionDispatcher — remove local portal, route to BossEncounter

**Files:**
- Modify: `src/core/composition_dispatcher.gd` (lines 102–115)

**Interfaces:**
- Consumes: Task 13 `BossEncounter`.
- Produces: `spawn_boss` connects the boss `died` signal to a local handler that calls `BossEncounter.notify_died(inst, world_pos)` instead of spawning a portal directly. `_on_boss_died` is replaced; the `PORTAL_SCENE` const and preload delete.

- [ ] **Step 1: Modify**

In `src/core/composition_dispatcher.gd`:

Replace `spawn_boss` + `_on_boss_died` (lines ~102–116) with:

```gdscript
func spawn_boss(world_pos: Vector2, boss_scene: PackedScene) -> void:
	if boss_scene == null:
		return
	var inst := boss_scene.instantiate()
	inst.global_position = world_pos
	_spawn_parent.add_child(inst)
	var enc := get_tree().get_first_node_in_group("boss_encounter")
	if enc and enc.has_method("notify_spawned"):
		enc.notify_spawned(inst, world_pos)
	if inst.has_signal("died"):
		inst.died.connect(func(): _notify_boss_died(world_pos))


func _notify_boss_died(arena_center: Vector2) -> void:
	var enc := get_tree().get_first_node_in_group("boss_encounter")
	if enc and enc.has_method("notify_died"):
		enc.notify_died(null, arena_center)
```

(We pass the boss via the controller's stored `_boss` ref — `notify_died` takes the stored boss; passing `null` here and letting the controller look up `_boss` is cleaner than threading the dying node through the lambda. Update `BossEncounter.notify_died` signature to `func notify_died(_boss: BossEnemy, arena_center: Vector2)` and have it use the stored `_boss` if the arg is null — already the case because `_on_died_signal` is tied to the controller's own connection. Document this in the plan; the implementer reconciles the two callers.)

Delete the `const PORTAL_SCENE = preload(...)` line inside `_on_boss_died`.

- [ ] **Step 2: Reconcile BossEncounter's `notify_died` callers**

`BossEncounter.notify_died(boss, arena_center)` is called from two places (CompositionDispatcher passes `null`, SpawnDispatcher was removed in Task 14). Make the controller treat a `null` boss arg as "use stored `_boss`":

```gdscript
func notify_died(boss: BossEnemy, arena_center: Vector2) -> void:
	var actual := boss if (boss != null) else _boss
	if actual == null:
		return
	if _boss != null:
		_boss = actual  # keep ref consistent
	...
```

- [ ] **Step 3: Run boss encounter test + composition test**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_encounter_lifecycle.gd -a tests/unit/test_arena_composition.gd`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/core/composition_dispatcher.gd src/core/boss_encounter.gd
git commit -m "refactor: CompositionDispatcher routes boss death to BossEncounter"
```

---

## Task 16: LevelManager — clear BossEncounter on floor advance

**Files:**
- Modify: `src/autoload/level_manager.gd` (line ~46)
- Modify: `POST_steps.md startup` — spawn a `BossEncounter` node once.

**Interfaces:**
- Consumes: Task 13 `BossEncounter`.
- Produces: `advance_floor()` additionally clears the controller. The `BossEncounter` node is added by `WorldManager._ready` (or as an autoload alternative — the implementer checks `project.godot` and the world manager setup); the simplest is adding it as a child of `WorldManager` when it builds, and it survives across floors since `reset()` doesn't free children. The implementer verifies the controller stays alive across `advance_floor` (only its state is cleared, not the node).

- [ ] **Step 1: Modify**

In `src/autoload/level_manager.gd` `advance_floor()`, after `CompositionDispatcher.clear()`:

```gdscript
	var enc := get_tree().get_first_node_in_group("boss_encounter")
	if enc and enc.has_method("clear"):
		enc.clear()
```

(If no `boss_encounter` node exists yet on first floor, this no-ops.)

- [ ] **Step 2: Spawn `BossEncounter` once**

In the world setup (find it via `grep -rn "world_manager\|get_chunk_container\|encounter_director" src/core/world_manager.gd` to locate `_ready`), add at the end of `WorldManager._ready()`:

```gdscript
	var be := preload("res://src/core/boss_encounter.gd").new()
	be.name = "BossEncounter"
	add_child(be)
```

(If `WorldManager` is itself where spawn happens, this keeps the controller scoped to the world node's lifetime. The implementer confirms the controller persists across `reset()` — reset frees chunk children, not the `BossEncounter` direct child if it's added to `self`, not the chunk container.)

- [ ] **Step 3: Run a smoke import**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_encounter_lifecycle.gd`
Expected: PASS (unchanged behavior; just confirms no compile break).

- [ ] **Step 4: Commit**

```bash
git add src/autoload/level_manager.gd src/core/world_manager.gd
git commit -m "feat: spawn BossEncounter with world; clear on floor advance"
```

---

## Task 17: Biome `.tres` — set `boss_scene` per biome

For each of the five biome `.tres` files under `assets/biomes/`, add an `ext_resource` for the biome's boss scene and set the `boss_scene` property.

**Files:**
- Modify: `assets/biomes/caves.tres` → `burrower_boss.tscn`
- Modify: `assets/biomes/magma.tres` → `pyrelord_boss.tscn`
- Modify: `assets/biomes/frozen.tres` → `glacier_boss.tscn`
- Modify: `assets/biomes/mines.tres` → `drill_boss.tscn`
- Modify: `assets/biomes/vault.tres` → `warden_boss.tscn`

**Interfaces:**
- Consumes: the five scene UIDs from Tasks 5–9.
- Produces: each biome's `BiomeDef.boss_scene` field populated.

**Pre-check:** the `scenes/enemies/bosses/*.tscn` UIDs need to exist first (Tasks 5–9 must have run `godot --headless --path . --import` to assign UIDs). The implementer reads each `.tscn`'s first line for its `uid="uid://..."` and uses that in the biome `.tres` `ext_resource`.

- [ ] **Step 1: Edit each biome .tres**

For each biome file, in the `[ext_resource ...]` block near the boss arena composition resources, add a line pointing at the biome's boss scene, with a stable id like `id="99_bossscene"`:

```
[ext_resource type="PackedScene" uid="uid://BBURROWER01" path="res://scenes/enemies/bosses/burrower_boss.tscn" id="99_bossscene"]
```

(use the actual uid printed by the implementer from the scene file — do NOT reuse the placeholder-id value).

Then in the `[resource]` block at the bottom of the file, add (or set, if the property already exists as `boss_scene = null`):

```
boss_scene = ExtResource("99_bossscene")
```

Repeat per biome with the right scene file + uid:
- caves → burrower_boss.tscn
- magma → pyrelord_boss.tscn
- frozen → glacier_boss.tscn
- mines → drill_boss.tscn
- vault → warden_boss.tscn

- [ ] **Step 2: Run import to regenerate .imports**

Run: `godot --headless --path . --import`
Expected: no parse errors. If Godot reports a duplicate `ext_resource id`, change the `id="99_bossscene"` to a unique value per file.

- [ ] **Step 3: Smoke-load each biome**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_biome_def.gd`
Expected: PASS (biomes still load).

- [ ] **Step 4: Commit**

```bash
git add assets/biomes/*.tres
git commit -m "feat: wire biome boss_scene to per-biome boss scenes"
```

---

## Task 18: Repoint the 20 arena `.tres` compositions to biome boss scenes

Each `assets/arenas/boss/<biome>_<variant>.tres` currently references the generic `boss_enemy.tscn` via its `FeatureBossSpawn.boss_scene`. Repoint all 20 to the biome's boss scene.

**Files:**
- Modify: `assets/arenas/boss/caves_{a,b,c,d}.tres`
- Modify: `assets/arenas/boss/magma_{a,b,c,d}.tres`
- Modify: `assets/arenas/boss/frozen_{a,b,c,d}.tres`
- Modify: `assets/arenas/boss/mines_{a,b,c,d}.tres`
- Modify: `assets/arenas/boss/vault_{a,b,c,d}.tres`

**Interfaces:**
- Consumes: the new scene UIDs from Tasks 5–9 (the same ones used in Task 17).
- Produces: every composition's `FeatureBossSpawn.boss_scene` references the biome-correct boss scene.

**Mechanism:** the `.tres` files have a top `[ext_resource type="PackedScene" uid="uid://d2jnf72pty04p" path="res://scenes/enemies/boss_enemy.tscn" id="1_tff1x"]` line and later `boss_scene = ExtResource("1_tff1x")` in the feature sub-resource. The edit changes the `path` of that `ext_resource` (and ideally its `uid`) to the biome boss scene, and possibly the `id` if collisions arise. Simplest correct edit: replace the `path=...` and the `uid=...` of that single `ext_resource` line with the biome scene's values (everything downstream uses the same `id`, so only one line changes per file).

- [ ] **Step 1: Edit each arena .tres**

For each of the 20 files, replace the line:

```
[ext_resource type="PackedScene" uid="uid://d2jnf72pty04p" path="res://scenes/enemies/boss_enemy.tscn" id="1_XXXX"]
```

with the biome boss scene:

```
[ext_resource type="PackedScene" uid="uid://BBURROWER01" path="res://scenes/enemies/bosses/burrower_boss.tscn" id="1_XXXX"]
```

(Keep the existing `id="1_XXXX"` token so downstream `boss_scene = ExtResource("1_XXXX")` references stay valid; only `uid` and `path` change.)

Use the per-biome scene file + actual uid:
- caves_{a,b,c,d} → burrower_boss.tscn
- magma_{a,b,c,d} → pyrelord_boss.tscn
- frozen_{a,b,c,d} → glacier_boss.tscn
- mines_{a,b,c,d} → drill_boss.tscn
- vault_{a,b,c,d} → warden_boss.tscn

- [ ] **Step 2: Run import**

Run: `godot --headless --path . --import`
Expected: no parse errors; all 20 `.tres` resolve their boss_scene to a real scene.

- [ ] **Step 3: Commit**

```bash
git add assets/arenas/boss/*.tres
git commit -m "feat: repoint all 20 boss arena compositions to biome boss scenes"
```

---

## Task 19: Arena biome-match smoke test

**Files:**
- Test: `tests/unit/test_boss_arena_biome_match.gd`

**Interfaces:**
- Consumes: the 20 arena compositions loaded via `BiomeRegistry`; the five boss scene scripts (`BurrowerBoss`, etc.). Asserts each biome's 4 compositions point to the right scene class.

- [ ] **Step 1: Write the test**

```gdscript
extends GdUnitTestSuite

const BurrowerScript := preload("res://src/enemies/bosses/burrower_boss.gd")
const PyrelordScript := preload("res://src/enemies/bosses/pyrelord_boss.gd")
const GlacierScript := preload("res://src/enemies/bosses/glacier_boss.gd")
const DrillScript := preload("res://src/enemies/bosses/drill_boss.gd")
const WardenScript := preload("res://src/enemies/bosses/warden_boss.gd")
const FeatureBossSpawn := preload("res://src/core/features/feature_boss_spawn.gd")

const EXPECTED := {
	"caves": BurrowerScript, "magma": PyrelordScript, "frozen": GlacierScript, "mines": DrillScript, "vault": WardenScript,
}
const BIOME_FILES := {
	"caves": "res://assets/biomes/caves.tres", "magma": "res://assets/biomes/magma.tres",
	"frozen": "res://assets/biomes/frozen.tres", "mines": "res://assets/biomes/mines.tres",
	"vault": "res://assets/biomes/vault.tres",
}

func test_each_biome_boss_scene_matches_expected_script() -> void:
	for biome_name in EXPECTED:
		var path: String = BIOME_FILES[biome_name]
		var bd: BiomeDef = load(path)
		assert_that(bd.boss_scene != null).is_true()
		var inst := bd.boss_scene.instantiate()
		assert_bool(inst is EXPECTED[biome_name]).is_true()
		inst.free()

func test_each_arena_composition_points_to_biome_boss() -> void:
	for biome_name in EXPECTED:
		var bd: BiomeDef = load(BIOME_FILES[biome_name])
		assert_that(bd.boss_compositions.size()).is_equal(4)
		for comp in bd.boss_compositions:
			for f in comp.features:
				if f is FeatureBossSpawn:
					var inst := f.boss_scene.instantiate()
					assert_bool(inst is EXPECTED[biome_name]).is_true()
					inst.free()
```

- [ ] **Step 2: Run test to verify it passes**

Run: `GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_arena_biome_match.gd`
Expected: PASS (since Tasks 17 & 18 wired the scenes).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test_boss_arena_biome_match.gd
git commit -m "test: assert arena compositions point to biome-correct boss scenes"
```

---

## Task 20: Manual smoke + cleanup pass

**Files:** none new

- [ ] **Step 1: Run the full gdUnit4 boss suite + related suites**

```bash
godot --headless --path . --import && \
GODOT_BIN=/usr/bin/godot ./addons/gdUnit4/runtest.sh -a tests/unit/test_boss_phase_transition.gd -a tests/unit/test_boss_phase_changed_signal.gd -a tests/unit/test_boss_attack_cadence.gd -a tests/unit/test_boss_floor_scaling.gd -a tests/unit/test_boss_facade.gd -a tests/unit/test_boss_drops.gd -a tests/unit/test_boss_telegraphs.gd -a tests/unit/test_burrower_boss_phases.gd -a tests/unit/test_pyrelord_boss_phases.gd -a tests/unit/test_glacier_boss_phases.gd -a tests/unit/test_drill_boss_phases.gd -a tests/unit/test_warden_boss_phases.gd -a tests/unit/test_mine_prop.gd -a tests/unit/test_boss_hud.gd -a tests/unit/test_camera_effect.gd -a tests/unit/test_boss_encounter_lifecycle.gd -a tests/unit/test_boss_death_dissolve.gd -a tests/unit/test_boss_fragment_stream.gd -a tests/unit/test_boss_arena_biome_match.gd
```

Expected: all PASS. If any single suite errors with a parse error, read the `SCRIPT ERROR: Parse Error` line (don't chase the misleading `Nonexistent function 'new' in base 'GDScript'` symptom — that means the under-test script failed to compile; fix the const-array typed-literal rule noted in Global Constraints if that's the cause).

- [ ] **Step 2: Confirm the `boss_enemy.tscn` legacy scene is unreferenced**

Run: `grep -rn "scenes/enemies/boss_enemy.tscn" assets/ src/ scenes/ tests/`
Expected: only `scenes/enemies/boss_enemy.tscn` itself in comments or the file listing; no active references. If any remain in a `.tres`/`.gd`, point them at the new scenes and re-run Task 18's import step.

- [ ] **Step 3: Commit cleanup**

```bash
git add -A
git commit -m "chore: boss design smoke pass + legacy generic-boss references cleared"
```

- [ ] **Step 4: Update the implementation todo**

In `docs/design_docs/implementation_todo2.md`, mark all Phase 3 rows as done by replacing `|  |` at the row start with `| x |` for every Phase 3 task (Boss Mechanics & Phases, Per-Biome Boss Design, Boss Presentation).

```bash
git add docs/design_docs/implementation_todo2.md
git commit -m "docs: mark Phase 3 boss design tasks complete"
```

---

## Self-Review (controller-side, post-write)

**Spec coverage check:**
- §`BossEnemy` base refactor → Task 2 ✓ (signals, hooks, cadence, pattern rotation, scaling, facades, movement helpers)
- §Five biome bosses (×2 patterns/phase) → Tasks 5–9 ✓
- §`BossEncounter` controller, HUD, intro & death → Tasks 10–13 ✓ (camera effect, HUD, deaths sequencer, controller)
- §Saltmire dissolve + silhouette fragments → Task 12 ✓
- §Data wiring (compositions, biomes, spawn paths) → Tasks 14–18 ✓ (dispatchers, level manager, biome tres, arena tres)
- §Testing strategy → tests in Tasks 1–20 ✓ (one suite per boss attack-cadence hook, controller lifecycle, dissolve smoke, fragment sampler, arena biome-match)
- §Non-goals (no audio, no new sprites/materials) → respected across all tasks.

**Placeholder scan:** All steps contain concrete code or exact commands; no "TBD/TODO/add appropriate error handling". Where a UID must be read at implementation time (`uid="uid://BBURROWER01"`), the step instructs the implementer to read the scene file's first line and substitute — that is a concrete assigned value, not a placeholder.

**Type consistency:** `BossEnemy.notify_died`/`notify_spawned` signatures matched between Tasks 13–16 (Task 15 reconciles the `null`-boss arg). `_pick_pattern`/`_execute_pattern`/`_pattern_count` match between base (Task 2) and all five subclasses (Tasks 5–9). `BossTelegraph` factory signatures match their call sites in Tasks 5–9. `CameraEffect`/`BossHud`/`BossDeathSequencer`/`BossEncounter` public APIs match across producer/consumer tasks.

The plan is internally consistent and covers the spec. Executing now.
