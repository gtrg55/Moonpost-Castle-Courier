shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 center = vec2(0.5);
	vec2 direction = SCREEN_UV - center;
	float edge = smoothstep(0.18, 0.78, length(direction));
	float amount = intensity * edge * 0.018;
	vec4 color = vec4(0.0);
	color += texture(screen_texture, SCREEN_UV - direction * amount * 2.0) * 0.12;
	color += texture(screen_texture, SCREEN_UV - direction * amount) * 0.20;
	color += texture(screen_texture, SCREEN_UV) * 0.36;
	color += texture(screen_texture, SCREEN_UV + direction * amount) * 0.20;
	color += texture(screen_texture, SCREEN_UV + direction * amount * 2.0) * 0.12;
	COLOR = color;
}
