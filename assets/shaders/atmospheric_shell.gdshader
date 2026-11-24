shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/weather_lighting.gdshaderinc"

uniform sampler2D backdrop : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D turbulence : repeat_enable, filter_linear;
uniform float wave_radius = 1.0;
uniform float band_width = 0.08;
uniform float condensation;
uniform float shimmer;
uniform float ground_level;
uniform float elapsed;

varying vec3 sphere_surface;
varying flat vec3 center;

void vertex() {
	center = MODEL_MATRIX[3].xyz;
	sphere_surface = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float interval_length(float start, float end) {
	return max(0.0, end - start);
}

// Integrate the density and its brightness through each visible part of the shell.
vec2 sample_vapor(vec3 eye, vec3 ray, float start, float end) {
	float step_size = interval_length(start, end) / 4.0;
	if (step_size <= 0.0) { return vec2(0.0); }
	vec2 sum = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec3 point = eye + ray * (start + (float(i) + 0.5) * step_size);
		float altitude = center.y + point.y * wave_radius - ground_level;
		float ground_mask = smoothstep(0.0, max(0.08, wave_radius * 0.027), altitude);
		float broad = texture(turbulence, point * 2.3 + vec3(0.23, elapsed * 0.038, 0.61)).r;
		float fine = texture(turbulence, point * 6.4 + vec3(0.43, elapsed * 0.052, 0.71)).r;
		float texture_value = broad * 0.71 + fine * 0.29;
		float layer = (1.0 - length(point)) / band_width;
		float falloff = smoothstep(0.0, 0.26 + 0.28 * fine, layer)
			* (1.0 - smoothstep(0.75, 1.0, layer));
		float density = ground_mask * falloff
			* mix(0.48, 1.42, smoothstep(0.24, 0.77, texture_value));
		sum += density * vec2(1.0, mix(0.67, 1.07, texture_value));
	}
	return sum * step_size / band_width;
}

void fragment() {
	vec3 ray = normalize(sphere_surface - CAMERA_POSITION_WORLD);
	vec3 eye = (CAMERA_POSITION_WORLD - center) / wave_radius;
	float along = dot(eye, ray);
	vec3 nearest = eye - along * ray;
	float distance_squared = dot(nearest, nearest);
	if (distance_squared >= 1.0) { discard; }

	float chord = sqrt(1.0 - distance_squared);
	float start = max(0.0, -along - chord);
	float end = -along + chord;
	float depth = texture(scene_depth, SCREEN_UV).r;
	if (depth > 0.0) {
		vec4 opaque = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		end = min(end, length(opaque.xyz / opaque.w) / wave_radius);
	}
	if (end <= start) { discard; }

	// Subtract the empty interior from the visible chord through the shell.
	float inner_radius = 1.0 - band_width;
	float sample_t = (start + end) * 0.5;
	vec2 vapor_field;
	if (distance_squared < inner_radius * inner_radius) {
		float inner_chord = sqrt(inner_radius * inner_radius - distance_squared);
		float front_end = min(end, -along - inner_chord);
		float back_start = max(start, -along + inner_chord);
		float near_path = interval_length(start, front_end);
		float far_path = interval_length(back_start, end);
		float separated = smoothstep(0.0, band_width * 2.3, inner_chord);
		vapor_field = sample_vapor(eye, ray, start, front_end)
			+ sample_vapor(eye, ray, back_start, end) * mix(1.0, 0.55, separated);
		float shell_sample = near_path > 0.0 ? (start + front_end) * 0.5 : (back_start + end) * 0.5;
		sample_t = mix(sample_t, shell_sample, separated);
	} else {
		vapor_field = sample_vapor(eye, ray, start, end);
	}
	if (vapor_field.x <= 0.0) { discard; }
	vec3 sample_point = eye + ray * sample_t;
	vec3 radial = normalize(sample_point);
	float limb = 1.0 - smoothstep(0.095, 0.72, abs(dot(radial, ray)));
	float wisps = vapor_field.y / vapor_field.x;
	float edge = smoothstep(0.0, 0.60, vapor_field.x);
	float optical_depth = min(vapor_field.x, 3.3) * condensation;
	float vapor = 1.0 - exp(-optical_depth * (4.4 + 1.0 * limb));
	float air_bend = shimmer * edge * (0.18 + 0.82 * limb);

	vec2 direction = (VIEW_MATRIX * vec4(radial, 0.0)).xy;
	vec2 shift = direction * air_bend * (0.0026 + 0.0045 * wisps);
	float depth_jump = abs(texture(scene_depth, SCREEN_UV + shift).r - depth);
	shift *= 1.0 - smoothstep(0.00035, 0.0025, depth_jump);
	vec3 refracted = texture(backdrop, SCREEN_UV + shift).rgb;
	vec3 vapor_position = center+sample_point*wave_radius;
	float sun_side = smoothstep(-0.87,0.82,dot(radial,weather_sun));
	vec3 pearl = vec3(1.0,0.98,0.95)*weather_effect_light(0.53+0.58*sun_side)*wisps;
	pearl += weather_flare(vapor_position)*0.21;
	float opacity = clamp(vapor + (1.0 - vapor) * 0.26 * air_bend, 0.0, 0.985);
	ALBEDO = mix(refracted, pearl, min(1.0, vapor / max(0.001, opacity)));
	ALPHA = opacity;
}
