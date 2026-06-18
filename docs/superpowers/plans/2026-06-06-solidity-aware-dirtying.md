# Solidity-Aware Dirtying Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the terrain simulation from marking every loaded chunk dirty every frame, so NavField and the collision helper only rebuild when terrain *solidity* actually changes — recovering the steady-state frame budget.

**Architecture:** The sim shader already touches every pixel. When it performs a solid→air write (burning a wall, exploding a wall), it `atomicOr`s a per-chunk flag into a small GPU buffer. The CPU reads that buffer back one frame later (double-buffered, no stall — mirroring the existing collider/light/probe readback pattern), and dirties only the flagged chunks. The per-frame blanket dirty in `dispatch_simulation` is removed. Carving, digging, generation, and CPU terrain placements keep their existing explicit dirtying and are unaffected.

**Tech Stack:** Godot 4 / GDScript, GLSL compute shaders via `RenderingDevice`, gdUnit4 for unit tests.

---

## Background & Key Facts (read before starting)

- **Root cause:** `src/core/compute_device.gd:604-606` — `dispatch_simulation` runs every frame and calls `world_manager.mark_terrain_dirty(coord)` for *every* loaded chunk. `mark_terrain_dirty` (`src/core/world_manager.gd:86-90`) dirties both the collision helper and NavField, so both rebuild every chunk every frame and never drain.
- **The only sim writes that change solidity** are solid→air removals at:
  - `shaders/include/sim/burning.glslinc:76` (flammable wall → `MAT_AIR`)
  - `shaders/include/sim/explode_wave.glslinc:97` and `:126` (wall chewed by blast → `MAT_AIR`)
  Lava/water/gas/blood/dust only move non-solid materials; nothing creates a solid.
- **`HAS_COLLIDER[]`** is already generated into `shaders/generated/materials.glslinc` (line 72) and already referenced by `explode_wave.glslinc:108`. No generator change is required — Task 1 just regenerates to be safe.
- **Double-buffer reference implementation** to mirror: collider buffer in `src/core/compute_device.gd` — declarations at lines 24-28, constants 55-58, `init_collider_storage_buffer()` at 134, `dispatch_collider_pack()` at 663, `read_collider_buffer_coalesced()` at 712, free at 441-443.
- **Sim dispatches each chunk twice per frame** (even phase, then odd phase) in `dispatch_simulation` (`compute_device.gd:566-606`). Push constant is 16 bytes: `phase`(0), `frame_seed`(4), `_pad2`(8), `_pad3`(12). We repurpose `_pad2` as `chunk_slot`.
- **Tests:** gdUnit4. Suites live in `tests/unit/`, extend `GdUnitTestSuite`. Pure `ComputeDevice` decode functions are tested by instantiating `ComputeDevice.new()` with no `RenderingDevice` (see `tests/unit/test_light_decode_hazard.gd`). Run a suite headless with `addons/gdUnit4/runtest.sh`.
- **Branch:** work proceeds on the current branch `feat/content-expansion`.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `shaders/generated/materials.glslinc` / `.gdshaderinc` | Generated material constant arrays incl. `HAS_COLLIDER[]` | Regenerate (no source change) |
| `src/core/compute_device.gd` | GPU dispatch + double-buffered readbacks | Add solidity flag buffer, slot assignment in `dispatch_simulation`, `decode_solidity_flags()` (pure), `read_solidity_flags()`, init + free; **remove blanket dirty** |
| `shaders/compute/simulation.glsl` | Sim entry shader | Add flag SSBO binding 6; rename push-constant `_pad2`→`chunk_slot` |
| `shaders/include/sim/burning.glslinc` | Burning transitions | `atomicOr` flag on solid→air burn |
| `shaders/include/sim/explode_wave.glslinc` | Blast terrain destruction | `atomicOr` flag on solid→air (2 sites) |
| `src/core/chunk_manager.gd` | Builds per-chunk sim uniform set | Bind flag buffer at set 0, binding 6 |
| `src/core/world_manager.gd` | Per-frame orchestration | Init the buffer; read flags + dirty flagged chunks before `_run_simulation` |
| `tests/unit/test_solidity_flags_decode.gd` | Unit test for the pure decoder | Create |

---

## Task 1: Regenerate material shader includes (verify `HAS_COLLIDER`)

**Files:**
- Modify (regenerate): `shaders/generated/materials.glslinc`, `shaders/generated/materials.gdshaderinc`

