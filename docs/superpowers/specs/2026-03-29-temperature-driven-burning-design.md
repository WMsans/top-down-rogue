# Temperature-Driven Burning

## Overview

Replaces the material-based burning system with temperature-driven burning. Wood pixels no longer convert to a separate FIRE material when they ignite. Instead, wood with high temperature is considered "burning" and retains its wood appearance.

## Problem

Currently, when wood exceeds the ignition temperature (180), it converts to material type 2 (FIRE). This makes burning wood visually distinct from wood rather than showing a progression of burning wood that still looks like wood.

## Solution

Keep wood as material WOOD throughout the burning process. Use temperature as the burning indicator.

## Behavior

### Burning Wood

- Wood with temperature > IGNITION_TEMP (180) is "burning"
- Burning wood:
  - Decrements health each tick
  - Spreads HEAT_SPREAD (10) heat per burning neighbor to adjacent wood
  - Temperature stays at max (255) while burning
- When health reaches 0:
  - Becomes air (material=0, health=0, temperature=0)

### Fire Placement

- `place_fire()` sets temperature to 255 on wood at clicked location
- No longer creates FIRE material
- If clicking on air, the action has no effect (or could set temperature but no material to burn)

### Heat Spread

- Burning wood spreads heat to adjacent wood (same behavior as FIRE material previously)
- Air dissipates heat (temperature decreases by HEAT_DISSIPATION=2 each tick)

## Implementation

### simulation.glsl

1. Remove `MAT_FIRE` constant
2. Modify wood handling:
   ```
   if (material == MAT_WOOD) {
       // Count burning neighbors (wood with high temp)
       int burning_neighbors = 0;
       if (get_material(n_up) == MAT_WOOD && get_temperature(n_up) > IGNITION_TEMP) burning_neighbors++;
       if (get_material(n_down) == MAT_WOOD && get_temperature(n_down) > IGNITION_TEMP) burning_neighbors++;
       // ... same for left and right
       
       // Heat spread from burning neighbors
       temperature = min(255, temperature + burning_neighbors * HEAT_SPREAD);
       temperature = max(0, temperature - HEAT_DISSIPATION);
       
       // If burning, consume health
       if (temperature > IGNITION_TEMP) {
           health = health - 1;
           temperature = FIRE_TEMP; // Keep temp high while burning
           if (health <= 0) {
               material = MAT_AIR;
               health = 0;
               temperature = 0;
           }
       }
   }
   ```
3. Remove MAT_FIRE handling block

### render_chunk.gdshader

1. Remove FIRE constant
2. Remove fire material case in `is_solid()` (line 31: `m != AIR && m != FIRE` becomes `m != AIR`)
3. Remove fire rendering case (lines 80-82)
4. Optional: enhance wood burning visual with glow effect based on temperature

### world_manager.gd

1. Modify `place_fire()` function (line 340):
   - Change `data[idx] = 2` to leave as-is (wood) or set to 1 if needed
   - Keep temperature = 255
   - Keep health = 255 (to give full burn duration)

## Files Changed

- `shaders/simulation.glsl` - Remove FIRE material, update wood burning logic
- `shaders/render_chunk.gdshader` - Remove FIRE rendering
- `scripts/world_manager.gd` - Update place_fire to heat wood instead of creating FIRE

## Testing

After changes:
1. Click to place fire on wood - should start burning immediately
2. Burning wood should spread to adjacent wood
3. Burning wood should visually show temperature tint
4. Consumed wood should become air after burn duration