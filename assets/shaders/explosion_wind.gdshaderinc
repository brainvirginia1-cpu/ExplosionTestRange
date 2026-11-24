uniform vec2 wind_drift;
uniform float wind_ground;
// Atlas coordinates mapped into the original cloud footprint.
uniform vec4 wind_frame = vec4(0.0,0.0,1.0,1.0);
uniform vec2 wind_spread = vec2(1.0);

vec3 upwind_position(vec3 p) {
	if (wind_drift != vec2(0.0)) {
		float height = max(0.0,p.y-wind_ground);
		float shear = 0.19+0.81*smoothstep(0.0,0.68,height);
		float eddy = 0.98+0.07*sin(height*15.0-age*0.48+variation.z*6.283);
		vec2 offset = (p.xz-0.5)*wind_frame.zw+wind_frame.xy-wind_drift*shear*eddy;
		vec2 along = normalize(wind_drift);
		vec2 longitudinal = along*dot(offset,along);
		p.xz = vec2(0.5)+longitudinal/wind_spread.x+(offset-longitudinal)/wind_spread.y;
	}
	return p;
}
