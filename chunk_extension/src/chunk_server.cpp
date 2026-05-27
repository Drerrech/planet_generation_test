#include "chunk_server.h"
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/color.hpp>

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

static void _apply_bin(float *arr, const char *user_dir, int chunk_id) {
    char path[512];
    snprintf(path, sizeof(path), "%splayer_delta/test_planet/%d.bin", user_dir, chunk_id);
    FILE *f = fopen(path, "rb");
    if (!f) return;
    int idx; float val;
    while (fread(&idx, sizeof(int), 1, f) == 1) {
        fread(&val, sizeof(float), 1, f);
        arr[idx] = val;
    }
    fclose(f);
}

static ChunkData *_make_chunk(int chunk_id, float x, float y, float z, const char *user_dir) {
    ChunkData *c = (ChunkData *)malloc(sizeof(ChunkData));
    c->base_arr = (float *)malloc(ARR_SIZE * sizeof(float));
    fill_chunk_array(c->base_arr, x, y, z);
    c->arr = (float *)malloc(ARR_SIZE * sizeof(float));
    memcpy(c->arr, c->base_arr, ARR_SIZE * sizeof(float));
    _apply_bin(c->arr, user_dir, chunk_id);
    c->v_a = march_and_build_mesh(c->arr);
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
    PackedColorArray colors;
    colors.resize(v_a.size);
    Vector3 *w = verts.ptrw();
    Color *c = colors.ptrw();
    for (int i = 0; i < v_a.size; i++) {
        w[i] = Vector3(v_a.v_arr[i].x, v_a.v_arr[i].y, v_a.v_arr[i].z);
        c[i] = Color(v_a.v_arr[i].r, v_a.v_arr[i].g, v_a.v_arr[i].b, v_a.v_arr[i].a);
    }
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = verts;
    arrays[Mesh::ARRAY_COLOR] = colors;
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
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

Ref<ArrayMesh> ChunkServer::update_chunk(int chunk_id, float x, float y, float z, Dictionary delta) {
    ChunkData *c = (ChunkData *)chunks[chunk_id];
    if (!c) {
        c = _make_chunk(chunk_id, x, y, z, user_dir);
        chunks[chunk_id] = c;
    }

    memcpy(c->arr, c->base_arr, ARR_SIZE * sizeof(float));

    Array keys = delta.keys();
    for (int i = 0; i < keys.size(); i++) {
        int idx = (int)keys[i];
        if (idx >= 0 && idx < ARR_SIZE) {
            c->arr[idx] = (float)delta[keys[i]];
        }
    }

    delete_vertex_array(&c->v_a);
    c->v_a = march_and_build_mesh(c->arr);
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
    ClassDB::bind_method(D_METHOD("update_chunk", "chunk_id", "x", "y", "z", "delta"), &ChunkServer::update_chunk);
    ClassDB::bind_method(D_METHOD("free_chunk", "chunk_id"), &ChunkServer::free_chunk);
}
