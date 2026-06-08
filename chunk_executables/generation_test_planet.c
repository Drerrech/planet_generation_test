#include "generation_test_planet.h"
#include "constants.h"

#include "FastNoiseLite.h"

#include <stdlib.h>
#include <math.h>

// defining planet generation logic
// -1 - empty
// +1 - full
static fnl_state simplex2_noise;  // global to this file
static fnl_state cellular_eucl_sq_sub_noise;
static fnl_state cellular_eucl_sq_mul_noise;
static fnl_state cellular_eucl_sq_div_noise;

void init_noise() {
    simplex2_noise = fnlCreateState();
    simplex2_noise.noise_type = FNL_NOISE_OPENSIMPLEX2;

    cellular_eucl_sq_sub_noise = fnlCreateState();
    cellular_eucl_sq_sub_noise.noise_type = FNL_NOISE_CELLULAR;
    cellular_eucl_sq_sub_noise.cellular_distance_func = FNL_CELLULAR_DISTANCE_EUCLIDEANSQ;
    cellular_eucl_sq_sub_noise.cellular_return_type = FNL_CELLULAR_RETURN_TYPE_DISTANCE2SUB;
    cellular_eucl_sq_sub_noise.cellular_jitter_mod = 0.0f;
    
    cellular_eucl_sq_mul_noise = fnlCreateState();
    cellular_eucl_sq_mul_noise.noise_type = FNL_NOISE_CELLULAR;
    cellular_eucl_sq_mul_noise.cellular_distance_func = FNL_CELLULAR_DISTANCE_EUCLIDEANSQ;
    cellular_eucl_sq_mul_noise.cellular_return_type = FNL_CELLULAR_RETURN_TYPE_DISTANCE2MUL;

    cellular_eucl_sq_div_noise = fnlCreateState();
    cellular_eucl_sq_div_noise.noise_type = FNL_NOISE_CELLULAR;
    cellular_eucl_sq_div_noise.cellular_distance_func = FNL_CELLULAR_DISTANCE_EUCLIDEANSQ;
    cellular_eucl_sq_div_noise.cellular_return_type = FNL_CELLULAR_RETURN_TYPE_DISTANCE2DIV;
}

const int NUM_BIOMES_AXIS_1 = 2;
const int NUM_BIOMES_AXIS_2 = 2;
const float BIOME_TRANSITION_MARGIN = 0.1f; // (0, 0.5]

const float SUFACE_LEVEL_MOUNTAIN_HEIGHT = 20.f;

float scale_to_0_1(float l, float h, float val) {
    return (fmin(fmax(val, l), h) - l) / (h - l);
}

float scale_to_neg_1_1(float l, float h, float val) {
    return (fmin(fmax(val, l), h) - l) / (h - l) * 2.f - 1.f;
}

// temperature
float get_biome_axis_1_surface(float unit_dir_x, float unit_dir_y, float unit_dir_z) {
    return (NUM_BIOMES_AXIS_1-1.f) * 0.5f * (fnlGetNoise3D(&simplex2_noise, 400.f * unit_dir_x, 400.f * unit_dir_y, 400.f * unit_dir_z) + 1.f);
}
// fertility
float get_biome_axis_2_surface(float unit_dir_x, float unit_dir_y, float unit_dir_z) {
    return (NUM_BIOMES_AXIS_2-1.f) * 0.5f * (fnlGetNoise3D(&simplex2_noise, 300.f * unit_dir_x + 100000.f, 300.f * unit_dir_y, 300.f * unit_dir_z) + 1.f);
}

// BIOME MATRIX
// hill(2)   mushroom(3)
// plains(0) creeks(1)
// and addapter to connect

float get_adapter_val(float x, float y, float z, float point_r_sq, float point_r, float unit_dir_x, float unit_dir_y, float unit_dir_z) {
    float surface_val = (PLANET_LEVEL_R - point_r) / CHUNK_CELL_SIDE_SIZE;
    surface_val = fmin(fmax(surface_val, -1.0f), 1.0f);

    return surface_val;
}

