shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform vec3 dust_tint : source_color = vec3(0.29, 0.20, 0.13);
uniform float wear : hint_range(0.0, 1.0) = 1.0;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world * 1.9;
	float warp = sin(p.x * 3.4 + p.y * 2.3) * 0.23 + sin(p.z * 8.1 + p.y) * 0.15;
	float cracks = abs(fract(p.x * 0.61 + p.z * 0.76 + p.y * 0.8 + warp) - 0.5);
	float soot = smoothstep(-0.13, 0.65, sin(p.x + p.y * 1.8) * cos(p.z * 0.8 + p.y));
	ALBEDO = mix(vec3(0.059, 0.045, 0.038), dust_tint, soot);
	ROUGHNESS = 0.9;
	ALPHA = wear * max((1.0 - smoothstep(0.018, 0.052, cracks)) * 0.9, soot * 0.29);
}
