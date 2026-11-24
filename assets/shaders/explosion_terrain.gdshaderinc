uniform vec4 terrain_craters[16];
uniform int terrain_crater_count;
uniform vec4 terrain_heave;

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
