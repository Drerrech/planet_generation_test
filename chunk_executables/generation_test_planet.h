#define MAX_NUM_CHUNKS 32*32*32
#define PLANET_LEVEL_R 240.0f
#define PLANET_LEVEL_R_SQ (PLANET_LEVEL_R*PLANET_LEVEL_R)
#define ISO_LEVEL 0.0f

#define CHUNK_SIDE_SIZE 17 // number of points, so x-1 cells
#define CHUNK_CELL_SIDE_SIZE 1.0f

#define MAX_NUM_VERTICES (15 * (CHUNK_SIDE_SIZE - 1) * (CHUNK_SIDE_SIZE - 1) * (CHUNK_SIDE_SIZE - 1)) // maximum of 15 vertices per cube (with duplicates)


typedef struct {
    float x, y, z;
    // float nx, ny, nz;
    // float u, v;
} Vertex;

typedef struct {
    Vertex *v_arr;
    int size;
} VertexArray;

VertexArray make_vertex_array();
void delete_vertex_array(VertexArray *v_a);

void init_noise();
void fill_chunk_array(float *arr, float x_global, float y_global, float z_global);

VertexArray march_and_build_mesh(float *arr);
