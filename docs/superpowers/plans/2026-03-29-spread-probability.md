# Temperature-Scaled Spread Probability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add temperature-scaled probability check for fire spread, making spread more natural and irregular.

**Architecture:** Each burning neighbor rolls a probability check before spreading heat. Probability scales from 0% at IGNITION_TEMP to 70% at FIRE_TEMP.

**Tech Stack:** GLSL compute shader

---

### Task 1: Add spread probability check in simulation shader

**Files:**
- Modify: `shaders/simulation.glsl:85-103`

- [ ] **Step 1: Add probability constant after existing constants**

After line 25 (HEAT_SPREAD constant), add:

```glsl
const float SPREAD_PROB_MAX = 0.7;
```

- [ ] **Step 2: Update heat gain accumulation with probability check**

Replace the heat gain accumulation block (lines 85-103) with:

```glsl
	// Accumulate random heat from each burning neighbor (with probability)
	int heat_gain = 0;
	uint base_rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed)));
	if (is_burning(n_up)) {
		int n_temp = get_temperature(n_up);
		float prob = float(n_temp - IGNITION_TEMP) / float(FIRE_TEMP - IGNITION_TEMP) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 1u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_down)) {
		int n_temp = get_temperature(n_down);
		float prob = float(n_temp - IGNITION_TEMP) / float(FIRE_TEMP - IGNITION_TEMP) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 2u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_left)) {
		int n_temp = get_temperature(n_left);
		float prob = float(n_temp - IGNITION_TEMP) / float(FIRE_TEMP - IGNITION_TEMP) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 3u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 4 + int(rng % uint(HEAT_SPREAD));
		}
	}
	if (is_burning(n_right)) {
		int n_temp = get_temperature(n_right);
		float prob = float(n_temp - IGNITION_TEMP) / float(FIRE_TEMP - IGNITION_TEMP) * SPREAD_PROB_MAX;
		uint rng = hash(base_rng ^ 4u);
		if (rng % 100 < uint(prob * 100.0)) {
			heat_gain += HEAT_SPREAD / 2 + int(rng % uint(HEAT_SPREAD));
		}
	}
```

- [ ] **Step 3: Verify shader compiles**

Run Godot. Expected: No shader errors.

- [ ] **Step 4: Commit**

```bash
git add shaders/simulation.glsl
git commit -m "feat: add temperature-scaled spread probability (0-70%)"
```