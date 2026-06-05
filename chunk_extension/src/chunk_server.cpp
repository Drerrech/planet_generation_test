#include "chunk_server.h"
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <cstdint>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>

extern "C" {
#include "generation_test_planet.h"
}

using namespace godot;

struct ChunkData {
    float *base_arr;
    float *arr;
    VertexArray v_a;
};

static const int ARR_SIZE = CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE;

static float _half_to_float(uint16_t h) {
    uint32_t sign     = (uint32_t)(h & 0x8000u) << 16;
    uint32_t exp      = (h >> 10) & 0x1Fu;
    uint32_t mantissa = h & 0x3FFu;
    uint32_t result;
    if (exp == 0u) {
        result = sign | (mantissa << 13);  // zero or subnormal
    } else if (exp == 31u) {
        result = sign | 0x7F800000u | (mantissa << 13);  // inf / nan
    } else {
        result = sign | ((exp + 112u) << 23) | (mantissa << 13);
    }
    float f;
    memcpy(&f, &result, sizeof(float));
    return f;
}

// Binary format per entry: [uint16 idx][float16 value][uint8 type] = 5 bytes
static void _apply_bin(float *arr, int *cell_type, const char *user_dir, int chunk_id) {
    char path[512];
    snprintf(path, sizeof(path), "%splayer_delta/test_planet/%d.bin", user_dir, chunk_id);
    FILE *f = fopen(path, "rb");
    if (!f) return;
    uint16_t idx16, val16; uint8_t type;
    while (fread(&idx16, sizeof(uint16_t), 1, f) == 1) {
        if (fread(&val16, sizeof(uint16_t), 1, f) != 1) break;
        if (fread(&type,  sizeof(uint8_t),  1, f) != 1) break;
        int idx = (int)idx16;
        arr[idx] = _half_to_float(val16);
        cell_type[idx] = (int)type;
    }
    fclose(f);
}

static ChunkData *_make_chunk(int chunk_id, float x, float y, float z, const char *user_dir) {
    ChunkData *c = (ChunkData *)malloc(sizeof(ChunkData));
    c->base_arr = (float *)malloc(ARR_SIZE * sizeof(float));
    fill_chunk_array(c->base_arr, x, y, z);
    c->arr = (float *)malloc(ARR_SIZE * sizeof(float));
    memcpy(c->arr, c->base_arr, ARR_SIZE * sizeof(float));
    int cell_type[ARR_SIZE] = {};
    _apply_bin(c->arr, cell_type, user_dir, chunk_id);
    c->v_a = march_and_build_mesh(c->arr, cell_type, x, y, z);
    return c;
}

static void _free_chunk(ChunkData *c) {
    free(c->base_arr);
    free(c->arr);
    delete_vertex_array(&c->v_a);
    free(c);
}

static Ref<ArrayMesh> _to_mesh(const VertexArray &v_a) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    if (v_a.size == 0) return mesh;
    PackedVector3Array verts;
    verts.resize(v_a.size);
    PackedFloat32Array custom0;
    custom0.resize(v_a.size * 4);
    Vector3 *w = verts.ptrw();
    float *c = custom0.ptrw();
    for (int i = 0; i < v_a.size; i++) {
        w[i] = Vector3(v_a.v_arr[i].x, v_a.v_arr[i].y, v_a.v_arr[i].z);
        c[i * 4 + 0] = v_a.v_arr[i].r;
        c[i * 4 + 1] = v_a.v_arr[i].g;
        c[i * 4 + 2] = v_a.v_arr[i].b;
        c[i * 4 + 3] = v_a.v_arr[i].a;
    }
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_CUSTOM0] = custom0;
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(),
        Mesh::ARRAY_FORMAT_CUSTOM0 | (Mesh::ARRAY_CUSTOM_RGBA_FLOAT << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT));
    return mesh;
}

ChunkServer::ChunkServer() {
    memset(chunks, 0, sizeof(chunks));
    strcpy(user_dir, "./");
    init_noise();
}

ChunkServer::~ChunkServer() {
    for (int i = 0; i < MAX_CHUNKS; i++) {
        if (chunks[i]) {
            _free_chunk((ChunkData *)chunks[i]);
            chunks[i] = nullptr;
        }
    }
}

void ChunkServer::set_user_dir(String path) {
    CharString cs = path.utf8();
    const char *s = cs.get_data();
    strncpy(user_dir, s, sizeof(user_dir) - 2);
    user_dir[sizeof(user_dir) - 2] = '\0';
    int len = strlen(user_dir);
    if (len > 0 && user_dir[len - 1] != '/' && user_dir[len - 1] != '\\') {
        user_dir[len] = '/';
        user_dir[len + 1] = '\0';
    }
}

Dictionary ChunkServer::generate_chunk(int chunk_id, float x, float y, float z) {
    if (chunks[chunk_id]) {
        _free_chunk((ChunkData *)chunks[chunk_id]);
    }
    ChunkData *c = _make_chunk(chunk_id, x, y, z, user_dir);
    chunks[chunk_id] = c;

    PackedFloat32Array pv;
    pv.resize(ARR_SIZE);
    memcpy(pv.ptrw(), c->arr, ARR_SIZE * sizeof(float));

    Dictionary result;
    result["mesh"] = _to_mesh(c->v_a);
    result["point_values"] = pv;
    return result;
}

Ref<ArrayMesh> ChunkServer::update_chunk(int chunk_id, float x, float y, float z, Dictionary delta, Dictionary delta_type) {
    ChunkData *c = (ChunkData *)chunks[chunk_id];
    if (!c) {
        c = _make_chunk(chunk_id, x, y, z, user_dir);
        chunks[chunk_id] = c;
    }

    memcpy(c->arr, c->base_arr, ARR_SIZE * sizeof(float));

    int cell_type[ARR_SIZE] = {};
    Array keys = delta.keys();
    for (int i = 0; i < keys.size(); i++) {
        int idx = (int)keys[i];
        if (idx >= 0 && idx < ARR_SIZE) {
            c->arr[idx] = (float)delta[keys[i]];
            if (delta_type.has(keys[i])) {
                cell_type[idx] = (int)delta_type[keys[i]];
            }
        }
    }

    delete_vertex_array(&c->v_a);
    c->v_a = march_and_build_mesh(c->arr, cell_type, x, y, z);
    return _to_mesh(c->v_a);
}

void ChunkServer::free_chunk(int chunk_id) {
    if (chunks[chunk_id]) {
        _free_chunk((ChunkData *)chunks[chunk_id]);
        chunks[chunk_id] = nullptr;
    }
}

void ChunkServer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_user_dir", "path"), &ChunkServer::set_user_dir);
    ClassDB::bind_method(D_METHOD("generate_chunk", "chunk_id", "x", "y", "z"), &ChunkServer::generate_chunk);
    ClassDB::bind_method(D_METHOD("update_chunk", "chunk_id", "x", "y", "z", "delta", "delta_type"), &ChunkServer::update_chunk);
    ClassDB::bind_method(D_METHOD("free_chunk", "chunk_id"), &ChunkServer::free_chunk);
}
