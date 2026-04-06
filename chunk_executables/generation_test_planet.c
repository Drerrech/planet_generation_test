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
    
    cellular_eucl_sq_mul_noise = fnlCreateState();
    cellular_eucl_sq_mul_noise.noise_type = FNL_NOISE_CELLULAR;
    cellular_eucl_sq_mul_noise.cellular_distance_func = FNL_CELLULAR_DISTANCE_EUCLIDEANSQ;
    cellular_eucl_sq_mul_noise.cellular_return_type = FNL_CELLULAR_RETURN_TYPE_DISTANCE2MUL;

    cellular_eucl_sq_div_noise = fnlCreateState();
    cellular_eucl_sq_div_noise.noise_type = FNL_NOISE_CELLULAR;
    cellular_eucl_sq_div_noise.cellular_distance_func = FNL_CELLULAR_DISTANCE_EUCLIDEANSQ;
    cellular_eucl_sq_div_noise.cellular_return_type = FNL_CELLULAR_RETURN_TYPE_DISTANCE2DIV;
}

const float SUFACE_LEVEL_MOUNTAIN_HEIGHT = 10.f;

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

    float final_val = 0.f;

    //mountains
    if (point_r >= 0.9f * PLANET_LEVEL_R) {
        // want range [-0.700 -0.500] -> [0, 1]
        float _l = -0.900f; float _h = -0.700f;
        float mountain_addition = (-_l + fmin(fmax(fnlGetNoise3D(&cellular_eucl_sq_sub_noise, unit_dir_x * 500.f, unit_dir_y * 500.f, unit_dir_z * 500.f), _l), _h)) / (_h - _l);
        // float mountain_addition = (fnlGetNoise3D(&cellular_eucl_sq_sub_noise, x, y, z) + 1.f) * 0.5f;
        float surface_addition = PLANET_LEVEL_R - point_r;
        float mountain_value = fmax(fmin(0.05f * (surface_addition + SUFACE_LEVEL_MOUNTAIN_HEIGHT * mountain_addition), 1.0f), -1.0f);

        final_val += mountain_value;
    }

    // cave shafts
    if (point_r >= 0.85f * PLANET_LEVEL_R) {
        float _l = -1.000f; float _h = -0.800f;
        // -> [0, 1] -> [-1, 1]
        float mask = (-_l + fmin(fmax(fnlGetNoise3D(&simplex2_noise, unit_dir_x * 1000.f, unit_dir_y * 1000.f, unit_dir_z * 1000.f), _l), _h)) / (_h - _l);
        mask = mask*2.f - 1.f;
        if (mask < 0) {
            // float _l = -0.950f; float _h = -0.750f;
            // float cave_value = (-_l + fmin(fmax(fnlGetNoise3D(&cellular_eucl_sq_mul_noise, x * 5.f, y * 5.f, z * 5.f), _l), _h)) / (_h - _l);
            // final_val += cave_value; // -mask * 
            final_val = -1;
        }
    }

    // caves
    if (point_r < 0.9f * PLANET_LEVEL_R) {
        float mask = fnlGetNoise3D(&simplex2_noise, x * 1.f, y * 1.f, z * 1.f);
        if (mask < 0) {
            float _l = -0.950f; float _h = -0.750f;
            // -> [0, 1] -> [-1, 1]
            float cave_value = (-_l + fmin(fmax(fnlGetNoise3D(&cellular_eucl_sq_mul_noise, x * 5.f, y * 5.f, z * 5.f), _l), _h)) / (_h - _l);
            cave_value = cave_value*2.f - 1.f;
            final_val += cave_value; // -mask * 
        } else {
            final_val += mask;

            // final_val += 1;
        }
    }

    // final value (scaled)
    return fmax(fmin(final_val, 1.0f), -1.0f);
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

VertexArray march_and_build_mesh(float *arr) {
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

                    v_a.v_arr[v_a.size] = v;
                    v_a.size++;
                }
            }
        }
    }
    // return the vertex array (includes size)
    return v_a;
}