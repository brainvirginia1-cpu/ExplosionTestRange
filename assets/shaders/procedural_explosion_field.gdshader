shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler3D turbulence : filter_linear, repeat_enable;
uniform vec3 variation;
uniform float age;
uniform float ignited = 1.0;
uniform float precursor;
uniform vec4 thermal_shape; // spray, ignition, temperature, rise
uniform float thermal_formation;
uniform float thermal_floor;
uniform float thermal_vertical_ratio;
uniform vec2 thermal_direction;
uniform float crown;
uniform float thermonuclear;
uniform vec3 ignition_form; // expansion, visibility, core heat
uniform float ground_level;
uniform float flame_height;
uniform float mature_fire;
uniform float cap_fire;
uniform float mushroom;
uniform float elapsed_fraction;
uniform float wind_dilution = 1.0;
uniform float wind_erosion;
uniform int burst_kind;
uniform vec4 terrain_rect;
uniform vec3 terrain_vertical;
uniform vec2 ground_dust; // radius in cloud coordinates, density
uniform vec4 terrain_craters[16];
uniform int terrain_crater_count;
uniform vec4 terrain_heave;

#include "res://assets/shaders/mushroom_flame.gdshaderinc"
#include "res://assets/shaders/explosion_atlas.gdshaderinc"

#include "res://assets/shaders/explosion_wind.gdshaderinc"

float cloud_lobe(vec3 point, vec3 radius) {
	float distance = length(point/radius);
	return 1.0-smoothstep(0.55,1.06,distance);
}

// Turbulent lobes grow and rise from the origin, leaving a cooling wake.
vec3 rising_burst(vec3 position, vec3 curl, float detail) {
	float lift = 1.0-exp(-age*0.52);
	float expansion = 1.0-exp(-age*2.7);
	float rise = mix(ground_level+0.10,0.48,lift);
	vec2 sway = (variation.xy-0.5)*0.105*lift;
	vec3 p = position-vec3(0.5+sway.x,rise,0.5+sway.y);
	p += curl*(0.067+0.105*expansion);
	float broad = mix(0.137,0.278,expansion);
	float height = mix(0.205,0.237,expansion);
	if (burst_kind == 2) {
		broad *= 1.13;
		height *= 0.91;
	}
	float main = cloud_lobe(p,vec3(broad,height,broad*0.89));
	vec2 turn = normalize(variation.xz-0.5+vec2(0.004));
	vec2 wing = turn*(0.056+0.088*expansion);
	vec3 side_a = p-vec3(wing.x,0.05+0.065*lift,wing.y);
	vec3 side_b = p+vec3(wing.x*0.89,0.06,wing.y*1.14);
	float billows = max(cloud_lobe(side_a,vec3(broad*0.65,height*0.71,broad*0.71))*0.86,
		cloud_lobe(side_b,vec3(broad*0.70,height*0.68,broad*0.62))*0.75);
	float trunk = cloud_lobe(p+vec3(0.003,0.23*lift,0.004),vec3(broad*0.55,0.18+0.21*lift,broad*0.59));
	trunk *= smoothstep(ground_level-0.024,ground_level+0.070,position.y);
	float gas = max(main,billows)+trunk*0.52*lift;
	float heat = cloud_lobe(p-vec3(0.0,0.015,0.0),vec3(broad*0.91,height*0.91,broad*0.83));
	heat = max(heat,billows*0.51)*exp(-age*2.65);
	heat *= 0.70+0.82*smoothstep(0.32,0.76,detail+curl.y*0.15);
	gas *= smoothstep(0.0,0.047,age);
	float dust = trunk*exp(-age*0.49)*(0.28+0.28*detail)*expansion;
	return vec3(gas*1.39,heat*1.61,dust);
}

