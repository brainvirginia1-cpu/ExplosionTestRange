uniform vec4 cloud_layout; // voxels per axis, tiles per row, atlas width, atlas height

vec2 cloud_atlas_uv(int layer, vec2 plane) {
	int columns = int(cloud_layout.y);
	vec2 tile = vec2(ivec2(layer % columns,layer / columns));
	return (tile*cloud_layout.x+plane)/cloud_layout.zw;
}
