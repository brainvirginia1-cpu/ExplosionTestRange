shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/weather_lighting.gdshaderinc"

uniform float life = 0.0;
uniform float weight = 1.0;
uniform float seed = 0.0;
uniform int form = 0;
uniform int samples = 12;
uniform float volume_radius = 40.0;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
varying flat vec3 cloud_center;

float hash3(vec3 p) {
	p = fract(p * 0.317 + vec3(0.112, 0.317, 0.651)) * 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 lo = vec4(hash3(i), hash3(i + vec3(1,0,0)), hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)));
	vec4 hi = vec4(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), hash3(i + vec3(0,1,1)), hash3(i + 1.0));
	vec4 m = mix(lo, hi, f.z);
	return mix(mix(m.x,m.y,f.x), mix(m.z,m.w,f.x), f.y);
}

void vertex() {
	cloud_center = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float shape_clip = dot(uv, uv);
	if (shape_clip >= 1.0) {
		discard;
	}
	float depth = sqrt(1.0 - shape_clip);
	float raw_depth = texture(scene_depth, SCREEN_UV).r;
	vec4 scene_point = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	float opaque_distance = -scene_point.z / scene_point.w;
	float plane_distance = -VERTEX.z;
	vec3 sun = (VIEW_MATRIX*vec4(weather_sun,0.0)).xyz;
	vec3 environment_light = weather_effect_light(1.0);
	vec3 flare = weather_flare(cloud_center);
	vec4 result = vec4(0.0);
	for (int i = 0; i < 14; i++) {
		if (i >= samples || result.a > 0.986) {
			break;
		}
		vec3 p = vec3(uv, mix(depth, -depth, (float(i) + 0.5) / float(samples)));
		float broad = noise3(p * 3.8 + vec3(seed, -life * 0.31, life * 0.12));
		float billow = noise3(p * 8.7 + (broad - 0.5) * 1.33 + seed);
		float erosion = noise3(p * 18.2 + vec3(4.8, -life * 0.12, seed));
		float displaced = 0.71 - length(p) + (broad - 0.46) * 0.65 + (billow - 0.48) * 0.24 + (erosion - 0.50) * 0.11;
		if (form == 1) {
			displaced += 0.13 * sin(p.x * 8.0 + p.z * 4.0) - abs(p.y) * 0.07;
		}
		float sample_distance = plane_distance - p.z * volume_radius * 0.63;
		float opaque_fade = smoothstep(0.0, max(0.35, volume_radius * 0.07), opaque_distance - sample_distance);
		float extinction = smoothstep(-0.051, 0.32, displaced) * depth * 3.9 * opaque_fade / float(samples);
		float sunlight = noise3(p * 3.8 + sun * 0.88 + vec3(seed, -life * 0.31, life * 0.12));
		float shading = clamp(0.30 + dot(p,sun)*0.32 + (broad - sunlight) * 1.13 + billow * 0.39 + erosion * 0.13, 0.0, 1.0);
		vec3 cold = mix(vec3(0.022, 0.019, 0.021), vec3(0.28, 0.219, 0.171), shading);
		if (form == 1) {
			cold = mix(vec3(0.037, 0.031, 0.036), vec3(0.51, 0.436, 0.345), shading);
		}
			if (form == 3) {
			cold = mix(vec3(0.16, 0.085, 0.043), vec3(0.52, 0.34, 0.19), shading);
		}
		float heat = (1.0 - smoothstep(0.8, 4.6, life)) * (form == 2 ? 1.0 : 0.0);
		float fuel = smoothstep(0.20, 0.77, broad * 0.63 + billow * 0.28 + displaced * 0.69) * heat;
		vec3 flame = mix(vec3(2.6, 0.227, 0.016), vec3(5.4, 3.62, 1.17), fuel);
		vec3 color = mix(cold * (environment_light + flare * 0.55), flame, fuel);
		float blend = (1.0 - result.a) * extinction;
		result += vec4(color * blend, blend);
	}
	ALBEDO = result.rgb / max(result.a, 0.001);
	ALPHA = clamp(result.a * weight, 0.0, 0.99);
}
