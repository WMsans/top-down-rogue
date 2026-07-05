# Dash Fire: Particle-Swarm Bullet (2026-07-05)

## Problem

`DashFireVfx` (`src/enemies/feedback/dash_fire_vfx.gd`) currently draws the lunge
enemy's dash-fire effect as two static `Polygon2D` bullet shapes with a tween-driven
alpha fade and per-frame vertex "wobble". Even with the wobble, it reads as a solid,
rigid bullet — it lost the flickering, living feel of fire and the earlier commit's
sense of speed. The user wants something "completely dynamic: a lot of small
particles combined into a bullet shape, like jumping flame."

## Design

Remove both `Polygon2D` bullet shapes entirely. Replace them with two particle
layers, both parented under the same `DashFireVfx` node and both started/stopped by
the existing `start()`/`stop()` calls from `lunge_enemy.gd`:

1. **Flame-fill layer (`CPUParticles2D`)** — the bullet silhouette itself, made of
   many small particles.
   - `emission_points` is a set of ~50 points sampled inside the existing
     `BULLET_UNIT_POINTS` polygon (rejection-sampled against the polygon at
     `_ready()`, scaled by `body_length`/`body_width`). This is why this layer uses
     CPUParticles2D rather than GPUParticles2D: CPUParticles2D takes a plain
     `PackedVector2Array` for `emission_points`, while GPUParticles2D would require
     baking the same points into an emission texture for no visual benefit at this
     particle count.
   - `amount` ~50, `lifetime` ~0.15s, continuous emission while active — particles
     are constantly recycled so the bullet silhouette always looks "full."
   - Each particle: near-zero base velocity with a wide spread (particles jitter in
     place rather than flying off), a scale curve that pops up quickly then shrinks
     ("jumping" flame lick), and the existing `FIRE_COLOR` → `FIRE_COLOR_FADE`
     color ramp so particles brighten then fade instead of just disappearing.
   - No inner/outer split polygon anymore — flame-color and core-color variation
     comes from `hue_variation`/color ramp randomization across particles instead of
     two fixed shapes.

2. **Trailing tail layer (`GPUParticles2D`, kept from the current implementation)**
   — a lighter spray drifting backward from the bullet for the sense of motion/speed
   as the enemy dashes. Reuses the current `_build_particles()` /
   `_build_process_material()` logic (with turbulence), just detached from the
   removed polygon-alpha logic.

`start(direction)`/`stop()` keep their current responsibilities: aim the node,
restart/stop both particle systems. There is no more tween-driven alpha fade or
`_process()`-based vertex wobble — the particle systems' own emission on/off and
lifetimes naturally produce the fade-in/fade-out feel, so `_animate_intensity`,
`_apply_visual`, `_wobble_points`, and the `Polygon2D` builders are deleted.

`offset_distance`, `body_length`, `body_width` exports are kept (they now size the
emission-point cloud and the tail spray).

## Testing

Manual: trigger a lunge enemy dash in the running game and visually confirm the
bullet-shaped particle swarm flickers/pops in place while a faint trail streams
behind it as the enemy moves. No new automated test — this is a visual-only effect
with no gameplay-affecting logic, consistent with the rest of `src/enemies/feedback/`.
