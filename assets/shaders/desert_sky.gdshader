shader_type sky;
uniform float night;
uniform float rain;
global uniform vec3 weather_sun;

float hash2(vec2 p) {
	p = fract(p * vec2(0.3121, 0.3879)) * 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float curve = dot(POSITION.xz,POSITION.xz)/12742000.0;
	float height = max(0.0,POSITION.y+curve);
	float vacuum = smoothstep(4500.0,85000.0,height);
	float high_air = smoothstep(650.0,11600.0,height);
	float relative_elevation = d.y+sqrt(height/3185500.0);
	float elevation = max(relative_elevation,0.0);
	float clear_day = (1.0-night)*(1.0-rain);
	vec3 horizon = mix(vec3(0.71,0.66,0.56),vec3(0.26,0.48,0.72),clear_day);
	vec3 low_blue = mix(vec3(0.40,0.43,0.44),vec3(0.065,0.25,0.57),clear_day);
	vec3 blue = mix(low_blue,vec3(0.099,0.26,0.44),high_air);
	vec3 color = mix(horizon, blue, pow(smoothstep(0.0, 0.90, elevation), 0.50));
	if (relative_elevation < 0.0) {
		color = mix(horizon, vec3(0.27, 0.224, 0.176), smoothstep(0.0, 0.55, -relative_elevation));
	}
	vec3 direction = normalize(weather_sun);
	float sunlight = max(0.0, dot(d, direction));
	vec3 halo = mix(vec3(0.55,0.27,0.10),vec3(0.22,0.16,0.10),clear_day);
	color += halo * pow(sunlight,mix(10.0,24.0,clear_day));
	color += vec3(3.7, 2.5, 1.32) * smoothstep(0.9984, 0.99965, sunlight);

	vec3 overcast = mix(vec3(0.342,0.346,0.350),vec3(0.30,0.35,0.40),high_air);
	color = mix(color,overcast,rain*0.64);
	vec3 night_tint = mix(vec3(0.081,0.085,0.091),vec3(0.045,0.074,0.14),high_air);
	float luminance = dot(color,vec3(0.2126,0.7152,0.0722));
	vec3 night_sky = mix(vec3(luminance),color,mix(0.28,1.0,high_air));
	vec3 atmosphere = mix(color,night_sky*night_tint,night);
	vec2 grid = vec2(atan(d.z,d.x)/6.2831853+0.5,asin(clamp(d.y,-1.0,1.0))/3.1415927+0.5)*vec2(880,440);
	vec2 cell = floor(grid);
	float star_id = hash2(cell+vec2(103.1,51.8));
	vec2 center = vec2(hash2(cell+5.7),hash2(cell+47.2))*0.54+0.23;
	float star = exp(-dot(fract(grid)-center,fract(grid)-center)*111.0);
	star *= smoothstep(0.978,1.0,star_id)*smoothstep(0.0,0.07,elevation);
	vec3 upper = vec3(0.005,0.009,0.026)+vec3(0.050,0.11,0.24)*exp(-elevation*11.0);
	COLOR = mix(atmosphere,upper,vacuum)+vec3(0.82,0.91,1.0)*star*max(vacuum,0.66*night);
}