float get_plains_val(float x, float y, float z, float point_r_sq, float point_r, float unit_dir_x, float unit_dir_y, float unit_dir_z) {
    float surface_val = (PLANET_LEVEL_R - point_r) / CHUNK_CELL_SIDE_SIZE;
    surface_val = fmin(fmax(surface_val, -1.0f), 1.0f);

    return surface_val;
}
float get_creeks_val(float x, float y, float z, float point_r_sq, float point_r, float unit_dir_x, float unit_dir_y, float unit_dir_z, float creek_depth_multiplier) {
    float CREEK_MAX_DEPTH = 4.f;
    
    float creek_depth = creek_depth_multiplier * CREEK_MAX_DEPTH * scale_to_0_1(-0.5f, 0.2f, fnlGetNoise3D(&cellular_eucl_sq_div_noise, 2400.f * unit_dir_x, 2400.f * unit_dir_y, 2400.f * unit_dir_z));
    
    float surface_val = (PLANET_LEVEL_R - point_r - creek_depth) / CHUNK_CELL_SIDE_SIZE;
    
    surface_val = fmin(fmax(surface_val, -1.0f), 1.0f);

    return surface_val;
}
float get_hills_val(float x, float y, float z, float point_r_sq, float point_r, float unit_dir_x, float unit_dir_y, float unit_dir_z, float hill_height_multiplier) {
    float HLL_MAX_HEIGHT = 12.f;
    
    float hill_height = hill_height_multiplier * HLL_MAX_HEIGHT * scale_to_0_1(-1.0f, 1.0f, fnlGetNoise3D(&simplex2_noise, 1200.f * unit_dir_x, 1200.f * unit_dir_y, 1200.f * unit_dir_z));
    
    float surface_val = (PLANET_LEVEL_R - point_r + hill_height) / CHUNK_CELL_SIDE_SIZE;
    
    surface_val = fmin(fmax(surface_val, -1.0f), 1.0f);

    return surface_val;
}
float get_mushrooms_val(float x, float y, float z, float point_r_sq, float point_r, float unit_dir_x, float unit_dir_y, float unit_dir_z, float mushroom_height_multiplier) {
    float MUSHROOM_MAX_HEIGHT = 8.f;
    
    float mushroom_height = mushroom_height_multiplier * MUSHROOM_MAX_HEIGHT * (1.f - scale_to_0_1(-1.0f, -0.94f, fnlGetNoise3D(&cellular_eucl_sq_mul_noise, 2400.f * unit_dir_x, 2400.f * unit_dir_y, 2400.f * unit_dir_z)));
    
    float surface_val = (PLANET_LEVEL_R - point_r + mushroom_height) / CHUNK_CELL_SIDE_SIZE;
    
    surface_val = fmin(fmax(surface_val, -1.0f), 1.0f);

    return surface_val;
}

float get_biome_val_surface(float x, float y, float z, float point_r_sq, float point_r, float unit_dir_x, float unit_dir_y, float unit_dir_z) {
    float biome_x1 = get_biome_axis_1_surface(unit_dir_x, unit_dir_y, unit_dir_z);
    float biome_x2 = get_biome_axis_2_surface(unit_dir_x, unit_dir_y, unit_dir_z);
    
    float final_val;

    // pure plains
    if (biome_x1 <= 0.5f - BIOME_TRANSITION_MARGIN && biome_x2 <= 0.5f - BIOME_TRANSITION_MARGIN) {
        final_val = get_plains_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);
    } else

    // pure creeks
    if (0.5f + BIOME_TRANSITION_MARGIN <= biome_x1 && biome_x2 <= 0.5f - BIOME_TRANSITION_MARGIN) {
        final_val = get_creeks_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z, 1.f);
    } else

    // pure mountains
    if (biome_x1 <= 0.5f - BIOME_TRANSITION_MARGIN && 0.5f + BIOME_TRANSITION_MARGIN <= biome_x2) {
        final_val = get_hills_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z, 1.f);
    } else

    // pure mushrooms
    if (0.5f + BIOME_TRANSITION_MARGIN <= biome_x1 && 0.5f + BIOME_TRANSITION_MARGIN <= biome_x2) {
        final_val = get_mushrooms_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z, 1.f);
    } else

    // transitions to adapter
    // plains <-> adapter
    if (biome_x1 < 0.5f && biome_x2 < 0.5){
        float adapter_weight = 1.f + (1.f / BIOME_TRANSITION_MARGIN) * fmaxf(+(biome_x1 - 0.5f), +(biome_x2 - 0.5f));
        
        // plains has no attributes
        float plains_val = get_plains_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);
        // for now adapter is also just flat
        float adapter_val = get_adapter_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);

        final_val = fmaxf(plains_val, adapter_val);
    } else

    // creeks <-> adapter
    if (0.5f < biome_x1 && biome_x2 < 0.5){
        float adapter_weight = 1.f + (1.f / BIOME_TRANSITION_MARGIN) * fmaxf(-(biome_x1 - 0.5f), +(biome_x2 - 0.5f));
        
        float creeks_val = get_creeks_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z, 1.f - adapter_weight);
        float adapter_val = get_adapter_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);

        final_val = fminf(creeks_val, adapter_val);
    } else

    // hills <-> adapter
    if (biome_x1 < 0.5f && 0.5 < biome_x2){
        float adapter_weight = 1.f + (1.f / BIOME_TRANSITION_MARGIN) * fmaxf(+(biome_x1 - 0.5f), -(biome_x2 - 0.5f));
        
        float hills_val = get_hills_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z, 1.f - adapter_weight);
        float adapter_val = get_adapter_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);

        final_val = fmaxf(hills_val, adapter_val);
    } else

    // mushrooms <-> adapter
    if (0.5f < biome_x1 && 0.5 < biome_x2){
        float adapter_weight = 1.f + (1.f / BIOME_TRANSITION_MARGIN) * fmaxf(-(biome_x1 - 0.5f), -(biome_x2 - 0.5f));
        
        float mushrooms_val = get_mushrooms_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z, 1.f - adapter_weight);
        float adapter_val = get_adapter_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);

        final_val = fmaxf(mushrooms_val, adapter_val);
    }

    // pure adapter
    else {
        final_val = get_adapter_val(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);
    }

    return final_val;
}



