shader_type spatial;

#include "res://global_resources/shader_related/simplex3d.gdshaderinc"
#include "res://global_resources/shader_related/worley3d.gdshaderinc"

varying vec3 world_pos;
varying vec4 vertex_info;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_info = CUSTOM0;
}

// biome textures
vec3 frag_biome0() {
	return vec3(1.0, 0.0, 0.0);
}

vec3 frag_biome1() {
	return vec3(0.0, 1.0, 0.0);
}

vec3 frag_biome2() {
	return vec3(0.0, 0.0, 1.0);
}

vec3 frag_biome3() {
	return vec3(1.0, 1.0, 1.0);
}

vec3 frag_type0() { // biome
	float biome = vertex_info.r;
	
	if (biome <= 1.0) {
		return mix(frag_biome0(), frag_biome1(), biome);
	} else if (biome <= 2.0) {
		return mix(frag_biome1(), frag_biome2(), biome - 1.);
	} else if (biome <= 3.0) {
		return mix(frag_biome2(), frag_biome3(), biome - 2.);
	}
	
	return vec3(0.0, 0.0, 0.0);
}

vec3 frag_type1() { // player built
	return vec3(0.2, 0.2, 0.2);
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	
	if (vertex_info.g <= 1.0) {
		ALBEDO = mix(frag_type0(), frag_type1(), vertex_info.g);
	}
}
