shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float opacity = 1.0;
uniform float width = 0.08;
uniform bool marker = false;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float breakup = 0.74 + 0.14 * sin(a * 19.0 + r * 12.0) + 0.12 * sin(a * 43.0);
	float edge = marker ? 0.0 : (sin(a * 27.0) + 0.36 * sin(a * 61.0)) * width * 0.08;
	float band = abs(r - 0.87 + edge);
	float halo = 1.0 - smoothstep(width * 0.16, width, band);
	float crest = 1.0 - smoothstep(width * 0.08, width * 0.4, abs(r - 0.89));
	vec3 dust = mix(vec3(0.50, 0.31, 0.16), vec3(1.12, 0.88, 0.60), crest);
	if (marker) {
		float ticks = step(0.18, fract((a + 3.14159265) * 2.546479));
		float cross = (1.0 - smoothstep(0.016, 0.045, min(abs(p.x), abs(p.y)))) * (1.0 - smoothstep(0.2, 0.32, r));
		ALBEDO = vec3(1.0, 0.69, 0.30);
		ALPHA = max(halo * ticks, cross) * opacity;
	} else {
		ALBEDO = dust;
		float trailing = 1.0 - smoothstep(width * 0.15, width * 1.2, abs(r - 0.80 + edge));
		ALPHA = max(max(halo * 0.68, crest * 0.81), trailing * 0.34) * breakup * opacity;
	}
}
