# Temperature Tint & Random Heat Spread

## Summary
Add temperature-based ember coloring with flickering animation to burning wood, and randomize heat spread for more natural fire behavior.

## Changes

### 1. Simulation Shader (`shaders/simulation.glsl`)

**Add frame seed to push constants:**
```glsl
layout(push_constant, std430) uniform PushConstants {
    int phase;
    int frame_seed;  // NEW: random seed from CPU each frame
    int _pad2;
    int _pad3;
} pc;
```

**Add hash function for deterministic randomness:**
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

**Modify heat spread to use random factor:**
- Replace `temperature += burning_neighbors * HEAT_SPREAD` with randomized amount per neighbor
- Each burning neighbor contributes `HEAT_SPREAD * (0.5 to 1.5)` heat
- Use position and frame seed to generate per-pixel randomness:

```glsl
// In the WOOD case, after counting burning_neighbors:
int total_heat = 0;
for each burning neighbor direction:
    uint rng = hash(uint(pos.x) ^ hash(uint(pos.y) ^ uint(pc.frame_seed ^ direction)));
    float spread_factor = 0.5 + float(rng % 100) / 100.0;
    total_heat += int(HEAT_SPREAD * spread_factor);
temperature = min(255, temperature + total_heat);
```

### 2. World Manager (`scripts/world_manager.gd`)

**Add frame seed to simulation push constants:**
- Generate new random seed each frame using `randi()`
- Encode as second int in push data (currently unused padding):

```gdscript
var push_even := PackedByteArray()
push_even.resize(16)
push_even.encode_s32(0, 0)
push_even.encode_s32(4, randi())  # frame_seed

var push_odd := PackedByteArray()
push_odd.resize(16)
push_odd.encode_s32(0, 1)
push_odd.encode_s32(4, randi())  # frame_seed
```

### 3. Render Shader (`shaders/render_chunk.gdshader`)

**Add TIME uniform for animation:**
```glsl
uniform float TIME;
```

**Add ember color function:**
Temperature-based gradient from dark red through orange to yellow-white:
- Below IGNITION_TEMP (180): normal wood brown color
- At IGNITION_TEMP (180): dark red
- Mid temperature (~220): bright orange  
- Max temperature (255): yellow-white

```glsl
vec3 ember_color(float temp_norm, float flicker_amount) {
    // temp_norm is 0.7-1.0 range for burning (IGNITION_TEMP/255 to 1.0)
    vec3 dark_red = vec3(0.3, 0.0, 0.0);
    vec3 orange = vec3(0.9, 0.4, 0.0);
    vec3 yellow_white = vec3(1.0, 0.9, 0.5);
    
    float adjusted = clamp(temp_norm + flicker_amount * 0.15, 0.0, 1.0);
    if (adjusted < 0.85) {
        return mix(dark_red, orange, (adjusted - 0.7) / 0.15);
    } else {
        return mix(orange, yellow_white, (adjusted - 0.85) / 0.15);
    }
}
```

**Add flicker function:**
Time-based brightness variation using multiple sine waves:

```glsl
float flicker_amount(ivec2 pixel_pos, float time, float temp_norm) {
    float a = sin(time * 8.0 + float(pixel_pos.x) * 0.01 * 3.14159) * 0.5;
    float b = sin(time * 12.0 + float(pixel_pos.y) * 0.01 * 2.71828) * 0.3;
    float c = sin(time * 15.0 + float(pixel_pos.x + pixel_pos.y) * 0.01 * 1.61803) * 0.2;
    float flicker = (a + b + c); // ranges -1 to 1
    // Reduce flicker intensity at higher temperatures (smoother glow)
    return flicker * (1.0 - temp_norm * 0.3);
}
```

**Update material_color function:**
```glsl
vec3 material_color(vec4 data, ivec2 pixel_pos) {
    int mat = get_material(data);
    float temperature = data.b;
    
    if (mat == WOOD) {
        vec3 wood_color = vec3(0.55, 0.35, 0.17);
        float temp_norm = temperature;
        if (temperature > 180.0 / 255.0) {
            // Burning: use ember gradient with flickering
            float flicker = flicker_amount(pixel_pos, TIME, temp_norm);
            return ember_color(temp_norm, flicker);
        }
        return wood_color;
    }
    return vec3(1.0, 0.0, 1.0);
}
```

## Behavior Summary

| Feature | Before | After |
|---------|--------|------|
| Heat spread per burning neighbor | Fixed +10 | Random 5-15 |
| Temperature tint | Brown → Red linear | Brown → DarkRed → Orange → Yellow-White |
| Flickering | None | Time-based brightness variation |
| Random seed source | N/A | Per-frame from CPU |

## Files Modified
- `shaders/simulation.glsl` - Add hash function, use frame_seed for random spread
- `scripts/world_manager.gd` - Generate and pass frame seed via push constant
- `shaders/render_chunk.gdshader` - Add TIME uniform, ember gradient, flickering