- [ ] **Step 1: Regenerate the material includes**

Run:
```bash
./generate_materials.sh
```
Expected output:
```
Generated shaders/generated/materials.glslinc
Generated shaders/generated/materials.gdshaderinc
```

- [ ] **Step 2: Verify `HAS_COLLIDER[]` is present and correct**

Run:
```bash
grep -A 16 "const bool HAS_COLLIDER" shaders/generated/materials.glslinc
```
Expected: a `bool[14]` array. With material order AIR, WOOD, STONE, GAS, LAVA, DIRT, COAL, ICE, WATER, BLOOD, OIL, EXPLODE_WAVE, DUST, BEDROCK, the values must be:
`false, true, true, false, false, true, true, true, false, false, false, false, false, true`
(solids = WOOD, STONE, DIRT, COAL, ICE, BEDROCK).

- [ ] **Step 3: Commit (only if the regenerate produced changes)**

```bash
git add shaders/generated/materials.glslinc shaders/generated/materials.gdshaderinc
git commit -m "chore: regenerate material shader includes" || echo "no changes to commit"
```

---

## Task 2: Pure solidity-flag decoder + unit test (TDD)

A side-effect-free function mapping the coalesced flag buffer + dispatch manifest + loaded-chunk set to the list of changed chunk coords. No `RenderingDevice` needed, so it is unit-testable.

**Files:**
- Modify: `src/core/compute_device.gd` (add constants + `decode_solidity_flags`)
- Test: `tests/unit/test_solidity_flags_decode.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_solidity_flags_decode.gd`:
```gdscript
extends GdUnitTestSuite

const SIM_FLAG_SLOT_BYTES := 4

# Build a coalesced flag buffer big enough for `slot_count` u32 slots, then
# set the given slots to non-zero (flagged).
func _make_buffer(slot_count: int, flagged_slots: Array) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(slot_count * SIM_FLAG_SLOT_BYTES)
	buf.fill(0)
	for slot in flagged_slots:
		buf.encode_u32(slot * SIM_FLAG_SLOT_BYTES, 1)
	return buf

# manifest = flat [cx, cy, slot] triples
func _manifest(triples: Array) -> PackedInt32Array:
	var m := PackedInt32Array()
	for t in triples:
		m.append(t[0]); m.append(t[1]); m.append(t[2])
	return m

func _loaded(coords: Array) -> Dictionary:
	var d: Dictionary = {}
	for c in coords:
		d[c] = true
	return d

func test_empty_manifest_returns_empty() -> void:
	var device := ComputeDevice.new()
	var out := device.decode_solidity_flags(PackedByteArray(), PackedInt32Array(), {})
	assert_that(out.size()).is_equal(0)

func test_only_flagged_slots_returned() -> void:
	var device := ComputeDevice.new()
	var manifest := _manifest([[1, 2, 0], [3, 4, 1], [5, 6, 2]])
	var data := _make_buffer(3, [0, 2])  # slots 0 and 2 flagged, slot 1 not
	var loaded := _loaded([Vector2i(1, 2), Vector2i(3, 4), Vector2i(5, 6)])
	var out := device.decode_solidity_flags(data, manifest, loaded)
	assert_that(out).contains_exactly_in_any_order([Vector2i(1, 2), Vector2i(5, 6)])

func test_unloaded_coords_filtered_out() -> void:
	var device := ComputeDevice.new()
	var manifest := _manifest([[1, 2, 0], [3, 4, 1]])
	var data := _make_buffer(2, [0, 1])  # both flagged
	var loaded := _loaded([Vector2i(1, 2)])  # (3,4) was unloaded
	var out := device.decode_solidity_flags(data, manifest, loaded)
	assert_that(out).contains_exactly_in_any_order([Vector2i(1, 2)])

func test_slot_beyond_buffer_is_skipped() -> void:
	var device := ComputeDevice.new()
	var manifest := _manifest([[7, 8, 5]])  # slot 5 but buffer only has 1 slot
	var data := _make_buffer(1, [0])
	var loaded := _loaded([Vector2i(7, 8)])
	var out := device.decode_solidity_flags(data, manifest, loaded)
	assert_that(out.size()).is_equal(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
addons/gdUnit4/runtest.sh -a tests/unit/test_solidity_flags_decode.gd
```
Expected: FAIL — `decode_solidity_flags` does not exist on `ComputeDevice`.

