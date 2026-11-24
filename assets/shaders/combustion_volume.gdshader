shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;
uniform sampler2D field : filter_linear, repeat_disable;
uniform sampler3D turbulence : filter_linear, repeat_enable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 bounds_min;
uniform vec3 bounds_max;
uniform float world_scale;
uniform float wind_visibility = 1.0;
uniform float age;
uniform float elapsed_fraction;
uniform float dust_weight;
uniform float heat_gain;
uniform float flash_light;
uniform float thermonuclear;
uniform float ground_light;
uniform float cap_fire;
uniform float flame_height;
uniform float ground_level;
uniform vec3 weather;
uniform vec3 sun_direction;
uniform vec3 variation;
uniform vec3 discharge;
uniform int steps = 76;
varying vec3 surface_world;

#include "res://assets/shaders/mushroom_flame.gdshaderinc"

void vertex() {
	surface_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

#include "res://assets/shaders/explosion_atlas.gdshaderinc"
#include "res://assets/shaders/explosion_wind.gdshaderinc"

vec4 volume(vec3 p) {
	if (any(lessThan(p,vec3(0))) || any(greaterThan(p,vec3(1)))) { return vec4(0); }
	vec3 cell = clamp(p*cloud_layout.x-0.5,vec3(0.0),vec3(cloud_layout.x-1.0));
	int layer = int(cell.y);
	return mix(texture(field,cloud_atlas_uv(layer,cell.xz+0.5)),
		texture(field,cloud_atlas_uv(min(int(cloud_layout.x)-1,layer+1),cell.xz+0.5)),fract(cell.y));
}

float occluder(vec3 p) {
	vec4 d = volume(p);
	return d.r + d.b*dust_weight*0.62 + d.a*0.52;
}

vec3 lightning(vec3 p) {
	float high = 0.36+0.32*(1.0-exp(-age*0.75));
	vec2 radial = p.xz-0.5;
	float radius = length(radial);
	float bearing = atan(radial.y,radial.x+0.00001)-discharge.y;
	float route = high-0.02+0.058*sin(bearing*13.0+discharge.z)+0.028*sin(bearing*41.0);
	float line = length(vec2(p.y-route,(radius-0.24)*0.58));
	float side = smoothstep(0.18,0.88,cos(bearing));
	return discharge.x*side*(vec3(4.0,5.1,7.0)*exp(-line*line/0.000016)+vec3(0.28,0.44,0.75)*exp(-line*line/0.0011));
}

void fragment() {
	vec3 ray = normalize(surface_world-CAMERA_POSITION_WORLD);
	vec3 inverse_ray = (2.0*step(vec3(0.0),ray)-1.0)/max(abs(ray),vec3(0.00001));
	vec3 a = (bounds_min-CAMERA_POSITION_WORLD)*inverse_ray;
	vec3 b = (bounds_max-CAMERA_POSITION_WORLD)*inverse_ray;
	vec3 lo = min(a,b), hi = max(a,b);
	float start = max(0.0,max(lo.x,max(lo.y,lo.z)));
	float end = min(hi.x,min(hi.y,hi.z));
	vec4 opaque = INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,texture(scene_depth,SCREEN_UV).r,1.0);
	end = min(end,length(opaque.xyz/opaque.w));
	if (end <= start) { discard; }
	vec3 span = bounds_max-bounds_min;
	vec3 light_ray = normalize(sun_direction/span);
	float stride = (end-start)/float(steps);
	float jitter = fract(52.9829189*fract(dot(FRAGCOORD.xy,vec2(0.06711056,0.00583715))));
	vec3 p = (CAMERA_POSITION_WORLD+ray*(start+stride*(0.42+0.16*jitter))-bounds_min)/span;
	vec3 step_size = ray*stride/span;
	vec3 sum = vec3(0.0);
	float transmission = 1.0;
	float fade = 1.0-smoothstep(0.58,1.0,elapsed_fraction);
	float view_altitude = CAMERA_POSITION_WORLD.y+dot(CAMERA_POSITION_WORLD.xz,CAMERA_POSITION_WORLD.xz)/12742000.0;
	float high_air = smoothstep(650.0,11600.0,view_altitude);
	vec3 night_ambient = mix(vec3(0.045,0.044,0.042),vec3(0.026,0.035,0.053),high_air);
	vec3 night_direct = mix(vec3(0.15,0.148,0.143),vec3(0.12,0.16,0.24),high_air);
	float density_at_camera = start < 0.001 ?
		occluder((CAMERA_POSITION_WORLD-bounds_min)/span) : 0.0;
	float enclosed = smoothstep(0.30,1.15,density_at_camera)*fade;
	for (int i=0;i<steps;i++) {
		vec4 d = volume(p);
		if (d.r+d.b+d.a>0.009) {
			float grain = texture(turbulence,p*3.5+variation+vec3(0,-age*0.037,0)).r;
			float gas = d.r;
			float soil = d.b*dust_weight*(1.0-weather.y*0.68);
			float haze = d.a;
			float density = gas+soil+haze;
			// Integrate the cloud's own density in the direction of the scene light.
			float shadow = occluder(p+light_ray*0.028)*0.46
				+occluder(p+light_ray*0.077)*0.58
				+occluder(p+light_ray*0.154)*0.78
				+occluder(p+light_ray*0.265)*0.67;
			float light = exp(-shadow*1.38);
			vec3 ambient = mix(vec3(0.135,0.120,0.111),night_ambient,weather.z);
			vec3 sun = mix(vec3(0.77,0.70,0.61),night_direct,weather.z)*(1.0-weather.y*0.43);
			vec3 smoke_color = ambient*0.68+sun*light*(0.80+grain*0.20);
			vec3 soil_color = (ambient*0.88+sun*light)*vec3(0.71,0.49,0.30);

			float heat = d.g*heat_gain;
			float flame_heat = 0.0;
			if (ground_light+cap_fire > 0.004) {
				vec3 flame_pos = upwind_position(p);
				vec3 flame = mushroom_flame(flame_pos,variation,age,ground_level,flame_height);
				flame_heat = dot(flame,vec3(ground_light*1.55,ground_light*1.24,cap_fire*1.47));
				heat += flame_heat;
			}
			vec3 fire = mix(vec3(1.06,0.069,0.007),vec3(5.0,0.90,0.070),smoothstep(0.17,0.78,heat));
			vec3 white_hot = mix(vec3(8.4,4.70,1.80),vec3(9.4,6.85,3.70),thermonuclear);
			fire = mix(fire,white_hot,smoothstep(0.65,1.18,heat));
			vec3 at_base = (p-vec3(0.5,ground_level+0.058,0.5))*vec3(6.0,8.3,6.0);
			float base_glow = ground_light*exp(-dot(at_base,at_base)*1.15);
			float nearby_heat = volume(p-vec3(0.0,0.025,0.0)).g;
			float hot_glow = 0.36*smoothstep(0.08,0.50,nearby_heat)+0.27*base_glow
				+0.42*smoothstep(0.025,0.68,flame_heat);
			float flash = flash_light*exp(-length(at_base)*0.9);
			vec3 inner_light = vec3(1.42,0.34,0.047)*(hot_glow+0.73*flash);
			vec3 color = (gas*(mix(smoke_color+inner_light,fire,smoothstep(0.065,0.72,heat)))
				+soil*(soil_color+inner_light*0.65)+haze*(ambient+sun*light*0.91))/max(density,0.001);
			if (discharge.x>0.002) {
				float exposed = smoothstep(0.035,0.16,gas)*(1.0-smoothstep(0.25,0.58,gas));
				color += lightning(upwind_position(p))*exposed;
			}
			float opacity = 1.0-exp(-density*stride/max(world_scale,0.01)*0.83*fade);
			sum += transmission*opacity*color;
			transmission *= 1.0-opacity;
			if (transmission<0.008) { break; }
		}
		p += step_size;
	}
	float cloud_opacity = 1.0-transmission;
	float obscured = enclosed*0.986;
	ALPHA = mix(cloud_opacity,1.0,obscured)*wind_visibility;
	ALBEDO = mix(sum/max(cloud_opacity,0.0001),vec3(0.045,0.041,0.037),obscured);
}
