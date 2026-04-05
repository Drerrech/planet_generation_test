shader_type spatial;
uniform sampler2D texture_y_pos: source_color, repeat_enable;
uniform sampler2D texture_y_neg: source_color, repeat_enable;
uniform sampler2D texture_side: source_color, repeat_enable;
uniform vec3 chunk_relative_pos;
uniform vec3 planet_global_pos;

varying vec3 relative_normal;
varying vec3 rotated_vertex;

// Build rotation matrix that aligns target direction back to local up
mat3 align_direction_to_up(vec3 current_up) {
    // Normalize the current up direction
    vec3 up = normalize(current_up);
    
    // Choose a reference direction (not parallel to up)
    vec3 reference = abs(up.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    
    // Build orthonormal basis
    vec3 right = normalize(cross(reference, up));
    vec3 forward = cross(up, right);
    
    // Return TRANSPOSED matrix (inverse rotation)
    // In mat3, rows become columns, so we pass them as rows
    return mat3(
        vec3(right.x, up.x, forward.x),
        vec3(right.y, up.y, forward.y),
        vec3(right.z, up.z, forward.z)
    );
}

void vertex() {
	vec3 global_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 from_sphere_center = global_pos - planet_global_pos;
	vec3 normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	
	mat3 rotation = align_direction_to_up(world_normal);
	relative_normal = normalize(rotation * from_sphere_center);
	//relative_normal = vec3(0, -1, 0);
    rotated_vertex = rotation * from_sphere_center;
}

void fragment() {
	vec4 vertex = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 normal = normalize(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz));
	//normal = vec3(0, 1, 0);
    
    vec3 adjusted_normal = pow(abs(normal), vec3(8.0));
    vec3 weights = adjusted_normal / (adjusted_normal.x + adjusted_normal.y + adjusted_normal.z) * 3.0;
    
    // Use rotated vertex for UVs
    vec2 uv_x = vertex.zy;
    vec2 uv_y = vertex.xz;
    vec2 uv_z = vertex.xy;
    
    float use_y_up = float(relative_normal.y > 0.0);
    
    vec3 color_x = texture(texture_y_pos, uv_x).rgb * weights.x;
    vec3 color_y_up = texture(texture_y_pos, uv_y).rgb * weights.y;
    vec3 color_y_down = texture(texture_y_pos, uv_y).rgb * weights.y;
    vec3 color_z = texture(texture_y_pos, uv_z).rgb * weights.z;
	
	vec3 all_side = (texture(texture_side, uv_x).rgb * weights.x + texture(texture_side, uv_y).rgb * weights.y + texture(texture_side, uv_z).rgb * weights.z)/3.0;
	vec3 all_y_pos = (texture(texture_y_pos, uv_x).rgb * weights.x + texture(texture_y_pos, uv_y).rgb * weights.y + texture(texture_y_pos, uv_z).rgb * weights.z)/3.0;
	vec3 all_y_neg = (texture(texture_y_neg, uv_x).rgb * weights.x + texture(texture_y_neg, uv_y).rgb * weights.y + texture(texture_y_neg, uv_z).rgb * weights.z)/3.0;
    
	vec3 adjusted_relative_normal = pow(abs(relative_normal), vec3(4.0));
    //vec3 weights = adjusted_normal / (adjusted_normal.x + adjusted_normal.y + adjusted_normal.z) * 3.0;
	
	vec3 color = all_side * length(adjusted_relative_normal.xz) + mix(all_y_neg, all_y_pos, use_y_up) * adjusted_relative_normal.y;
	
    ALBEDO = color;//(color_x + mix(color_y_down, color_y_up, use_y_up) + color_z) / 3.0;
}