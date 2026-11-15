shader_type canvas_item;
render_mode unshaded;

uniform vec4 fog_color : source_color = vec4(0.2, 0.2, 0.3, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.2;
uniform float clock = 0.0;
uniform bool high_contrast = false;
uniform vec2 camera_offset = vec2(0.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void fragment() {
    vec2 p = UV * vec2(5.0, 3.0) + camera_offset + vec2(clock * 0.015, 0.0);
    float wisps = noise(p) * 0.65 + noise(p * 2.2 - vec2(clock * 0.025, 0.0)) * 0.35;
    float height = smoothstep(0.05, 1.0, UV.y);
    float opacity = density * (0.18 + 0.65 * height) * (0.4 + 0.6 * wisps);
    COLOR = vec4(fog_color.rgb, opacity * (high_contrast ? 0.25 : 1.0));
}
