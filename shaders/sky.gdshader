shader_type canvas_item;
render_mode unshaded;

uniform vec4 top_color : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.12, 0.06, 0.18, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.65, 0.3, 1.0);
uniform vec3 sun = vec3(0.5, 0.4, 0.12);
uniform float stars = 0.5;
uniform float nebula = 0.3;
uniform float clock = 0.0;
uniform float aspect = 1.777778;
uniform bool reduced_flashes = false;
uniform bool high_contrast = false;
uniform bool planet = false;
uniform vec2 camera_offset = vec2(0.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
        mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}
void fragment() {
    vec2 uv = UV;
    vec2 p = vec2(uv.x * aspect, uv.y) + camera_offset;
    vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
    float cloud = noise(p * 3.0 + vec2(clock * 0.002, 0.0));
    cloud += noise(p * 7.0 - vec2(clock * 0.004, 0.0)) * 0.4;
    cloud += noise(p * 15.0) * 0.18;
    float veil = smoothstep(0.46, 1.1, cloud) * nebula;
    col += mix(sun_color.rgb, vec3(0.28, 0.22, 0.55), 0.7) * veil * 0.22;
    vec2 star_grid = p * 280.0;
    vec2 cell = floor(star_grid);
    float seed = hash(cell);
    vec2 center = vec2(hash(cell + 3.7), hash(cell + 9.1)) * 0.6 + 0.2;
    float star = 1.0 - smoothstep(0.015, 0.12, length(fract(star_grid) - center));
    float flicker = reduced_flashes ? 0.85 : 0.8 + 0.2 * sin(clock * 0.55 + seed * 80.0);
    col += vec3(0.7, 0.84, 1.0) * star * step(0.975, seed) * stars * flicker;
    if (sun.z > 0.0) {
        vec2 delta = (uv - sun.xy) * vec2(aspect, 1.0);
        float r = length(delta);
        float disc = 1.0 - smoothstep(sun.z - 0.002, sun.z + 0.002, r);
        float corona = exp(-abs(r - sun.z) * 22.0) * 0.22;
        vec3 body = sun_color.rgb;
        if (planet) {
            float bands = sin(delta.y * 100.0 + noise(delta * 16.0) * 3.0);
            body *= 0.68 + 0.18 * bands;
            body *= mix(0.16, 1.0, smoothstep(-sun.z, sun.z, delta.x));
        } else {
            float surface = noise(delta * 45.0 + vec2(clock * 0.006));
            body *= 0.8 + 0.2 * surface;
        }
        col = mix(col, body, disc);
        col += sun_color.rgb * corona * (1.0 - disc);
    }
    if (high_contrast) { col *= 0.72; }
    COLOR = vec4(col, 1.0);
}