- [ ] **Step 3: Add constants and the pure decoder**

In `src/core/compute_device.gd`, add these constants next to the collider constants (near line 55-58, after `COLLIDER_COALESCED_BUFFER_SIZE`):
```gdscript
const SIM_MAX_CHUNKS := 64
const SIM_FLAG_SLOT_BYTES := 4
const SIM_FLAG_BUFFER_SIZE := SIM_MAX_CHUNKS * SIM_FLAG_SLOT_BYTES
```

Add this function (place it near `read_collider_buffer_coalesced`, e.g. after `decode_collider_slice` around line 763):
```gdscript
# Pure: given the coalesced solidity-flag buffer, the dispatch manifest
# (flat [cx, cy, slot] triples), and the set of currently-loaded chunk coords,
# return the coords whose flag slot is non-zero (a solid->air change happened).
# Slots out of buffer range and coords no longer loaded are skipped.
static func decode_solidity_flags(data: PackedByteArray, manifest: PackedInt32Array, loaded: Dictionary) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var entry_count := manifest.size() / 3
	for i in range(entry_count):
		var slot: int = manifest[i * 3 + 2]
		var off := slot * SIM_FLAG_SLOT_BYTES
		if off + 4 > data.size():
			continue
		if data.decode_u32(off) == 0:
			continue
		var coord := Vector2i(manifest[i * 3], manifest[i * 3 + 1])
		if not loaded.has(coord):
			continue
		changed.append(coord)
	return changed
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
addons/gdUnit4/runtest.sh -a tests/unit/test_solidity_flags_decode.gd
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/compute_device.gd tests/unit/test_solidity_flags_decode.gd
git commit -m "feat: pure solidity-flag decoder + unit test"
```

---

## Task 3: GPU plumbing — flag buffer, shader writes, dispatch, readback, wiring

This is one atomic feature commit: after it the project boots, sets flags on the GPU, reads them back one frame late, and dirties only changed chunks. Adding the shader binding requires the uniform set and buffer to exist together, so these land as a unit.

**Files:**
- Modify: `src/core/compute_device.gd`
- Modify: `shaders/compute/simulation.glsl`
- Modify: `shaders/include/sim/burning.glslinc`
- Modify: `shaders/include/sim/explode_wave.glslinc`
- Modify: `src/core/chunk_manager.gd`
- Modify: `src/core/world_manager.gd`

**Double-buffer note (why a single buffer is correct here):** Each chunk's `sim_uniform_set` is built once and binds a fixed buffer RID; it cannot swap which buffer it writes per frame without rebuilding every set. So we use **one** flag buffer. No-stall reads come from *ordering*: WorldManager reads the buffer at the **start** of the frame (before this frame's sim dispatch zeroes and rewrites it), so it reads last frame's already-completed writes — the same "read previous frame's results" pattern as `read_terrain_probe` / `read_collider_buffer_coalesced`.

- [ ] **Step 1: Add flag-buffer state to `ComputeDevice`**

In `src/core/compute_device.gd`, next to the collider buffer declarations (lines 24-28), add:
```gdscript
var solidity_flag_buffer: RID = RID()
var solidity_dispatch_manifest: PackedInt32Array = PackedInt32Array()
```

- [ ] **Step 2: Add the init function**

In `src/core/compute_device.gd`, add after `init_collider_storage_buffer()` (after line ~144):
```gdscript
func init_solidity_flag_buffer() -> void:
	var zero := PackedByteArray()
	zero.resize(SIM_FLAG_BUFFER_SIZE)
	zero.fill(0)
	solidity_flag_buffer = rd.storage_buffer_create(SIM_FLAG_BUFFER_SIZE)
	rd.buffer_update(solidity_flag_buffer, 0, SIM_FLAG_BUFFER_SIZE, zero)
	solidity_dispatch_manifest = PackedInt32Array()
```

- [ ] **Step 3: Free the buffer in `free_resources`**

In `src/core/compute_device.gd`, inside `free_resources()` (starts line 408), next to the collider buffer free block (lines 441-443), add:
```gdscript
	if solidity_flag_buffer.is_valid():
		rd.free_rid(solidity_flag_buffer)
		solidity_flag_buffer = RID()
```

- [ ] **Step 4: Add the flag SSBO binding to the sim shader**

In `shaders/compute/simulation.glsl`, after the injection buffer block (ends line 33), add:
```glsl
layout(set = 0, binding = 6, std430) buffer SolidityFlags {
	uint flags[];
} solidity;
```

