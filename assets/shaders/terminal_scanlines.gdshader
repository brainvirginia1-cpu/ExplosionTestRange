shader_type canvas_item;

void fragment() {
	vec2 from_center = UV * 2.0 - 1.0;
	float edge = smoothstep(0.13, 1.75, dot(from_center, from_center));
	float lines = step(0.61, fract(FRAGCOORD.y / 3.0));
	COLOR = vec4(0.042, 0.025, 0.005, lines * 0.11 + edge * 0.18);
}