// The preparation cloud spreads outward above the ground before it lights up.
vec4 thermal_plume(vec3 p, vec3 curl, float detail, float surface_distance) {
	float spray = thermal_shape.x;
	float burning = thermal_shape.y;
	float temperature = thermal_shape.z;
	float rising = thermal_shape.w;
	float dome_radius = 0.445;
	float altitude = p.y-thermal_floor;
	float spray_height = mix(0.08,0.27,spray);
	float height = mix(spray_height,dome_radius/thermal_vertical_ratio,thermal_formation);
	float height_fraction = altitude/max(height,0.006);
	float descent = 1.0-height_fraction*1.25;
	float stride = smoothstep(0.07,0.86,spray);
	float spray_envelope = smoothstep(-0.042,0.045,height_fraction)
		*(1.0-smoothstep(0.63,1.09,height_fraction+curl.y*0.10));

	vec2 displacement = p.xz-0.5+curl.xz*0.085;
	vec2 side_axis = vec2(-thermal_direction.y,thermal_direction.x);
	float along = dot(displacement,thermal_direction);
	float cross = dot(displacement,side_axis);
	float depth = clamp(descent+0.06,0.0,1.0);
	float steep_edge = -0.075-0.047*(1.0-depth)+0.038*curl.z;
	float wide_edge = mix(0.16,0.48,depth*stride)+0.057*(detail-0.5);
	float fan_center = (steep_edge+wide_edge)*0.5;
	float fan_width = max(0.045,(wide_edge-steep_edge)*0.5);
	float fan_thickness = mix(0.10,0.23,depth*stride);

	// Move the cross-sections of the same cloud into circular slices of the dome.
	float h = clamp(height_fraction,0.0,1.0);
	float dome_section = dome_radius*sqrt(max(0.0004,1.0-h*h));
	float center = mix(fan_center,0.037,thermal_formation);
	vec2 axes = mix(vec2(fan_width,fan_thickness),vec2(dome_section),thermal_formation);
	vec2 parcel = vec2(along-center,cross)/axes;
	float across = parcel.x*0.5+0.5;
	float profile = smoothstep(-0.08,0.14,across)*(1.0-smoothstep(0.72,1.03,across));
	float sides = 1.0-smoothstep(0.40,1.0,abs(parcel.y)/mix(0.68,1.0,profile));
	float circular = 1.0-smoothstep(0.73,1.04,length(parcel));
	float footprint = mix(profile*sides,circular,thermal_formation);
	float cap = smoothstep(-0.035,0.01,height_fraction)*(1.0-smoothstep(0.97,1.025,height_fraction));
	float envelope = mix(spray_envelope,cap,thermal_formation);
	if (surface_distance<0.0) {
		envelope *= smoothstep(-0.29*terrain_vertical.z,0.0,surface_distance);
	}
	// Sample turbulence in the undeformed cloud, so its billows move with the material.
	vec3 source = vec3(fan_center+parcel.x*fan_width,descent*0.32,parcel.y*fan_thickness);
	float grain = texture(turbulence,source*2.15+variation*0.47).r;
	float plume = footprint*envelope*spray*(0.58+0.63*grain);

	float sheet = 0.0;
	float contact = smoothstep(0.59,0.92,spray);
	if (contact>0.0 && surface_distance>-terrain_vertical.z*0.24 &&
		surface_distance<terrain_vertical.z*2.4) {
		vec2 footprint = vec2((along-0.17)/mix(0.21,0.37,contact),
			cross/mix(0.13,0.25,contact));
		float skirt = 1.0-smoothstep(0.40,1.05,length(footprint));
		float height = max(0.0,surface_distance)/max(terrain_vertical.z,0.01);
		float blanket = exp(-height/(0.48+0.29*detail))*(1.0-smoothstep(1.0,2.4,height));
		sheet = skirt*blanket*contact*(0.49+0.64*detail)*(1.0-0.42*rising);
	}

	float lit = smoothstep(0.0,0.65,burning);
	float heat = (plume+sheet*0.38)*lit*temperature*(0.98+0.70*grain);
	float haze = (plume+sheet)*(1.0-burning)*(0.78+0.22*grain);
	float diffusion = smoothstep(0.13,1.0,rising);
	float wisps = mix(1.0,smoothstep(0.22,0.71,grain+curl.y*0.18),diffusion*0.62);
	float smoke = plume*burning*mix(1.14,0.34,diffusion)*wisps;
	return vec4(smoke,heat*1.62,sheet*burning*0.84,haze);
}

