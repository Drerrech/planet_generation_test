#include "generation_test_planet.h"
#include "constants.h"

#include <stdlib.h>
#include <math.h>

// defining planet generation logic
// -1 - empty
// +1 - full
float get_global_value(float x, float y, float z) {
    // return 2*(double)rand() / (double)RAND_MAX - 1; // random
    return fmax(fmin(0.005f * (PLANET_LEVEL_R_SQ - (x*x + y*y + z*z)), 1.0f), -1.0f);
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