shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
#include "res://assets/shaders/weather_lighting.gdshaderinc"

uniform sampler3D turbulence : repeat_enable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float phase;
uniform float fade;
uniform float flash_light;
uniform vec3 sun_direction;
uniform vec4 air_reach;

varying vec3 surface_world;
varying flat vec3 puff;
varying flat vec3 center;
varying flat vec3 local_x;
varying flat vec3 local_y;
varying flat vec3 local_z;
varying flat vec3 local_sun;
varying flat float reference_width;

void vertex() {
	puff = INSTANCE_CUSTOM.rgb;
	center = MODEL_MATRIX[3].xyz;
	surface_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec3 x = MODEL_MATRIX[0].xyz;
	vec3 y = MODEL_MATRIX[1].xyz;
	vec3 z = MODEL_MATRIX[2].xyz;
	local_x = x/max(dot(x,x),0.00001);
	local_y = y/max(dot(y,y),0.00001);
	local_z = z/max(dot(z,z),0.00001);
	local_sun = vec3(dot(normalize(x),sun_direction),dot(normalize(y),sun_direction),
		dot(normalize(z),sun_direction));
	reference_width = max(0.12,min(length(y),length(z)));
}

vec3 local_vector(vec3 direction) {
	return vec3(dot(direction,local_x),dot(direction,local_y),dot(direction,local_z));
}

void fragment() {
	vec3 ray = normalize(surface_world-CAMERA_POSITION_WORLD);
	vec3 eye = local_vector(CAMERA_POSITION_WORLD-center);
	vec3 direction = local_vector(ray);

	// Intersect the puff's three-dimensional proxy, then stop at opaque geometry.
	float quadratic = dot(direction,direction);
	float projection = dot(eye,direction);
	float discriminant = projection*projection-quadratic*(dot(eye,eye)-1.0);
	if (discriminant<=0.0) { discard; }
	float interval = sqrt(discriminant);
	float start = max(0.0,(-projection-interval)/quadratic);
	float end = (-projection+interval)/quadratic;
	float depth = texture(scene_depth,SCREEN_UV).r;
	if (depth>0.0) {
		vec4 opaque = INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth,1.0);
		end = min(end,length(opaque.xyz/opaque.w));
	}
	if (end<=start) { discard; }

	const int STEPS = 11;
	float stride = (end-start)/float(STEPS);
	vec3 pos = eye+direction*(start+stride*0.5);
	vec3 step_size = direction*stride;
	vec3 drift = vec3(puff.x*5.0-phase*0.024,puff.x*9.1-phase*0.072,puff.x*6.6+phase*0.045);
	float density_scale = fade*puff.y*mix(1.0,0.60,puff.z)*stride/reference_width*1.62;
	vec3 environment_light = weather_effect_light(1.0);
	vec3 radiance = vec3(0.0);
	float transmission = 1.0;
	for (int i=0;i<STEPS;i++) {
		vec3 roll = vec3(pos.x,pos.y,pos.z+pos.y*0.22);
		float broad = texture(turbulence,roll*0.61+drift).r;
		float folds = texture(turbulence,roll*1.57+drift*0.72+vec3(0.27,0.53,0.18)).r;
		float edge = 0.86-length(roll)+0.50*(broad-0.5)+0.23*(folds-0.5);
		float body = smoothstep(-0.09,0.25,edge);
		float ground = 1.0-0.47*smoothstep(-0.25,0.90,pos.y);
		float travel = start+stride*(float(i)+0.5);
		float distance = length(CAMERA_POSITION_WORLD+ray*travel-air_reach.xyz);
		float reach_mask = 1.0-smoothstep(air_reach.w*0.975,max(0.001,air_reach.w),distance);
		float density = body*ground*(0.62+0.65*broad+0.38*folds)*reach_mask;
		float toward_sun = dot(pos,local_sun);
		float light_path = max(0.0,sqrt(max(0.0,toward_sun*toward_sun+1.0-dot(pos,pos)))-toward_sun);
		float direct = exp(-light_path*fade*(0.78+0.76*broad));
		float lit = clamp(0.12+0.84*direct+(folds-0.5)*0.28,0.0,1.0);
		vec3 color = mix(vec3(0.125,0.074,0.044),vec3(0.64,0.47,0.30),lit*lit);
		color *= environment_light;
		color += vec3(0.70,0.25,0.064)*flash_light*(0.58-0.36*pos.z);
		float opacity = 1.0-exp(-density*density_scale);
		radiance += transmission*opacity*color;
		transmission *= 1.0-opacity;
		if (transmission<0.015) { break; }
		pos += step_size;
	}
	float opacity = 1.0-transmission;
	ALBEDO = radiance/max(opacity,0.0001);
	ALPHA = opacity;
}
