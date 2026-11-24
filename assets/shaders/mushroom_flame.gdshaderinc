// Evaluate the flame between smoke samples to keep the hot edges continuous.
vec3 mushroom_flame(vec3 pos, vec3 seed, float phase, float ground, float height) {
	vec2 offset = pos.xz-0.5;
	float y = pos.y-ground;
	float lift = 1.0-exp(-phase*0.74);
	float cap_center = 0.30+0.39*lift;
	float opening = smoothstep(0.09,3.30,phase);
	float cap_distance = pos.y-(cap_center-0.075);
	if (y < -0.016 || length(offset) > 0.39 ||
		(y > 0.52 && abs(cap_distance) > 0.17)) {
		return vec3(0.0);
	}

	vec3 flow = vec3(offset.x*2.35,y*1.85-phase*0.21,offset.y*2.35)+seed;
	float large = texture(turbulence,flow).r;
	float detail = texture(turbulence,flow*1.56+vec3(0.27,-phase*0.13,0.34)).r;
	float tongues = smoothstep(0.40,0.75,large*0.77+detail*0.23);
	float radial = length(offset+(large-0.5)*vec2(0.047,-0.038));
	float base = (1.0-smoothstep(0.105,0.27,radial))*
		(1.0-smoothstep(height*0.19,height*(0.61+0.62*large),y))*
		smoothstep(-0.016,0.028,y)*tongues;

	float spine = (1.0-smoothstep(0.048,0.139,radial))*
		smoothstep(0.060,0.15,y)*(1.0-smoothstep(cap_center-0.19,cap_center-0.065,pos.y));
	float pockets = spine*smoothstep(0.37,0.74,detail*0.58+large*0.42);

	// Curl the rising fire outward into pockets along the underside of the cap.
	vec2 cap_offset = offset-vec2(0.045*lift,0.0);
	float cap_radius = length(cap_offset);
	float under_lip = mix(0.104,0.216,opening)+(large-0.5)*0.064;
	float warped_height = cap_distance+(detail-0.5)*0.095+(cap_radius-under_lip)*0.42;
	float band_distance = length(vec2((cap_radius-under_lip)/0.103,warped_height/0.075));
	float band = 1.0-smoothstep(0.23,1.21,band_distance);
	float angle = atan(cap_offset.y,cap_offset.x+0.00001);
	float roll = 0.5+0.5*sin(angle*6.0+phase*0.52+seed.x*6.28+large*3.2);
	float flicker = smoothstep(0.34,0.74,large*0.52+detail*0.19+roll*0.29);
	return vec3(base,pockets,band*flicker);
}