And change the push constant block (lines 14-19) — rename `_pad2` to `chunk_slot`:
```glsl
layout(push_constant, std430) uniform PushConstants {
	int phase;
	int frame_seed;
	int chunk_slot;
	int _pad3;
} pc;
```

- [ ] **Step 5: Flag solid→air burns in `burning.glslinc`**

In `shaders/include/sim/burning.glslinc`, replace the final store (line 84) `imageStore(chunk_tex, pos, make_pixel(material, health, temperature));` with:
```glsl
	int orig_mat = get_material(pixel);
	imageStore(chunk_tex, pos, make_pixel(material, health, temperature));
	if (HAS_COLLIDER[orig_mat] && !HAS_COLLIDER[material]) {
		atomicOr(solidity.flags[pc.chunk_slot], 1u);
	}
```
(`pixel` is the original loaded pixel and is never reassigned in this function, so `get_material(pixel)` is the pre-burn material.)

- [ ] **Step 6: Flag solid→air blast destruction in `explode_wave.glslinc`**

In `shaders/include/sim/explode_wave.glslinc`, at the Branch C destruction (line 97), replace:
```glsl
				if (new_health <= 0) {
					imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
				} else {
```
with:
```glsl
				if (new_health <= 0) {
					imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
					if (HAS_COLLIDER[material]) {
						atomicOr(solidity.flags[pc.chunk_slot], 1u);
					}
				} else {
```

At the Branch D destruction (line 126), replace:
```glsl
				if (new_health <= 0) {
					imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
				} else {
					imageStore(chunk_tex, pos, make_pixel(material, new_health, temperature));
				}
```
with:
```glsl
				if (new_health <= 0) {
					imageStore(chunk_tex, pos, make_pixel(MAT_AIR, 0, SCORCH_TEMP));
					if (HAS_COLLIDER[material]) {
						atomicOr(solidity.flags[pc.chunk_slot], 1u);
					}
				} else {
					imageStore(chunk_tex, pos, make_pixel(material, new_health, temperature));
				}
```
(In Branch C, `material` here is a flammable solid — wood/coal, since oil already returned at line 90 — so `HAS_COLLIDER[material]` is true. In Branch D it is a non-bedrock solid. The guard is precise and self-documenting.)

- [ ] **Step 7: Bind the flag buffer in the sim uniform set**

In `src/core/chunk_manager.gd`, in `build_sim_uniform_set` (lines 221-253), after the injection-buffer uniform `u5` block (lines 247-251) and before `chunk.sim_uniform_set = ...`, add:
```gdscript
	var u6 := RDUniform.new()
	u6.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u6.binding = 6
	u6.add_id(compute.solidity_flag_buffer)
	uniforms.append(u6)
```
The flag buffer is a single global buffer; every chunk's uniform set binds the same buffer and writes only its own slot (via the push-constant `chunk_slot`).

- [ ] **Step 8: Slot assignment + zero + remove blanket dirty in `dispatch_simulation`**

WorldManager reads the buffer at frame start (Step 11), *before* this dispatch zeroes it — so this dispatch is free to clear and re-accumulate.

In `src/core/compute_device.gd`, modify `dispatch_simulation` (lines 566-606).

After the empty-chunks early return (line 567-568), before building `push_even`, insert the zero + slot/manifest bookkeeping:
```gdscript
	# --- Solidity-change flag bookkeeping ---
	# Clear last frame's flags (already read by WorldManager at frame start) and
	# assign each chunk a flag slot for this frame's accumulation.
	var zero := PackedByteArray()
	zero.resize(SIM_FLAG_BUFFER_SIZE)
	zero.fill(0)
	rd.buffer_update(solidity_flag_buffer, 0, SIM_FLAG_BUFFER_SIZE, zero)

	var flag_manifest := PackedInt32Array()
	var slot_of: Dictionary = {}
	var next_slot := 0
	for coord in chunks:
		if next_slot >= SIM_MAX_CHUNKS:
			push_warning("dispatch_simulation: loaded chunks exceed SIM_MAX_CHUNKS; solidity flags dropped for extras")
			break
		slot_of[coord] = next_slot
		flag_manifest.append(coord.x)
		flag_manifest.append(coord.y)
		flag_manifest.append(next_slot)
		next_slot += 1
	solidity_dispatch_manifest = flag_manifest
```

