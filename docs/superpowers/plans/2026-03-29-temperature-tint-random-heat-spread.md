# Temperature Tint & Random Heat Spread Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ember-style temperature coloringwith flickering animation and randomized heat spread for more natural fire behavior.

**Architecture:** Modify compute simulation shader to use per-frame random seeds for heat spread variation. Update render shader with TIME-based flickering and ember color gradient (dark red → orange → yellow-white). Pass random seed from GDScript via push constants.

**Tech Stack:** Godot 4, GLSL compute shaders, GDScript

---

## File Structure

| File | Purpose |
|------|---------|
| `shaders/simulation.glsl` | Add hash function, frame_seed push constant, randomize heat spread |
| `scripts/world_manager.gd` | Generate per-frame random seed, pass via push constant |
| `shaders/render_chunk.gdshader` | Add TIME uniform, ember_color function, flicker_amount function, update material_color |

---

### Task 1: Add frame seed to simulation shader push constants

**Files:**
- Modify: `shaders/simulation.glsl:12-17`

- [ ] **Step 1: Update push constants struct**

Change the push constants to include `frame_seed` in the second field (previously `_pad1`):

```glsl
layout(push_constant, std430) uniform PushConstants {
	int phase;
	int frame_seed;
	int _pad2;
	int _pad3;
} pc;
```

- [ ] **Step 2: Verify shader compiles**

Run Godot and check for shader errors in console. Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat: add frame_seed to simulation shader push constants"
```

---

### Task 2: Add hash function and randomize heat spread in simulation shader

**Files:**
- Modify: `shaders/simulation.glsl:54-99`

- [ ] **Step 1: Add hash function before `is_burning`**

Insert after the constant definitions (after line 26):

```glsl
uint hash(uint n) {
	n = (n >> 16) ^ n;
	n *= 0xed5ad0bb;
	n = (n >> 16) ^ n;
	n *= 0xac4c1b51;
	n = (n >> 16) ^ n;
	return n;
}
```

- [ ] **Step 2: Update burning_neighbors counting to accumulate random heat**

Replace the burning neighbor counting and heat application logic. Find this section (approximately lines 76-81 and 86):

```glsl
	// Count burning neighbors (wood with high temperature)
	int burning_neighbors = 0;
	if (is_burning(n_up)) burning_neighbors++;
	if (is_burning(n_down)) burning_neighbors++;
	if (is_burning(n_left)) burning_neighbors++;
	if (is_burning(n_right)) burning_neighbors++;
```

And the heat application:

```glsl
		temperature = min(255, temperature + burning_neighbors * HEAT_SPREAD);
```

Replace with:

```glsl
	// Accumulate random heat from each burning neighbor
	int heat_gain = 0;
	uint base_rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
	if (is_burning(n_up)) {
		uint rng = hash(base_rng ^ 1u);
		heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
	}
	if (is_burning(n_down)) {
		uint rng = hash(base_rng ^ 2u);
		heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
	}
	if (is_burning(n_left)) {
		uint rng = hash(base_rng ^ 3u);
		heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
	}
	if (is_burning(n_right)) {
		uint rng = hash(base_rng ^ 4u);
		heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
	}
```

And replace the temperature line in the MAT_WOOD case with:

```glsl
		temperature = min(255, temperature + heat_gain);
```

- [ ] **Step 3: Verify shader compiles and runs**

Run Godot, place fire on wood, observe burning behavior. Expected: Fire spreads with varying rates.

- [ ] **Step 4: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat: randomize heat spread per burning neighbor using hash"
```

---

### Task 3: Pass frame seed from world_manager.gd

**Files:**
- Modify: `scripts/world_manager.gd:281-287`

- [ ] **Step 1: Update push_even to include frame seed**

Find the push_even definition (approximately line 281-282):

```gdscript
	var push_even := PackedByteArray()
	push_even.resize(16)
	push_even.encode_s32(0, 0)
```

Replace with:

```gdscript
	var push_even := PackedByteArray()
	push_even.resize(16)
	push_even.encode_s32(0, 0)
	push_even.encode_s32(4,randi())
```

- [ ] **Step 2: Update push_odd toinclude frame seed**

Find the push_odd definition (approximately line 285-287):

```gdscript
	var push_odd := PackedByteArray()
	push_odd.resize(16)
	push_odd.encode_s32(0, 1)
```

Replace with:

```gdscript
	var push_odd := PackedByteArray()
	push_odd.resize(16)
	push_odd.encode_s32(0, 1)
	push_odd.encode_s32(4, randi())
```

