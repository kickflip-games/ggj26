shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back;

// Per-instance control without breaking batching.
instance uniform float static_intensity : hint_range(0.0, 1.0) = 0.3;
instance uniform float power : hint_range(0.0, 5.0) = 0.0;

uniform float scanline_count : hint_range(0.0, 1000.0) = 400.0;
uniform float flicker_speed : hint_range(0.0, 20.0) = 10.0;

uniform bool use_image_texture = false;
uniform sampler2D image_texture : source_color, repeat_disable, filter_nearest;
uniform bool use_screen_texture = false;
uniform vec4 base_color : source_color = vec4(0.07, 0.07, 0.07, 1.0);
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec2 mesh_uv = UV;

	float flicker = sin(TIME * flicker_speed) * 0.05 + 0.95;
	float grain = random(screen_uv + fract(TIME * 0.99));

	float lines = clamp(sin(screen_uv.y * scanline_count + TIME * 2.0), 0.7, 1.0);
	float vignette = pow(screen_uv.x * screen_uv.y * (1.0 - screen_uv.x) * (1.0 - screen_uv.y) * 15.0, 0.25);

	vec3 screen_color = base_color.rgb;
	if (use_image_texture) {
		screen_color = texture(image_texture, mesh_uv).rgb;
	} else if (use_screen_texture) {
		screen_color = texture(screen_texture, screen_uv).rgb;
	}
	vec3 final_color = mix(screen_color, vec3(grain), static_intensity);
	vec3 shaded = final_color * lines * flicker * vignette * power;

	ALBEDO = shaded;
	EMISSION = shaded;
}
