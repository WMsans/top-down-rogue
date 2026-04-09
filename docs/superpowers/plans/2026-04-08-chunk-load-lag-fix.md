# Chunk-Load Lag Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the ~0.5s stall that occurs when a row of new chunks enters the view.

**Architecture:** Frame-budget collision rebuilds to one chunk per frame (nearest-to-player first), and replace the synchronous burning-state texture readback with CPU-side bookkeeping refreshed only on a low-frequency tick.

**Tech Stack:** Godot 4 / GDScript, RenderingDevice compute shaders.

**Spec:** `docs/superpowers/specs/2026-04-08-chunk-load-lag-fix-design.md`

**Note on testing:** This Godot project has no automated test framework. Verification is done by running the game in the editor and observing chunk-loading behavior. Each task ends with explicit manual verification steps.

---

## File Structure

- `scripts/chunk.gd` — add `has_burning` field, plus a counter for low-frequency burning rechecks.
- `scripts/world_manager.gd` — frame-budget queue logic in `_rebuild_dirty_collisions`, drop the per-rebuild `_check_chunk_burning` call, set `has_burning` from `place_fire`.

No new files. No shader changes. Total diff target: ~60 lines.

---

### Task 1: Add `has_burning` field to `Chunk`

**Files:**
- Modify: `scripts/chunk.gd`

- [ ] **Step 1: Add the field**

Edit `scripts/chunk.gd`. After the existing `last_collision_time` field, add:

```gdscript
var has_burning: bool = false
var burning_recheck_counter: int = 0
```

The full file should now look like:

```gdscript
class_name Chunk
extends RefCounted

var coord: Vector2i
var rd_texture: RID
var texture_2d_rd: Texture2DRD
var mesh_instance: MeshInstance2D
var wall_mesh_instance: MeshInstance2D
var sim_uniform_set: RID
var injection_buffer: RID
var static_body: StaticBody2D
var collision_dirty: bool = true
var last_collision_time: float = 0.0
var has_burning: bool = false
var burning_recheck_counter: int = 0
```

- [ ] **Step 2: Verify the project still parses**

Open the Godot editor (or run `godot --headless --check-only` if available) and confirm there are no parse errors. The game should still launch without behavioral changes (the new fields are unused so far).

- [ ] **Step 3: Commit**

```bash
git add scripts/chunk.gd
git commit -m "feat(chunk): add has_burning state field"
```

---

### Task 2: Set `has_burning` from `place_fire`

**Files:**
- Modify: `scripts/world_manager.gd` (the `place_fire` function near the bottom of the file)

This wires up the producer side of the new flag so we know which chunks have active fire without reading the GPU texture.

- [ ] **Step 1: Update `place_fire` to set the flag**

In `scripts/world_manager.gd`, find the loop in `place_fire` that ends with `chunk.collision_dirty = true`. Replace that block:

```gdscript
		if modified:
			rd.texture_update(chunk.rd_texture, 0, data)
			chunk.collision_dirty = true
```

with:

```gdscript
		if modified:
			rd.texture_update(chunk.rd_texture, 0, data)
			chunk.collision_dirty = true
			chunk.has_burning = true
```

- [ ] **Step 2: Verify no parse errors**

Reload the project in the Godot editor. No errors expected.

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat(world): mark chunks has_burning when fire is placed"
```

---

### Task 3: Replace `_check_chunk_burning` with `has_burning` flag (no readback in hot path)

**Files:**
- Modify: `scripts/world_manager.gd` — `_rebuild_dirty_collisions`, `_rebuild_chunk_collision_gpu`, and `_check_chunk_burning`

The existing code calls `_check_chunk_burning` after every successful GPU rebuild. That function does a full `rd.texture_get_data` (sync stall) and iterates 65 536 pixels. We replace it with the cached `chunk.has_burning` flag, refreshed only every 10th rebuild for fire-decay correctness.

- [ ] **Step 1: Change the post-rebuild logic in `_rebuild_dirty_collisions`**

Find this block in `_rebuild_dirty_collisions`:

```gdscript
		var success := _rebuild_chunk_collision_gpu(chunk)
		if not success:
			_rebuild_chunk_collision_cpu(chunk)
		else:
			chunk.collision_dirty = _check_chunk_burning(chunk)
		
		chunk.last_collision_time = now
```

Replace with:

```gdscript
		var success := _rebuild_chunk_collision_gpu(chunk)
		if not success:
			_rebuild_chunk_collision_cpu(chunk)
		else:
			# Refresh has_burning every 10th rebuild (~3s) so fires that
			# burn out eventually stop triggering rebuilds, without paying
			# a texture readback on every rebuild.
			chunk.burning_recheck_counter += 1
			if chunk.burning_recheck_counter >= 10:
				chunk.burning_recheck_counter = 0
				chunk.has_burning = _check_chunk_burning(chunk)
			chunk.collision_dirty = chunk.has_burning
		
		chunk.last_collision_time = now
```

- [ ] **Step 2: Manual verification — load the game**

Launch the game in the editor. Walk around and confirm chunks still generate and have collision. Place a fire (whatever input triggers `place_fire`) and confirm it still burns terrain (the burning behavior is unchanged — we just refresh the flag less often).

- [ ] **Step 3: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "perf(world): cache has_burning instead of readback per rebuild"
```

