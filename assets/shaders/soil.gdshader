shader_type spatial;

varying vec3 world;
varying vec3 ground_normal;
uniform vec4 craters[16];
uniform int crater_count = 0;
uniform vec4 shock = vec4(0.0);
uniform float wetness;
uniform vec4 ground_split;
instance uniform bool distant_ground = false;
uniform float shock_limit = 0.0;
uniform float shock_progress = 0.0;
uniform float shock_elevation = 0.0;

float random_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(random_cell(i), random_cell(i + vec2(1, 0)), f.x),
		mix(random_cell(i + vec2(0, 1)), random_cell(i + 1.0), f.x), f.y);
}

float filtered_noise(vec2 p, float pixel_width, float frequency) {
	float detail = 1.0-smoothstep(0.27,0.92,pixel_width*frequency);
	return mix(0.5,noise2(p*frequency),detail);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 p = world.xz;
	if (distant_ground) {
		for (int i = 0; i < crater_count; i++) {
			if (distance(p,craters[i].xy) < craters[i].z*1.20) { discard; }
		}
		if (ground_split.z > 0.0 && distance(p,ground_split.xy) < ground_split.z*0.98) { discard; }
	}
	float footprint = max(length(dFdx(p)),length(dFdy(p)));
	float broad = filtered_noise(p,footprint,0.16)*0.55
		+filtered_noise(p,footprint,0.8)*0.25+filtered_noise(p,footprint,9.0)*0.20;
	vec3 sand = mix(vec3(0.21, 0.125, 0.067), vec3(0.52, 0.34, 0.20), broad);
	float grit = smoothstep(0.67, 0.94, noise2(p * 21.0));
	sand *= 0.95 + grit * 0.24 * (1.0 - smoothstep(0.03, 0.13, footprint));
	float road = 1.0 - smoothstep(2.6, 3.3, abs(p.x + 12.0 + 0.32 * noise2(p * 0.4)));
	float track = (1.0 - smoothstep(0.02, 0.15, abs(abs(p.x + 12.0) - 1.0)));
	vec3 road_color = mix(vec3(0.29, 0.22, 0.16), vec3(0.39, 0.30, 0.22), broad) * (1.0 - track * 0.17);
	float strata = distant_ground ? 1.0 : 0.90+0.10*sin(world.y*2.2+broad*4.0);
	ALBEDO = mix(sand * strata, road_color, max(road * (1.0 - smoothstep(86.0, 96.0, abs(p.y))),
		0.73 * (1.0 - smoothstep(1.9, 2.55, abs(p.y + 27.0 + 0.39 * noise2(p * 0.34)))) * (1.0 - smoothstep(52.0, 60.0, abs(p.x))) ));
	float main_road = (1.0 - smoothstep(3.1, 4.1, abs(p.x + 12.0 + noise2(p * 0.05)))) * (1.0 - smoothstep(929.0, 1020.0, abs(p.y)));
	float service_road = (1.0 - smoothstep(2.6, 4.3, abs(p.y + 270.0 + noise2(p * 0.017) * 2.7))) * (1.0 - smoothstep(875.0, 1020.0, abs(p.x)));
	ALBEDO = mix(ALBEDO, road_color, max(main_road, service_road) * 0.86);
	ALBEDO *= 0.83+0.25*filtered_noise(p,footprint,0.014)+0.079*filtered_noise(p,footprint,0.05);
	for (int i = 0; i < crater_count; i++) {
		vec2 radial = p - craters[i].xy;
		float r = length(radial) / craters[i].z;
		float edge = 0.10 * noise2(radial * 0.55) + 0.05 * broad;
		float mouth = 1.0 - smoothstep(0.91, 1.01, r + edge * 0.33);
		float floor_mask = 1.0 - smoothstep(0.17, 0.68, r + edge);
		float depth_band = sin(world.y / max(0.14, craters[i].w * 0.12) + broad * 3.0);
		float steepness = clamp(1.0 - normalize(ground_normal).y, 0.0, 1.0);
		vec3 open_earth = mix(vec3(0.094, 0.046, 0.024), vec3(0.50, 0.26, 0.105), broad * 0.46 + smoothstep(-0.4, 0.8, depth_band) * 0.44);
		vec3 dark_floor = mix(vec3(0.027, 0.013, 0.009), vec3(0.115, 0.062, 0.032), broad);
		float spoil = smoothstep(0.70, 0.94, r) * (1.0 - smoothstep(1.04, 1.31, r + edge * 0.65));
		ALBEDO = mix(ALBEDO, mix(open_earth * (1.0 - steepness * 0.42), dark_floor, floor_mask), mouth * 0.97);
		ALBEDO = mix(ALBEDO, vec3(0.43, 0.245, 0.106) * (0.78 + broad * 0.55), spoil * 0.66);
	}
	if (ground_split.z>0.0 && ground_split.w>0.0) {
		vec2 offset = (p-ground_split.xy)/ground_split.z;
		float r = length(offset);
		float angle = atan(offset.y,offset.x+0.00001);
		float jag = noise2(offset*31.0)-0.5;
		float spoke = abs(sin(angle*4.0 + jag*0.21 + r*2.5));
		float ring = abs(sin(r*13.0 + jag*0.29 + 0.52*sin(angle*5.0)));
		float opening = mix(0.025,0.092,ground_split.w);
		float breaks = max(1.0-smoothstep(opening,opening+0.04,spoke),
			(1.0-smoothstep(opening,opening+0.056,ring))*smoothstep(0.3,0.64,broad));
		float exposed = smoothstep(0.05,0.16,r)*(1.0-smoothstep(0.70,0.98,r))*ground_split.w;
		ALBEDO = mix(ALBEDO,vec3(0.048,0.031,0.020),breaks*exposed*0.94);
	}
	if (shock_limit > 0.0) {
		float distance_to_origin = distance(world, vec3(shock.x, shock_elevation, shock.y));
		float lag = shock.z - distance_to_origin;
		float fade = 1.0 - shock_progress;
		float wave = (1.0 - smoothstep(0.10, 0.52 + shock.w * 0.16, abs(lag))) * fade;
		EMISSION = vec3(0.72, 0.42, 0.20) * wave * 0.72;
	}
	if (distant_ground) {
		float view_distance = distance(CAMERA_POSITION_WORLD,world);
		float broad_relief = noise2(p*0.000045)*0.73 + noise2(p*0.00014)*0.27;
		vec3 basin = mix(vec3(0.29,0.197,0.127),vec3(0.51,0.365,0.229),broad_relief);
		float macro_blend = smoothstep(2700.0,27000.0,view_distance);
		ALBEDO = mix(ALBEDO,basin,macro_blend);
	}
	ALBEDO *= mix(1.0,0.63,wetness);
	ROUGHNESS = mix(0.97,0.38,wetness);
}
