shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform vec4 parcels[120]; // xyz local center, w radius
uniform vec4 state[120]; // temperature, dust fraction, optical density
uniform vec3 cloud_min;
uniform vec3 cloud_span;
void fragment() {
	vec2 pixel = min(floor(UV*vec2(384.0,288.0)),vec2(383,287));
	float layer = floor(pixel.x/48.0)+8.0*floor(pixel.y/48.0);
	vec3 point = cloud_min+cloud_span*(vec3(mod(pixel.x,48.0),layer,mod(pixel.y,48.0))+0.5)/48.0;
	float gas=0.0, energy=0.0, soil=0.0;
	for(int i=0;i<120;i++){
		float dy=abs(point.y-parcels[i].y);
		if (dy*state[i].w>parcels[i].w) {continue;}
		vec3 offset=(point-parcels[i].xyz)/parcels[i].w;
		offset.y *= state[i].w;
		float k=max(0.0,1.0-dot(offset,offset));
		float density=k*k*state[i].z;
		gas += density*(1.0-state[i].y);
		energy += density*state[i].x;
		soil += density*state[i].y;
	}
	COLOR=vec4(1.0-exp(-gas), energy/max(gas,0.001),1.0-exp(-soil),1.0);
}