float get_global_value(float x, float y, float z) {
    float point_r_sq = x*x + y*y + z*z;
    float point_r = sqrtf(point_r_sq);

    float unit_dir_x = 0.5773502692f;
    float unit_dir_y = 0.5773502692f;
    float unit_dir_z = 0.5773502692f;
    if (fabs(x) >= 0.000001 || fabs(y) >= 0.000001 || fabs(z) >= 0.000001) {
        unit_dir_x = x / point_r;
        unit_dir_y = y / point_r;
        unit_dir_z = z / point_r;
    }

    // biome generation
    float final_val;
    
    if (point_r < 0.95f * PLANET_LEVEL_R) {
        final_val = 1.;
    }

    // surface and mountains
    else if (point_r < 1.15f * PLANET_LEVEL_R) {
        final_val = get_biome_val_surface(x, y, z, point_r_sq, point_r, unit_dir_x, unit_dir_y, unit_dir_z);
    }

    // sky
    else {
        final_val = -1.0f;
    }

    return final_val;
}


// filling in the chunk array and generating mesh
int get_idx(int x, int y, int z) {
    return x * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE + y * CHUNK_SIDE_SIZE + z;
}

void fill_chunk_array(float *arr, float x_global, float y_global, float z_global) {
    int idx = 0;
    for (int x_idx = 0; x_idx < CHUNK_SIDE_SIZE; x_idx++) {
        for (int y_idx = 0; y_idx < CHUNK_SIDE_SIZE; y_idx++) {
            for (int z_idx = 0; z_idx < CHUNK_SIDE_SIZE; z_idx++) {
                arr[idx] = get_global_value(x_global + x_idx * CHUNK_CELL_SIDE_SIZE, y_global + y_idx * CHUNK_CELL_SIDE_SIZE, z_global + z_idx * CHUNK_CELL_SIDE_SIZE);
                idx++;
            }
        }
    }
}

int get_triangulation_idx(float *arr, int x, int y, int z) {
	int idx = 0b00000000;
    idx |= (arr[get_idx(x, y, z)] > ISO_LEVEL) << 0;
    idx |= (arr[get_idx(x, y, z+1)] > ISO_LEVEL) << 1;
    idx |= (arr[get_idx(x+1, y, z+1)] > ISO_LEVEL) << 2;
	idx |= (arr[get_idx(x+1, y, z)] > ISO_LEVEL) << 3;
	idx |= (arr[get_idx(x, y+1, z)] > ISO_LEVEL) << 4;
	idx |= (arr[get_idx(x, y+1, z+1)] > ISO_LEVEL) << 5;
	idx |= (arr[get_idx(x+1, y+1, z+1)] > ISO_LEVEL) << 6;
	idx |= (arr[get_idx(x+1, y+1, z)] > ISO_LEVEL) << 7;
	
	return idx;
}

VertexArray make_vertex_array() {
    VertexArray v_a;
    v_a.v_arr = malloc(MAX_NUM_VERTICES * sizeof(Vertex));
    v_a.size = 0;
    return v_a;
}

void delete_vertex_array(VertexArray *v_a) {
    free(v_a->v_arr);
}