In the **even-phase** loop (lines 583-589), set the per-chunk slot in the push constant. Replace:
```gdscript
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_even, push_even.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
```
with:
```gdscript
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		push_even.encode_s32(8, slot_of.get(coord, 0))
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_even, push_even.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
```

Apply the identical change to the **odd-phase** loop (lines 594-600), using `push_odd`:
```gdscript
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.sim_uniform_set.is_valid():
			continue
		push_odd.encode_s32(8, slot_of.get(coord, 0))
		rd.compute_list_bind_uniform_set(compute_list, chunk.sim_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_odd, push_odd.size())
		rd.compute_list_dispatch(compute_list, NUM_WORKGROUPS, NUM_WORKGROUPS, 1)
```

Finally, **delete the blanket dirty loop** (lines 604-606):
```gdscript
	if world_manager:
		for coord in chunks:
			world_manager.mark_terrain_dirty(coord)
```
(Leave the `shadow_grid` block that follows it intact.)

- [ ] **Step 9: Add `read_solidity_flags`**

In `src/core/compute_device.gd`, add (e.g. after `decode_solidity_flags`). Call this at frame start, before `dispatch_simulation` zeroes the buffer, so it returns the chunk coords that had a solid->air change *last* frame. No stall: last frame's writes have completed and this frame's dispatch has not yet run.
```gdscript
func read_solidity_flags(chunks: Dictionary) -> Array[Vector2i]:
	if solidity_dispatch_manifest.is_empty():
		return []
	var data := rd.buffer_get_data(solidity_flag_buffer, 0, SIM_FLAG_BUFFER_SIZE)
	return decode_solidity_flags(data, solidity_dispatch_manifest, chunks)
```

- [ ] **Step 10: Initialize the buffer at startup**

In `src/core/world_manager.gd`, after `compute_device.init_collider_storage_buffer()` (line 50), add:
```gdscript
	compute_device.init_solidity_flag_buffer()
```

- [ ] **Step 11: Wire the per-frame read + dirty**

In `src/core/world_manager.gd` `_physics_process`, immediately before `_run_simulation()` (line 103), add:
```gdscript
	for coord in compute_device.read_solidity_flags(chunks):
		mark_terrain_dirty(coord)
```

- [ ] **Step 12: Boot the project and verify shaders compile + no errors**

Run:
```bash
godot --headless --quit-after 120 2>&1 | tee /tmp/solidity_boot.log; grep -iE "error|shader.*fail|SCRIPT ERROR|Condition" /tmp/solidity_boot.log || echo "NO ERRORS"
```
Expected: `NO ERRORS`. Specifically there must be **no** shader compile errors for `simulation.glsl`, no "Uniform set 0 is invalid" / binding-mismatch errors, and no GDScript errors. (`--quit-after 120` runs ~120 frames so the sim dispatch and first readback execute.)

If a shader/uniform error appears, the binding count in `build_sim_uniform_set` must match the shader's declared bindings (0-6). Re-check Steps 4 and 7.

- [ ] **Step 13: Commit**

```bash
git add src/core/compute_device.gd src/core/chunk_manager.gd src/core/world_manager.gd \
        shaders/compute/simulation.glsl shaders/include/sim/burning.glslinc shaders/include/sim/explode_wave.glslinc
git commit -m "feat: GPU solidity-changed flag replaces sim per-frame blanket dirty"
```

---

## Task 4: Manual gameplay + profiler verification

No code changes — this confirms the optimization works and nothing regressed. Run the game from the editor (or `godot` with the main scene) and use the in-editor Debugger → Profiler.

- [ ] **Step 1: Steady-state frame budget (the win)**

Load into a level, stand still in an area with flowing lava/gas (or no active hazards). Open the Profiler.
Expected:
- `NavField._drain_tiles` and `read_region` are ≈ 0 ms / 0 calls most frames (they only spike briefly when a wall actually changes).
- `TerrainCollisionHelper.rebuild_dirty` no longer dispatches every chunk every frame.
- Frame time for these systems drops from the previous ~24 ms / ~25 ms toward ~0; overall frame time returns to budget.

- [ ] **Step 2: Digging updates collision + nav**

Carve a tunnel through a wall with a melee swing / projectile.
Expected: enemies route through the new opening; the player collides correctly against the freshly cut edges. (Carving dirties its own chunks explicitly — unaffected by this change.)

- [ ] **Step 3: Burning a wall updates collision + nav**

