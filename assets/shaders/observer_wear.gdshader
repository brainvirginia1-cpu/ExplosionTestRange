shader_type spatial;
render_mode depth_draw_never;
uniform float abrasion;
uniform float scorch;
varying vec3 local_surface;
void vertex() {
	local_surface = VERTEX;
}
void fragment() {
	vec3 p = local_surface * 55.0;
	float grain = sin(p.x*1.71 + sin(p.z*2.9))*sin(p.y*2.3 + cos(p.x));
	float patches = sin(p.x*0.21+p.z*0.32)*cos(p.y*0.27+p.z*0.29);
	float ash = smoothstep(0.02,0.67,patches+grain*0.18+scorch*0.32);
	float tears = smoothstep(0.39,0.81,grain*0.34+patches*0.52);
	ALBEDO = mix(vec3(0.22,0.15,0.09),vec3(0.045,0.037,0.033),scorch);
	ROUGHNESS = 0.98;
	ALPHA = max(ash*scorch*0.88,tears*abrasion*0.79);
}
