shader_type spatial;

varying vec3 n;

void vertex() {
	n = NORMAL;
}

void fragment() {
	ALBEDO = n*0.5 + 0.5;
}
