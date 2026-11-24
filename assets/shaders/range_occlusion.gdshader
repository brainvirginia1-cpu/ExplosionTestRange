shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D cloud_field : filter_linear, repeat_disable;
uniform vec3 cloud_min;
uniform vec3 cloud_max;
uniform vec3 sun_direction = vec3(-0.5,0.65,0.4);
uniform float cloud_strength;

#include "res://assets/shaders/explosion_atlas.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy,1.0,1.0);
}

vec3 reconstruct(vec2 uv, float depth, mat4 inverse_projection) {
	vec4 view = inverse_projection*vec4(uv*2.0-1.0,depth,1.0);
	return view.xyz/view.w;
}

float smoke_density(vec3 p) {
	if (any(lessThan(p,vec3(0))) || any(greaterThan(p,vec3(1)))) { return 0.0; }
	vec3 cell = clamp(p*cloud_layout.x-0.5,vec3(0.0),vec3(cloud_layout.x-1.0));
	int layer = int(cell.y);
	vec4 lower = texture(cloud_field,cloud_atlas_uv(layer,cell.xz+0.5));
	vec4 upper = texture(cloud_field,cloud_atlas_uv(min(int(cloud_layout.x)-1,layer+1),cell.xz+0.5));
	return dot(mix(lower,upper,fract(cell.y)),vec4(1.0,0.0,0.36,0.085));
}

float cloud_shadow(vec3 world) {
	vec3 span = cloud_max-cloud_min;
	vec3 p = (world-cloud_min)/span;
	vec3 ray = normalize(sun_direction)/span;
	vec3 inverse_ray = (2.0*step(vec3(0.0),ray)-1.0)/max(abs(ray),vec3(0.00000001));
	vec3 a = -p*inverse_ray;
	vec3 b = (1.0-p)*inverse_ray;
	vec3 lo = min(a,b);
	vec3 hi = max(a,b);
	float near_t = max(0.0,max(lo.x,max(lo.y,lo.z)));
	float far_t = min(hi.x,min(hi.y,hi.z));
	if (far_t <= near_t) { return 0.0; }

	// Integrate a straight path through the cloud. Thin wisps retain a soft edge,
	// while a long path through the core quickly blocks nearly all direct light.
	const int STEPS = 24;
	float segment = (far_t-near_t)/float(STEPS);
	float extinction_per_sample = segment*14.0/max(0.1,span.y);
	vec3 sample_pos = p+ray*(near_t+segment*0.5);
	float extinction = 0.0;
	for (int i=0;i<STEPS;i++) {
		extinction += smoke_density(sample_pos)*extinction_per_sample;
		if (extinction>=3.8) { break; }
		sample_pos += ray*segment;
	}
	float occlusion = 1.0-exp(-extinction);
	float solid_core = smoothstep(1.65,3.75,extinction);
	return mix(occlusion,1.0,solid_core)*smoothstep(0.0,0.23,extinction)*cloud_strength;
}

void fragment() {
	if (cloud_strength<=0.001) { discard; }
	float depth = texture(scene_depth,SCREEN_UV).r;
	if (depth<=0.0) { discard; }
	vec3 view = reconstruct(SCREEN_UV,depth,INV_PROJECTION_MATRIX);
	vec3 world = (INV_VIEW_MATRIX*vec4(view,1.0)).xyz;
	ALBEDO = vec3(0.004);
	ALPHA = cloud_shadow(world);
}
