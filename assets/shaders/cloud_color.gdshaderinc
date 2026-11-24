uniform sampler3D turbulence : repeat_enable, filter_linear;
uniform float phase;
uniform float night;
instance uniform float offset_seed;
instance uniform vec3 state;
float noise_at(vec3 q) { return texture(turbulence,q).r; }
vec3 pigment(float detail, float lit) {
	float fire = smoothstep(0.20,0.70,state.x*(0.74+detail*0.72));
	vec3 smoke = mix(vec3(0.035,0.031,0.030),vec3(0.46,0.425,0.40),lit);
	vec3 soil = mix(vec3(0.13,0.085,0.052),vec3(0.56,0.39,0.24),lit);
	vec3 cold = mix(smoke,soil,state.y)*mix(vec3(1.0),vec3(0.19,0.22,0.31),night);
	vec3 ember = mix(vec3(1.7,0.13,0.009),vec3(5.8,2.0,0.24),fire*detail);
	return mix(cold,ember,fire);
}
