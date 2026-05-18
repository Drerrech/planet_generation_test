shader_type spatial;

#include "res://global_resources/shader_related/simplex3d.gdshaderinc"

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    ALBEDO = vec3(
		0.1 * mod(pow(_simplex3dNoiseFunc(0.5 * (world_pos + vec3(1, 0, 0))) * 2., 1.), 1.),
		mod(pow(_simplex3dNoiseFunc(1.0 * (world_pos + vec3(0, 1, 0))) * 2., 2.), 1.),
		0.5 * mod(pow(_simplex3dNoiseFunc(2.0 * (world_pos + vec3(0, 0, 1))) * 2., 3.), 1.)
	);
}
