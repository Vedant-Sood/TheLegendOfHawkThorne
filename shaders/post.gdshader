shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 grade : source_color = vec4(1.0);
uniform float clock = 0.0;
uniform float hit = 0.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec2 light_position = vec2(0.5);
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;
uniform bool underwater = false;
uniform bool reduced_flashes = false;
uniform bool high_contrast = false;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
    vec2 uv = SCREEN_UV;
    float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    if (underwater && !reduced_flashes) {
        uv.x += sin(uv.y * 32.0 + clock * 1.3) * 0.0013;
        uv.y += sin(uv.x * 24.0 - clock) * 0.0007;
    }
    uv = clamp(uv, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
    float aberration = reduced_flashes || high_contrast ? 0.0 : hit * 0.004;
    vec2 shift = vec2(aberration, 0.0);
    vec3 col = texture(screen_texture, uv).rgb;
    col.r = texture(screen_texture, clamp(uv + shift, vec2(0.0), vec2(1.0))).r;
    col.b = texture(screen_texture, clamp(uv - shift, vec2(0.0), vec2(1.0))).b;
    col *= mix(vec3(1.0), grade.rgb, high_contrast ? 0.18 : 0.42);
    float luminance = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(col, vec3(luminance), desaturation);
    vec2 centered = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
    float vignette = smoothstep(0.28, 1.0, length(centered));
    col *= 1.0 - vignette * (high_contrast ? 0.08 : 0.3);
    if (!reduced_flashes && !high_contrast) {
        float grain = hash(FRAGCOORD.xy + floor(clock * 24.0)) - 0.5;
        col += grain * 0.012;
    }
    float light_distance = length((SCREEN_UV - light_position) * vec2(aspect, 1.0));
    float mask = smoothstep(0.12, high_contrast ? 0.52 : 0.38, light_distance);
    col *= 1.0 - darkness * mask * (high_contrast ? 0.55 : 0.94);
    COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
