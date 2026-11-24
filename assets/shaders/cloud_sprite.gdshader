shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://assets/shaders/cloud_color.gdshaderinc"
void vertex() {
	vec3 scales = vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),1.0);
	MODELVIEW_MATRIX = mat4(vec4(scales.x,0,0,0),vec4(0,scales.y,0,0),vec4(0,0,1,0),(VIEW_MATRIX*MODEL_MATRIX)[3]);
}
void fragment() {
	vec2 p = UV*2.0-1.0;
	float angle = offset_seed*6.283;
	vec2 q = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*p;
	vec3 uvw = vec3(q*0.22,offset_seed+phase*0.055);
	float broad = noise_at(uvw);
	float detail = noise_at(uvw*2.8+broad*0.38);
	float lace = noise_at(uvw*8.5+detail*0.28);
	float mask = 1.0-dot(p,p)+(broad-0.53)*0.90+(detail-0.5)*0.41+(lace-0.5)*0.13;
	float relief = noise_at(uvw+vec3(-0.024,-0.029,0.0))-broad;
	float lit = clamp(0.43-0.24*p.y-0.19*p.x+relief*0.78+(detail-0.5)*0.29,0.0,1.0);
	ALBEDO = pigment(clamp(detail+(lace-0.5)*0.45,0.0,1.0),lit);
	ALPHA = (1.0-smoothstep(0.85,1.0,length(p)))*smoothstep(0.06,0.68,mask)*min(0.92,state.z)*(1.0-smoothstep(7.0,12.0,phase));
}