VertexArray march_and_build_mesh(float *arr, int *cell_type, float chunk_x, float chunk_y, float chunk_z) {
    VertexArray v_a = make_vertex_array();
    
    for (int x_idx = 0; x_idx < CHUNK_SIDE_SIZE - 1; x_idx++) {
        for (int y_idx = 0; y_idx < CHUNK_SIDE_SIZE - 1; y_idx++) {
            for (int z_idx = 0; z_idx < CHUNK_SIDE_SIZE - 1; z_idx++) {
                int triangulation_idx = get_triangulation_idx(arr, x_idx, y_idx, z_idx);

                for (int i = 0; i < 16; i++) {
                    int edge_idx = TRIANGULATIONS[triangulation_idx][i];
                    if (edge_idx == -1) break;

                    const int *point_idx = EDGES[edge_idx];

                    const int *p0 = POINTS[point_idx[0]];
                    const int *p1 = POINTS[point_idx[1]];

                    float p0_val = arr[get_idx(p0[0] + x_idx, p0[1] + y_idx, p0[2] + z_idx)];
                    float p1_val = arr[get_idx(p1[0] + x_idx, p1[1] + y_idx, p1[2] + z_idx)];

                    int p0_type = cell_type[get_idx(p0[0] + x_idx, p0[1] + y_idx, p0[2] + z_idx)];
                    int p1_type = cell_type[get_idx(p1[0] + x_idx, p1[1] + y_idx, p1[2] + z_idx)];

                    // interpolate and multiply vector by cell size (identical in logic, but less repetition)
                    float t = (ISO_LEVEL - p0_val) / (p1_val - p0_val);
                    float p_inter_pos[] = {
                        (x_idx + p0[0] + t * (p1[0] - p0[0])) * CHUNK_CELL_SIDE_SIZE,
                        (y_idx + p0[1] + t * (p1[1] - p0[1])) * CHUNK_CELL_SIDE_SIZE,
                        (z_idx + p0[2] + t * (p1[2] - p0[2])) * CHUNK_CELL_SIDE_SIZE
                    };

                    // append vertex to mesh (duplicates will be removed by godot)
                    Vertex v;
                    v.x = p_inter_pos[0]; v.y = p_inter_pos[1]; v.z = p_inter_pos[2];
                    
                    // r - biome
                    // g - cell type (int)
                    // b - 
                    // a - 

                    // TODO biomes
                    float x = chunk_x + v.x;
                    float y = chunk_y + v.y;
                    float z = chunk_z + v.z;

                    float point_r_sq = x*x + y*y + z*z;
                    float point_r = sqrtf(point_r_sq);

                    
                    float unit_dir_x = 0.5773502692f;
                    float unit_dir_y = 0.5773502692f;
                    float unit_dir_z = 0.5773502692f;
                    if (fabs(x) >= 0.000001 || fabs(y) >= 0.000001 || fabs(z) >= 0.000001) {
                        unit_dir_x = x / point_r;
                        unit_dir_y = y / point_r;
                        unit_dir_z = z / point_r;
                    }
                    
                    // biome
                    // v.r = 2.f * floorf(2.f * get_biome_axis_2_surface(unit_dir_x, unit_dir_y, unit_dir_z)) + floorf(2.f * get_biome_axis_1_surface(unit_dir_x, unit_dir_y, unit_dir_z));
                    float a1 = get_biome_axis_1_surface(unit_dir_x, unit_dir_y, unit_dir_z);
                    float a2 = get_biome_axis_2_surface(unit_dir_x, unit_dir_y, unit_dir_z);
                    float g1 = fminf(fmaxf((a1 - 0.5f) / (2.f * BIOME_TRANSITION_MARGIN) + 0.5f, 0.f), 1.f);
                    float g2 = fminf(fmaxf((a2 - 0.5f) / (2.f * BIOME_TRANSITION_MARGIN) + 0.5f, 0.f), 1.f);
                    v.r = g1 + 2.f * g2;
                    
                    v.b = a1;
                    v.a = a2;
                    // v.r = 2.f * (get_biome_axis_2_surface(unit_dir_x, unit_dir_y, unit_dir_z)) + (get_biome_axis_1_surface(unit_dir_x, unit_dir_y, unit_dir_z));

                    // cell type
                    if (p0_type == 1 || p1_type == 1) {
                        v.g = 1.f; // player delta is a special case, takes priority
                    } else{
                        v.g = (t <= 0.5f) ? p0_type : p1_type;
                    }
                    
                    v_a.v_arr[v_a.size] = v;
                    v_a.size++;
                }
            }
        }
    }
    // return the vertex array (includes size)
    return v_a;
}