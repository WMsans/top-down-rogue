# Enemy Intent Indicator Design (Soul Knight Style)

**Date:** 2026-05-11
**Status:** Design

## Overview

Add a red exclamation mark (`!`) indicator above enemies during their WINDUP state, telegraphing incoming attacks to the player — similar to Soul Knight.

## Requirements

- Red `!` appears above all enemies (melee, ranged, boss) during WINDUP
- Flash intro animation followed by persistent juicy idle animation
- Quick exit animation when windup ends (attack fires or state interrupted)
- Self-contained scene for reusability and clean separation

## Architecture

### New Scene: `scenes/fx/intent_indicator.tscn`

- Root `Node2D` with script `src/fx/intent_indicator.gd`
- Child `Label` using project pixel font (`SDS_8x8.ttf`), text `!`, red color with dark outline
- Self-contained animation lifecycle — manages its own tweens and cleanup

### Integration in `src/enemies/enemy.gd` (base class)

- Preload the indicator scene in `_ready()`
- **Entering WINDUP**: Instantiate indicator as child, call `show()`
- **Exiting WINDUP** (to ATTACK / HURT / DEATH): Call `hide()` which plays exit animation then `queue_free`s

## Animation Timeline

| Phase | Duration | Behavior |
|-------|----------|----------|
| **Flash in** | ~0.15s | Scale 0 → 1.4 (overshoot) → 1.0 with elastic easing; alpha 0 → 1 |
| **Idle juice** | Remaining windup duration | Subtle scale oscillation (1.0 ↔ 1.08) looping; vertical bob (+2 / -2 px) |
| **Exit** | ~0.1s | Scale to 0 + fade to 0 simultaneously, then `queue_free` |

## Positioning

- 16 px above enemy sprite origin (offsets from `Sprite2D.position`)
- Scales with enemy size — elite enemies at 1.3x scale multiply the offset accordingly

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Death during windup | Indicator plays exit animation alongside death shrink, then frees |
| Multiple enemies windup at once | Each gets its own independent indicator instance (child of respective enemy) |
| Pause during windup | Tweens use `TWEEN_PAUSE_PROCESS` (matches existing UI animation pattern in `ui_animations.gd`) |
| Boss multi-phase | Same behavior, no special treatment |
| Enemy despawns / queue_free during windup | Indicator is a child node, destroyed automatically with parent |

## Files

| File | Action |
|------|--------|
| `scenes/fx/intent_indicator.tscn` | Create |
| `src/fx/intent_indicator.gd` | Create |
| `src/enemies/enemy.gd` | Modify — add indicator lifecycle in FSM |

## Dependencies

- `SDS_8x8.ttf` (already in project)
- `ui_theme.gd` for `DANGER` color constant (optional — can inline `Color.RED`)
- Existing enemy FSM in `enemy.gd` (WINDUP state already defined)