// The smoke cap and its rising stem share the same curl field.
vec2 atmospheric_cloud(vec3 pos, vec3 curl, float phase) {
	float rise = 1.0-exp(-phase*0.74);
	float h = 0.30+0.39*rise;
	vec2 center = vec2(0.50+0.045*rise,0.50);
	vec3 q = pos + curl*(0.041 + 0.045*smoothstep(4.0,11.0,phase));
	q.xz -= center;
	float radius = length(q.xz);
	float bearing = atan(q.z,q.x+0.00001);
	float rolls = 0.5*sin(bearing*7.0+phase*0.23)+0.3*sin(bearing*11.0-phase*0.31)+0.2*cos(bearing*4.0);
	q.y += 0.022*rolls*smoothstep(0.06,0.20,radius);
	float billows = sin(bearing*9.0 + q.y*23.0-phase*0.50)*0.015 + rolls*0.013;
	q.xz *= 1.0-billows*2.2;
	float opening = smoothstep(0.09,3.30,phase);
	float dome_width = mix(0.115,0.305+0.040*thermonuclear,opening);
	q.y += curl.x*0.044*opening*smoothstep(0.06,0.29,radius);
	float dome = length(vec3(q.x/dome_width,(q.y-h)/mix(0.087,0.155-0.015*thermonuclear,opening),q.z/(dome_width*0.94)));
	float lip = length(vec2((radius-mix(0.058,0.208,opening)-0.019*rolls)/mix(0.064,0.110,opening),(q.y-h+0.039)/0.102));
	float hood = 1.0-smoothstep(0.82,1.04,min(lip,dome));
	if (thermonuclear>0.5) {
		float lower_roll = length(vec2((radius-0.22*opening-0.018*rolls)/0.107,(q.y-h+0.075)/0.061));
		hood = max(hood,(1.0-smoothstep(0.70,1.10,lower_roll))*opening*0.85);
	}
	vec2 axis = q.xz+vec2(0.060,0.025)*(h-q.y)+0.013*sin(q.y*19.0+vec2(1.0,2.0)+phase*0.31);
	float stem_width = 0.045+0.046*pow(abs(2.0*clamp(q.y/h,0.0,1.0)-1.0),1.5);
	float stem = (1.0-smoothstep(stem_width*0.65,stem_width*1.32,length(axis)))
		*smoothstep(-0.02,0.05,q.y)*(1.0-smoothstep(h-0.015,h+0.07,q.y));
	return vec2(hood,stem);
}

float terrain_height(vec2 p) {
	float height = -dot(p,p)/12742000.0;
	for (int i=0;i<terrain_crater_count;i++) {
		vec4 region = terrain_craters[i];
		vec2 delta = p-region.xy;
		float distance = length(delta);
		if (distance>=region.z*1.36) { continue; }
		float angle = atan(delta.y,delta.x+0.00001);
		float boundary = 1.0+sin(angle*5.0)*0.045+cos(angle*7.0)*0.022;
		float r = distance/(region.z*boundary);
		float floor_depth = -region.w*pow(max(1.0-r*r,0.0),1.22);
		float lip = (r-0.94)*10.0;
		float rim = exp(-lip*lip)*region.w*(0.14+sin(angle*9.0)*0.043);
		height += floor_depth+rim*(1.0-smoothstep(1.07,1.26,r));
	}
	if (terrain_heave.z>0.0) {
		vec2 delta = p-terrain_heave.xy;
		float r = length(delta)/terrain_heave.z;
		float angle = atan(delta.y,delta.x+0.00001);
		float ribs = sin(angle*7.0+r*6.0)*0.11*smoothstep(0.0,0.34,r);
		height += terrain_heave.w*(1.0-smoothstep(0.11,1.0,r))*(1.0+ribs);
	}
	return height;
}