- [ ] **Step 3: Test simulation still runs**

Run Godot, place fire on wood. Expected: No errors, fire spreads.

- [ ] **Step 4: Commit**

```bash
git add scripts/world_manager.gd
git commit -m "feat: pass per-frame random seed to simulation shader"
```

---

### Task 4: Add TIME uniform to render shader

**Files:**
- Modify: `shaders/render_chunk.gdshader:1-6`

- [ ] **Step 1: Add TIME uniform**

After the existing uniforms (line 5), add:

```glsl
uniform float TIME;
```

- [ ] **Step 2: Verify shader compiles**

Run Godot. Expected: No shader errors.

- [ ] **Step 3: Commit**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat: add TIME uniform for flickering animation"
```

---

### Task 5: Add ember color and flicker functions to render shader

**Files:**
- Modify: `shaders/render_chunk.gdshader:33-47`

- [ ] **Step 1: Add ember_color function after is_solid function**

Insert after `is_solid` function (after line31):

```glsl
vec3 ember_color(float temp_norm, float flicker_amt) {
	vec3 dark_red = vec3(0.3, 0.0, 0.0);
	vec3 orange = vec3(0.9, 0.4, 0.0);
	vec3 yellow_white = vec3(1.0, 0.9, 0.5);
	
	float adjusted = clamp(temp_norm + flicker_amt * 0.15, 0.0, 1.0);
	if (adjusted < 0.85) {
		float t = (adjusted - 0.7) / 0.15;
		return mix(dark_red, orange, t);
	} else {
		float t = (adjusted - 0.85) / 0.15;
		return mix(orange, yellow_white, t);
	}
}

float flicker_amount(ivec2 pixel_pos, float time, float temp_norm) {
	float px = float(pixel_pos.x);
	float py = float(pixel_pos.y);
	float a = sin(time * 8.0 + px * 0.05) * 0.5;
	float b = sin(time * 12.0 + py * 0.03) * 0.3;
	float c = sin(time * 15.0 + (px + py) * 0.04) * 0.2;
	float flicker = a + b + c;
	return flicker * (1.0 - temp_norm * 0.3);
}
```

- [ ] **Step 2: Verify shader compiles**

Run Godot. Expected: No shader errors.

- [ ] **Step 3: Commit**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat: add ember_color and flicker_amount functions"
```

---

### Task 6: Update material_color to use ember gradient

**Files:**
- Modify: `shaders/render_chunk.gdshader:33-47`

- [ ] **Step 1: Update material_color function signature**

Change the function signature to accept pixel position:

```glsl
vec3 material_color(vec4 data, ivec2 pixel_pos) {
```

- [ ] **Step 2: Update material_color body for burning wood**

Replace the entire function body:

```glsl
vec3 material_color(vec4 data, ivec2 pixel_pos) {
	int mat = get_material(data);
	float temperature = data.b;
	
	if (mat == WOOD) {
		vec3 wood_color = vec3(0.55, 0.35, 0.17);
		float temp_norm = temperature;
		if (temperature > 180.0 / 255.0) {
			float flicker = flicker_amount(pixel_pos, TIME, temp_norm);
			return ember_color(temp_norm, flicker);
		}
		return wood_color;
	}
	return vec3(1.0, 0.0, 1.0);
}
```

- [ ] **Step 3: Update call sites in fragment shader**

Find the calls to `material_color` (approximately lines 91 and 101):

```glsl
				vec3 tint = material_color(src_data);
```

and

```glsl
			COLOR = vec4(material_color(data), 1.0);
```

Replace both with:

```glsl
				vec3 tint = material_color(src_data, px);
```

and

```glsl
			COLOR = vec4(material_color(data, px), 1.0);
```

- [ ] **Step 4: Test visual appearance**

Run Godot, place fire on wood. Expected: Burning wood shows ember gradient (dark red → orange → yellow-white) with flickering.

- [ ] **Step 5: Commit**

```bash
git add shaders/render_chunk.gdshader
git commit -m "feat: apply ember gradient and flickering to burning wood"
```

---

### Task 7: Final verification and cleanup

- [ ] **Step 1: Run full visual test**

Run Godot, generate world, place fire on wood. Verify:
1. Fire spreads with irregular patterns (not uniform circles)
2. Burning wood transitions from dark red → orange → yellow-white as temperature increases
3. Flickering animation is visible on burning pixels
4. No console errors

- [ ] **Step 2: Commit any remaining changes**

```bash
git status
git add -A
git commit -m "feat: complete temperature tint and random heat spread"
```