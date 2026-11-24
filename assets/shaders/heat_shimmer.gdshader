shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D backdrop : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler3D turbulence : repeat_enable, filter_linear;
uniform float elapsed = 0.0;
uniform float strength = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float rim = 1.0 - smoothstep(0.30, 0.97, length(p));
	vec2 uv = vec2(p.x * 0.87, p.y * 1.12) + vec2(0.17, elapsed * 0.88);
	float x = texture(turbulence, vec3(uv, elapsed * 0.19)).r;
	float y = texture(turbulence, vec3(uv * 1.81 + 0.27, elapsed * 0.23 + 0.12)).r;
	vec2 ripple = (vec2(x, y) - 0.5) * vec2(0.011, 0.0065);
	ALBEDO = texture(backdrop, SCREEN_UV + ripple * rim * strength).rgb;
	ALPHA = rim * min(0.72, strength * 0.62);
}
