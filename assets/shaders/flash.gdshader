shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;
uniform float thermonuclear;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = exp(-r * r * 34.0);
	float halo = exp(-r * r * 8.0) * (1.0 - smoothstep(0.35, 1.0, r));
	vec3 aureole = mix(vec3(3.7,1.57,0.41),vec3(4.2,2.56,1.10),thermonuclear);
	vec3 white_core = mix(vec3(4.2,3.5,2.5),vec3(4.9,4.65,4.18),thermonuclear);
	ALBEDO = aureole*halo+white_core*core;
	ALPHA = intensity * clamp(halo * 0.68 + core, 0.0, 1.0);
}
