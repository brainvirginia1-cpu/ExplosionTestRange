global uniform vec2 weather_state; // rain, night
global uniform vec3 weather_sun;
global uniform vec4 weather_flash; // world position and light range
global uniform float weather_flash_gain;

vec3 weather_effect_light(float shade) {
	vec3 ambient = mix(vec3(0.52, 0.49, 0.46), vec3(0.21, 0.25, 0.34), weather_state.y);
	vec3 direct = mix(vec3(0.56, 0.52, 0.46), vec3(0.24, 0.29, 0.40), weather_state.y);
	return ambient + direct * shade * (1.0 - 0.34 * weather_state.x);
}

vec3 weather_flare(vec3 world) {
	if (weather_flash_gain <= 0.001) { return vec3(0.0); }
	float proximity = length(world - weather_flash.xyz) / max(0.1, weather_flash.w);
	return vec3(1.0, 0.52, 0.24) * weather_flash_gain * exp(-proximity * proximity * 2.0);
}
