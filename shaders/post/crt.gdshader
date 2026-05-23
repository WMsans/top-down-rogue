shader_type canvas_item;

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_count : hint_range(100.0, 2000.0) = 540.0;
uniform float curvature : hint_range(0.0, 0.3) = 0.08;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.45;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

const float PI = 3.14159265;

vec2 barrel(vec2 uv, float amount) {
    vec2 cc = uv - 0.5;
    float dist = dot(cc, cc);
    return uv + cc * dist * amount;
}

void fragment() {
    vec2 uv = barrel(SCREEN_UV, curvature);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        vec3 col = texture(screen_tex, uv).rgb;
        float scan = 0.5 + 0.5 * sin(uv.y * scanline_count * PI);
        float scan_factor = mix(1.0, scan, scanline_intensity);
        col *= scan_factor;
        vec2 vc = uv - 0.5;
        float vd = length(vc);
        float vig = smoothstep(0.5 + vignette_softness * 0.5, 0.5 - vignette_softness * 0.5, vd);
        col *= mix(1.0, vig, vignette_strength);
        COLOR = vec4(col, 1.0);
    }
}
