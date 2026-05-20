shader_type spatial;

#include "res://global_resources/shader_related/simplex3d.gdshaderinc"
#include "res://global_resources/shader_related/worley3d.gdshaderinc"

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	
	float ligament_val = min(4. * pow(_cellular3dNoiseFunc(1.0 * (world_pos + vec3(1, 0, 0)), 1.).x, 8.), 0.6);
	
	float _pulse = max(8. * max(mod(0.8 * TIME, 1.), mod(-0.8 *TIME, 1.)) - 7., 0.);
	float vein_val = max(-abs((20. - 8. * _pulse) * (_simplex3dNoiseFunc(0.5 * (world_pos + vec3(1, 0, 0))) - 0.5)) + 1., 0.);
    vein_val = pow(vein_val, 2.);
	
	ALBEDO = (1. - vein_val) * (vec3(0.15, 0.005, 0.01) + ligament_val * vec3(0.2, 0.2, 0.2)) + vein_val * vec3(0.08, 0.01, 0.04);
}
