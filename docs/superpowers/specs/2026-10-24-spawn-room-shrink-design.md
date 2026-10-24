# Spawn Room Shrink — Design (small change)

## Intent
Make the guidance (spawn) room a small, clean circle, and have the player and
camera start inside it on the first frame. Today the player sits at (0,0) while
chunks load, then teleports to the room, so the minimap fog reveals an extra
patch at the start.

## Goals
- Guidance room radius 80px.
- Remove the signs (plaque set).
- Lanterns pulled in to fit the smaller room.
- First minimap reveal and camera position are at the room, with no camera pan.

## Non-goals
- Forest prop keep-out changes (props don't spawn in the room).
- Any other room or biome.

## Approaches
1. **Pre-place the player (chosen).** Set `position` to the guidance center
   before the chunk-load await in `player_controller.gd`, then call
   `reset_smoothing()` on the Camera2D after the final placement. ~2 lines.
2. Hide until placed: gate the minimap reveal and camera on a "placed" flag.
   Rejected: more code, same outcome.

## Decided
- `guidance_room_composition.tres`: `nominal_radius`, `inner_disc_radius`, and the
  floor overlay `radius` go to 80; wood wall `inner_radius` 72 / `outer_radius` 80.
- Remove the plaque set feature, its plaque sub-resources and their ext_resources.
- Lantern offsets go from ±70 to ±40.

## Builder's calls (flag if wrong)
- Lantern `light_radius` stays 200 so the area beyond the wall stays lit.
- The sign textures stay on disk (only references are removed).
