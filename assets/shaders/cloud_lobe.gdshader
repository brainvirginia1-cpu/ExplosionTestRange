shader_type spatial;
render_mode unshaded, cull_back;
#include "res://assets/shaders/cloud_color.gdshaderinc"
varying vec3 surface;
void vertex(){
	surface = VERTEX;
	vec3 uvw = surface*0.27+vec3(offset_seed,phase*0.043,0);
	float fold = textureLod(turbulence,uvw,0.0).r;
	float grain = textureLod(turbulence,uvw*2.6+fold*0.32,0.0).r;
	VERTEX *= 0.51+fold*0.83+grain*0.24;
}
void fragment(){
	vec3 uvw = surface*0.27+vec3(offset_seed,phase*0.043,0);
	float fold = noise_at(uvw);
	float grain = noise_at(uvw*2.6+fold*0.32);
	float finer = noise_at(uvw*7.3+grain*0.26);
	vec3 sun = normalize(vec3(-0.55,0.86,0.32));
	float height_diff = noise_at(uvw+sun*0.022)-fold;
	float lit = clamp(0.37+dot(normalize(surface),sun)*0.33-height_diff*0.95+(grain-0.50)*0.27,0.0,1.0);
	ALBEDO = pigment(grain*0.7+finer*0.3,lit);
	float rim = abs(dot(normalize(NORMAL),normalize(VIEW)));
	ALPHA = smoothstep(0.01,0.44,rim+(finer-0.5)*0.27)*min(0.88,state.z*1.13)*(1.0-smoothstep(7.0,12.0,phase));
}