---

### Task 4: Frame-budget collision rebuilds (one chunk per frame, nearest first)

**Files:**
- Modify: `scripts/world_manager.gd` — `_rebuild_dirty_collisions`

This is the change that actually eliminates the spike. Instead of rebuilding every dirty chunk on the same frame, we pick the single highest-priority dirty chunk (closest to `tracking_position`) and rebuild only that one.

For *re-rebuilds* (already-built chunks whose `has_burning` keeps them dirty), we still respect `COLLISION_UPDATE_INTERVAL`. For *initial* builds (new chunks with `last_collision_time == 0.0`), we bypass the interval gate so they get collision as soon as their queue turn arrives.

- [ ] **Step 1: Rewrite `_rebuild_dirty_collisions`**

Replace the entire current `_rebuild_dirty_collisions` function:

```gdscript
func _rebuild_dirty_collisions() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.collision_dirty:
			continue
		if now - chunk.last_collision_time < COLLISION_UPDATE_INTERVAL:
			continue
		
		var success := _rebuild_chunk_collision_gpu(chunk)
		if not success:
			_rebuild_chunk_collision_cpu(chunk)
		else:
			chunk.burning_recheck_counter += 1
			if chunk.burning_recheck_counter >= 10:
				chunk.burning_recheck_counter = 0
				chunk.has_burning = _check_chunk_burning(chunk)
			chunk.collision_dirty = chunk.has_burning
		
		chunk.last_collision_time = now
```

with:

```gdscript
func _rebuild_dirty_collisions() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var tracking_chunk := Vector2(
		tracking_position.x / CHUNK_SIZE,
		tracking_position.y / CHUNK_SIZE
	)

	# Find the single highest-priority dirty chunk this frame.
	# Initial builds (last_collision_time == 0.0) bypass the interval gate;
	# re-rebuilds of already-built chunks still wait COLLISION_UPDATE_INTERVAL.
	var best: Chunk = null
	var best_dist_sq := INF
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if not chunk.collision_dirty:
			continue
		var is_initial: bool = chunk.last_collision_time == 0.0
		if not is_initial and now - chunk.last_collision_time < COLLISION_UPDATE_INTERVAL:
			continue
		var d := Vector2(coord) - tracking_chunk
		var dist_sq := d.x * d.x + d.y * d.y
		# Prioritize initial builds over re-rebuilds at equal distance by
		# subtracting a constant; this keeps newly-loaded chunks ahead.
		if is_initial:
			dist_sq -= 10000.0
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = chunk

	if best == null:
		return

	var success := _rebuild_chunk_collision_gpu(best)
	if not success:
		_rebuild_chunk_collision_cpu(best)
	else:
		best.burning_recheck_counter += 1
		if best.burning_recheck_counter >= 10:
			best.burning_recheck_counter = 0
			best.has_burning = _check_chunk_burning(best)
		best.collision_dirty = best.has_burning

	best.last_collision_time = now
```

- [ ] **Step 2: Manual verification — measure the spike**

Launch the game. Walk in a straight line to force chunk-row loads. The previous half-second hitch should be gone — collisions for new chunks should appear over the next several frames instead of all at once.

If you have the in-editor frame-time monitor open (Debugger → Monitor → Frame Time), watch for the spike on chunk-load. It should be substantially smaller and bounded to a single chunk's rebuild cost.

- [ ] **Step 3: Verify collision correctness**

Walk into a freshly-loaded chunk. The player must not fall through terrain. If a new chunk appears but its collision is still pending (because earlier chunks in the queue haven't finished), the player should encounter it ~1–2 frames later — not noticeable at 60 fps because a chunk is 256 px wide and the player can't cross it that fast.

If you observe the player passing through terrain in newly-loaded chunks, raise the per-frame budget by processing the **two** best chunks instead of one (extend the loop in Step 1 to run twice).

- [ ] **Step 4: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "perf(world): frame-budget chunk collision rebuilds (one per frame)"
```

---

### Task 5: Final verification and cleanup check

- [ ] **Step 1: Re-read the modified function**

Read `scripts/world_manager.gd` around `_rebuild_dirty_collisions` and confirm:
- No reference to the old per-rebuild `_check_chunk_burning` call outside the once-per-10-rebuilds path.
- `_check_chunk_burning` itself is still defined (we still call it for the periodic refresh — do not delete it).
- `tracking_position` is the field used for distance, matching how `_get_desired_chunks` already uses it.

- [ ] **Step 2: Smoke test all gameplay paths**

Launch the game and exercise:
- Walking across multiple chunk boundaries in different directions.
- Placing fire on flammable terrain — confirm it burns and that collision updates as terrain is destroyed (may lag by up to 3 seconds for the burning-state refresh, which is the intended trade-off).
- Standing still — no spurious rebuilds (look at frame time, should be flat).

- [ ] **Step 3: Final commit if anything was tweaked**

If the smoke test surfaced any small fix, commit it:

```bash
git add scripts/world_manager.gd
git commit -m "fix(world): <describe tweak>"
```

Otherwise, no commit needed. The optimization is complete.
