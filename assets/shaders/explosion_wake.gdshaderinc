uniform vec4 wake_shape; // radius, half-width, height, density
uniform vec2 wake_center;
uniform vec2 wake_vertical;
uniform vec4 wake_reach;
uniform float wake_age;

vec3 safe_inverse(vec3 ray) {
	return (2.0*step(vec3(0.0),ray)-1.0)/max(abs(ray),vec3(0.000001));
}

vec2 box_span(vec3 eye, vec3 inverse_ray, vec3 lower, vec3 upper) {
	vec3 a = (lower-eye)*inverse_ray;
	vec3 b = (upper-eye)*inverse_ray;
	vec3 lo = min(a,b), hi = max(a,b);
	return vec2(max(lo.x,max(lo.y,lo.z)),min(hi.x,min(hi.y,hi.z)));
}

vec2 cylinder_span(vec2 eye, vec2 ray, float radius) {
	float a = dot(ray,ray);
	float c = dot(eye,eye)-radius*radius;
	if (a < 0.00000001) {
		return c < 0.0 ? vec2(-1e9,1e9) : vec2(1e9,-1e9);
	}
	float b = dot(eye,ray);
	float disc = b*b-a*c;
	if (disc <= 0.0) { return vec2(1e9,-1e9); }
	return (-b+vec2(-1.0,1.0)*sqrt(disc))/a;
}

vec4 wake_spans(vec3 eye, vec3 ray, vec3 inverse_ray, float opaque_end) {
	if (wake_shape.w <= 0.0) { return vec4(1e9,-1e9,1e9,-1e9); }
	vec2 offset = eye.xz-wake_center;
	vec2 band = cylinder_span(offset,ray.xz,wake_shape.x+wake_shape.y);
	vec2 y = (wake_vertical-eye.y)*inverse_ray.y;
	band = vec2(max(band.x,max(min(y.x,y.y),0.0)),min(band.y,min(max(y.x,y.y),opaque_end)));
	float inner_radius = wake_shape.x-wake_shape.y;
	if (inner_radius <= 0.0) { return vec4(band,1e9,-1e9); }
	vec2 gap = cylinder_span(offset,ray.xz,inner_radius);
	if (gap.y <= band.x || gap.x >= band.y || gap.y <= gap.x) {
		return vec4(band,1e9,-1e9);
	}
	return vec4(band.x,min(band.y,gap.x),max(band.x,gap.y),band.y);
}

float wake_density(vec3 world) {
	vec2 offset = world.xz-wake_center;
	float radial = (length(offset)-wake_shape.x)/wake_shape.y;
	float height = (world.y-terrain_height(world.xz))/wake_shape.z;
	if (height <= 0.0 || height >= 2.20 || abs(radial) >= 1.0) { return 0.0; }
	float feather = min(wake_shape.y*0.74,wake_reach.w*0.18);
	float reach = 1.0-smoothstep(wake_reach.w-feather,wake_reach.w,length(world-wake_reach.xyz));
	if (reach <= 0.0) { return 0.0; }
	vec3 flow = vec3(offset.x/wake_shape.y,height*0.60,offset.y/wake_shape.y);
	vec3 drift = variation*7.0+vec3(-0.018,-0.054,0.035)*wake_age;
	float masses = texture(turbulence,flow*0.32+drift).r;
	float folds = texture(turbulence,flow*0.91+drift*0.81).r;
	float wisps = texture(turbulence,flow*1.81+drift*0.61).r;
	float roll_height = mix(0.32,1.05,smoothstep(0.28,0.78,masses));
	float roll_center = -0.08+(masses-0.5)*0.68;
	vec2 roll = vec2((radial-roll_center+height*0.24)*2.0,(height-0.26)/roll_height);
	float billow = 1.0-smoothstep(0.20,1.33,length(roll)+(0.49-folds)*0.60);
	float tail_offset = (radial+0.55)*1.94;
	float tail = exp(-tail_offset*tail_offset-height*3.6);
	float rim = (1.0-smoothstep(0.46,1.0,abs(radial)))*(1.0-smoothstep(1.0,2.20,height));
	float contact = smoothstep(0.0,0.13,height);
	float pockets = mix(0.15,1.18,smoothstep(0.29,0.72,masses*0.68+folds*0.32));
	return (billow*pockets+tail*0.32)*mix(0.73,1.13,wisps)*rim*contact*reach;
}