vec2 ignition_cloud(vec3 p, vec3 curl, float detail) {
	float expansion = ignition_form.x;
	float height = mix(ground_level+0.08,0.40,expansion);
	vec3 q = p-vec3(0.5,height,0.5);
	q.xz -= (variation.xz-0.5)*0.055*expansion;
	float width = mix(0.16,0.32,expansion);
	float core_radius = length((q+curl*0.031)/vec3(width,0.23,width));
	float core = 1.0-smoothstep(0.55,1.0,core_radius);
	float rim_radius = mix(0.105,0.335,expansion);
	vec3 rim_point = q+curl*mix(0.018,0.070,expansion);
	float rim_distance = length(vec2((length(rim_point.xz)-rim_radius)/0.080,
		(rim_point.y+0.042+0.064*expansion)/0.10));
	float rim = (1.0-smoothstep(0.32,1.0,rim_distance))*smoothstep(0.07,0.50,expansion);
	float density = max(core*1.45,rim*(0.82+0.43*detail));
	float heat = core*ignition_form.z*2.25+rim*(0.24+0.79*ignition_form.z)*(0.62+0.52*detail);
	return vec2(density,heat);
}

void fragment() {
	float diffusion = smoothstep(0.48,1.0,elapsed_fraction);
	ivec2 pixel = ivec2(FRAGCOORD.xy);
	int grid = int(cloud_layout.x);
	ivec2 tile = pixel / grid;
	int layer = tile.x + int(cloud_layout.y)*tile.y;
	if (layer >= grid) { discard; }
	vec2 xz = (vec2(pixel % grid)+0.5)/cloud_layout.x;
	vec3 p = vec3(xz.x,(float(layer)+0.5)/cloud_layout.x,xz.y);
	float ground_y = p.y-ground_level;
	float surface_distance = 1.0e8;
	if (burst_kind<3 && ground_y<0.19) {
		vec2 world = terrain_rect.xy+p.xz*terrain_rect.zw;
		surface_distance = terrain_vertical.x+p.y*terrain_vertical.y-terrain_height(world);
	}
	p = upwind_position(p);
	if (length(p.xz-0.5)>0.55) { discard; }
	vec3 cloud_pos = p;
	// Spread the rising crown and draw in its lower column.
	float crown_width = mix(1.0, 0.74 + 0.64*smoothstep(0.29,0.69,p.y),
		crown*smoothstep(0.5,2.8,age));
	p.xz = (p.xz-0.5)/crown_width+0.5;
	float spray_motion = burst_kind==1 ? thermal_shape.x*0.12 : 0.0;
	vec3 flow = p*1.54+vec3(-age*0.027,-age*0.071-spray_motion,0.43)+variation*0.21;
	vec3 curl = vec3(texture(turbulence,flow).r,texture(turbulence,flow.yzx+0.31).r,
		texture(turbulence,flow.zxy+0.65).r)-0.5;
	float local_detail = texture(turbulence,flow*1.48+curl*0.53+vec3(0.19,-age*0.024,0.31)).r;
	vec4 thermal_field = vec4(0.0);
	vec3 field;
	if (burst_kind==1) {
		thermal_field = thermal_plume(cloud_pos,curl,local_detail,surface_distance);
		field = thermal_field.rgb;
	} else {
		field = rising_burst(p,curl,local_detail)*ignited;
	}
	float mature = crown*smoothstep(0.20,3.10,age);
	float formed = mushroom*smoothstep(0.75,2.80,age);
	if (mature>0.001) {
		vec2 cap = atmospheric_cloud(cloud_pos,curl,age);
		// Let ground dust settle below the stem as the crown separates.
		float height_mask = smoothstep(0.07,0.39,cloud_pos.y);
		float clear_view = smoothstep(0.06,0.95,mature);
		clear_view = max(clear_view,formed);
		field.b *= mix(1.0,(1.0-height_mask)*exp(-age*0.52),clear_view);
		float skirt = field.r*(1.0-height_mask)*0.34*exp(-age*0.28);
		float column = cap.y*(0.72-0.30*diffusion);
		field.r = mix(field.r,max(max(cap.x,column),skirt),clear_view);
		field.g *= 1.0-mature*0.86;
	}
	if (ignition_form.y>0.001) {
		vec2 fireball = ignition_cloud(cloud_pos,curl,local_detail);
		field.rg = mix(field.rg,max(field.rg,fireball),ignition_form.y);
	}
	// A filled, low sheet stays attached to the terrain behind the rolling front.
	float dust_depth = terrain_vertical.z;
	if (burst_kind<3 && precursor<0.01) {
		float suspended = smoothstep(dust_depth*0.60,dust_depth*1.75,surface_distance);
		field.r += field.b*suspended*0.19;
		field.b *= 1.0-suspended*0.95;
	}
	if (surface_distance > -dust_depth*0.24 && surface_distance < dust_depth*3.6 &&
		(burst_kind!=1 || thermal_shape.y>0.0)) {
		vec2 offset = (cloud_pos.xz-0.5)*2.0;
		float radius = length(offset+curl.xz*0.105);
		float expansion = 1.0-exp(-age*0.77);
		float edge = 0.18+(0.77+0.045*thermonuclear)*expansion+(local_detail-0.5)*0.10;
		float sheet = 1.0-smoothstep(edge-0.14,edge+0.045,radius);
		float crest = exp(-pow((radius-edge+0.12)/0.13,2.0));
		float folds = 0.52+0.71*smoothstep(0.31,0.72,local_detail+curl.z*0.18);
		float low_height = max(surface_distance,0.0)/max(dust_depth,0.01);
		float settled = mix(1.0,0.48,smoothstep(1.45,6.7,age));
		float hug = exp(-low_height/(0.36*settled));
		float roll = 1.0-smoothstep(0.08,0.80+0.42*folds,low_height/settled);
		float suspension = smoothstep(0.015,0.37,age)*exp(-age*mix(0.42,0.23,crown));
		field.b *= 1.0-smoothstep(dust_depth*0.8,dust_depth*3.5,surface_distance)*formed;
		field.b += sheet*(0.96*hug+crest*roll*1.13)*folds*suspension*mix(0.80,2.32,crown);
	} else {
		field.b *= 1.0-formed*smoothstep(0.018,0.080,ground_y);
	}
	if (ground_dust.y > 0.001 && surface_distance > -dust_depth*0.20 && surface_distance < dust_depth*3.4) {
		vec2 offset = cloud_pos.xz-0.5+curl.xz*ground_dust.x*0.17;
		float radius = length(offset)/max(ground_dust.x,0.001);
		float edge = 1.0-smoothstep(0.74,1.07,radius);
		float roll = exp(-pow((radius-0.79)/0.16,2.0));
		float local_height = max(surface_distance,0.0)/dust_depth;
		float ground_sheet = exp(-local_height*2.40);
		float billowing_edge = exp(-local_height*(1.12+local_detail*0.60));
		float pockets = mix(0.42,1.22,smoothstep(0.25,0.78,local_detail+0.20*curl.y));
		field.b += ground_dust.y*pockets*edge*(0.68*ground_sheet+0.95*roll*billowing_edge);
	}
	float fine = texture(turbulence,flow*3.0+curl*0.39).r;
	float folds = local_detail;
	float breakup = smoothstep(0.27+0.15*wind_erosion,0.67+0.08*wind_erosion,folds*0.70+fine*0.30);
	float filaments = mix(1.0,breakup,max(diffusion*0.90,wind_erosion*0.65))*
		clamp(0.93+(folds-0.5)*1.08+curl.y*0.88+(fine-0.5)*0.70,0.20,1.75);

	if (mature_fire+cap_fire > 0.001) {
		vec3 flame = mushroom_flame(cloud_pos,variation,age,ground_level,flame_height);
		// Give the flames a little material of their own so they extinguish inside the smoke.
		field.r += dot(flame,vec3(mature_fire*0.36,mature_fire*0.24,cap_fire*0.22));
	}
	// Thin edges disperse first. The remaining dense pockets lose opacity continuously.
	float edge_noise = mix(folds,fine,0.37);
	float eroded = max(0.0,field.r-wind_erosion*(0.24+0.50*(1.0-edge_noise)));
	float dust = max(0.0,field.b-wind_erosion*(0.07+0.21*(1.0-edge_noise)));
	COLOR = vec4(eroded*filaments*wind_dilution*1.43,field.g*(0.80+fine*0.44),
		dust*filaments*wind_dilution,thermal_field.a*wind_dilution);
}