Ignite a wood wall (fire) and let it burn through; separately, detonate oil against a stone wall (explode wave).
Expected: once the wall clears to air, within a frame or two enemies path through the gap and the player can pass — confirming the GPU flag correctly dirtied those chunks.

- [ ] **Step 4: Regression — intact walls still block**

With walls intact, confirm enemies still route *around* them and the player still collides with them (no walk-through-wall, no invisible walls).

- [ ] **Step 5: Record results**

Note before/after profiler frame times in the PR / commit description. If steady-state frame time is now within budget, sub-projects 2 and 3 (see `docs/design_docs/implementation_todo.md` Phase 8) are likely unnecessary — confirm with the user before proceeding to them.

---

## Task 5 (OPTIONAL — skip unless Task 4 shows flow-field churn): NavField tile-hash skip

The spec lists this as optional. With the GPU flag in place, flagged chunks are rare, and NavField's cost (readback + downsample) happens *before* any hash could help — so this saves almost nothing and changes no behavior. **Only implement if** Step 1 of Task 4 still shows NavField cost from frequently-flagged chunks whose coarse 8-px solidity did not actually change.

**Files:**
- Modify: `src/core/nav/passability_grid.gd`

- [ ] **Step 1: Add a per-chunk tile hash and skip unchanged tiles**

In `src/core/nav/passability_grid.gd`, add a field `var _tile_hashes: Dictionary = {}` and, at the end of `update_chunk` (replace the final `_tiles[chunk_coord] = tile`):
```gdscript
	var h := hash(tile)
	if _tile_hashes.get(chunk_coord, -1) == h and _tiles.has(chunk_coord):
		return
	_tile_hashes[chunk_coord] = h
	_tiles[chunk_coord] = tile
```
Also erase the hash in `drop_chunk`: add `_tile_hashes.erase(chunk_coord)` next to the existing `_tiles.erase(chunk_coord)`.

- [ ] **Step 2: Run the existing nav/passability tests**

Run:
```bash
addons/gdUnit4/runtest.sh -a tests/unit
```
Expected: PASS (no regressions). If a passability test asserts tile identity, confirm it still holds.

- [ ] **Step 3: Commit**

```bash
git add src/core/nav/passability_grid.gd
git commit -m "perf: skip NavField tile store when downsampled solidity is unchanged"
```

---

## Self-Review Notes (addressed during planning)

- **Spec coverage:** GPU flag buffer (Task 3 Steps 1-3, 9), shader flag writes incl. `HAS_COLLIDER` check (Steps 4-6, Task 1), binding 6 (Step 7), `dispatch_simulation` slot assignment + blanket-dirty removal (Step 8), `read_solidity_flags` + WorldManager wiring (Steps 9-11), `build_sim_uniform_set` binding (Step 7), double-buffer no-stall readback (Step 8 snapshot copy), edge cases — buffer cap/warn (Step 8), unloaded-coord filtering + slot-range guard (Task 2 decoder), first-frame guard (Step 9). Optional NavField tile-hash (Task 5). Tests (Task 2). Manual verification (Task 4).
- **No-stall mechanism note (deviation from spec's "swap indices" phrasing):** Per-chunk sim uniform sets bind a fixed buffer RID and cannot swap binding per frame without rebuilding every set. The plan therefore uses a **single flag buffer** and gets the no-stall, one-frame-late read purely from *ordering*: WorldManager reads at frame start (Step 11) before `dispatch_simulation` zeroes and rewrites the buffer (Step 8). The buffer it reads holds last frame's already-completed writes — identical externally observable behavior to a ping-pong double buffer (one-frame latency, no stall), with less machinery. The `solidity_dispatch_manifest` read at frame start is still last frame's, because dispatch overwrites it only *after* the read.
- **Type/name consistency:** `decode_solidity_flags(data, manifest, loaded)` and `read_solidity_flags(chunks)` signatures match between Task 2, Task 3, and the WorldManager call. `solidity_flag_buffer` / `solidity_dispatch_manifest` names are consistent across init, dispatch, read, free, and the uniform-set binding. `SIM_FLAG_SLOT_BYTES`/`SIM_FLAG_BUFFER_SIZE`/`SIM_MAX_CHUNKS` defined once (Task 2 Step 3) and reused. Push-constant `chunk_slot` at byte offset 8 is consistent between shader (Step 4) and `encode_s32(8, ...)` (Step 8).
