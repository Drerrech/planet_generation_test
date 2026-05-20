#include "generation_test_planet.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")

static double ms_now(void) {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static char log_path[512];

static void log_ms(const char *label, int chunk_id, double ms) {
    FILE *f = fopen(log_path, "a");
    if (!f) return;
    fprintf(f, "%s chunk %d: %.2f ms\n", label, chunk_id, ms);
    fclose(f);
}

#define REQ_GENERATE 1
#define REQ_DELETE   2
#define REQ_UPDATE   3

static char user_dir[512];

typedef struct {
    int chunk_id;
    float x;
    float y;
    float z;

    float *base_arr;  // pure noise, never modified
    float *arr;       // working array: noise + delta

    VertexArray v_a;
} Chunk;

Chunk* make_chunk(int chunk_id, float x, float y, float z) {
    Chunk *c;
    c = malloc(sizeof(Chunk));

    c->chunk_id = chunk_id;
    c->x = x;
    c->y = y;
    c->z = z;

    int arr_size = CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE;
    c->base_arr = malloc(arr_size * sizeof(float));
    fill_chunk_array(c->base_arr, x, y, z);
    c->arr = malloc(arr_size * sizeof(float));
    memcpy(c->arr, c->base_arr, arr_size * sizeof(float));

    // apply player changes
    char path[256];
    snprintf(path, sizeof(path), "%splayer_delta/test_planet/%d.bin", user_dir, chunk_id);
    FILE *f = fopen(path, "rb");
    if (f != NULL) { // player changed something in this chunk
        int point_idx;
        float point_val;
        while (fread(&point_idx, sizeof(int), 1, f) == 1) {
            fread(&point_val, sizeof(float), 1, f);
            // overwrite chunk's array with the change
            c->arr[point_idx] = point_val;
        }
        fclose(f);
    }

    // build the mesh with (updated) values
    c->v_a = march_and_build_mesh(c->arr);

    return c;
}

void delete_chunk(Chunk *c) {
    free(c->base_arr);
    free(c->arr);
    delete_vertex_array(&(c->v_a));
    free(c);
}


static int send_all(SOCKET sock, const void *buf, size_t len) {
    const char *p = (const char *)buf;
    size_t sent = 0;
    while (sent < len) {
        int n = send(sock, p + sent, (int)(len - sent), 0);
        if (n <= 0) return -1;
        sent += (size_t)n;
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc > 1)
        snprintf(user_dir, sizeof(user_dir), "%s", argv[1]);
    else
        snprintf(user_dir, sizeof(user_dir), "./");

    snprintf(log_path, sizeof(log_path), "%schunk_perf.log", user_dir);

    int port = 8999;
    if (argc > 2)
        port = atoi(argv[2]);

    // init planet noise
    init_noise();

    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);

    // array of chunks, some will be active and malloced, those that are deleted are freed
    Chunk *chunks[MAX_NUM_CHUNKS] = {NULL}; // define to null in case we call free on it

    // socket listening stuff
    SOCKET server = socket(AF_INET, SOCK_STREAM, 0);

    // allow immediate reuse of port after restart
    int opt = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;

    bind(server, (struct sockaddr*)&addr, sizeof(addr));
    listen(server, 1);

    printf("[SERVER] server starting on port %d\n", port);
    fflush(stdout);

    SOCKET client = accept(server, NULL, NULL); // blocks until godot connects
    int nodelay = 1;
    setsockopt(client, IPPROTO_TCP, TCP_NODELAY, (const char*)&nodelay, sizeof(nodelay));
    printf("[SERVER] client connected\n");
    fflush(stdout);

    while (1) {
        // read request type
        uint8_t req_type;
        int r = recv(client, (char*)&req_type, 1, MSG_WAITALL);
        if (r <= 0) break;  // godot disconnected

        switch(req_type) {
            case REQ_GENERATE: {
                int chunk_id;
                recv(client, (char*)&chunk_id, sizeof(chunk_id), MSG_WAITALL);
                float chunk_pos[3];
                recv(client, (char*)chunk_pos, sizeof(chunk_pos), MSG_WAITALL);

                if (chunks[chunk_id] != NULL) {
                    delete_chunk(chunks[chunk_id]);
                }
                double t0 = ms_now();
                Chunk *c_pointer = make_chunk(chunk_id, chunk_pos[0], chunk_pos[1], chunk_pos[2]);
                chunks[chunk_id] = c_pointer;
                log_ms("generate", chunk_id, ms_now() - t0);

                send_all(client, &c_pointer->v_a.size, sizeof(c_pointer->v_a.size));
                send_all(client, c_pointer->v_a.v_arr, (size_t)c_pointer->v_a.size * sizeof(Vertex));
                // send full voxel array so godot can query point values without round trips
                send_all(client, c_pointer->arr, CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE * sizeof(float));
                break;
            }
            case REQ_UPDATE: {
                int chunk_id;
                recv(client, (char*)&chunk_id, sizeof(chunk_id), MSG_WAITALL);
                float chunk_pos[3];
                recv(client, (char*)chunk_pos, sizeof(chunk_pos), MSG_WAITALL);

                Chunk *c = chunks[chunk_id];
                if (c == NULL) {
                    c = make_chunk(chunk_id, chunk_pos[0], chunk_pos[1], chunk_pos[2]);
                    chunks[chunk_id] = c;
                } else {
                    int arr_size = CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE;
                    memcpy(c->arr, c->base_arr, arr_size * sizeof(float));

                    char path[256];
                    snprintf(path, sizeof(path), "%splayer_delta/test_planet/%d.bin", user_dir, chunk_id);
                    FILE *f = fopen(path, "rb");
                    if (f != NULL) {
                        int point_idx;
                        float point_val;
                        while (fread(&point_idx, sizeof(int), 1, f) == 1) {
                            fread(&point_val, sizeof(float), 1, f);
                            c->arr[point_idx] = point_val;
                        }
                        fclose(f);
                    }

                    delete_vertex_array(&c->v_a);
                    double t0 = ms_now();
                    c->v_a = march_and_build_mesh(c->arr);
                    log_ms("update", chunk_id, ms_now() - t0);
                }

                send_all(client, &c->v_a.size, sizeof(c->v_a.size));
                send_all(client, c->v_a.v_arr, (size_t)c->v_a.size * sizeof(Vertex));
                // no voxel array — caller already has it locally
                break;
            }
            case REQ_DELETE: {
                int chunk_id;
                recv(client, (char*)&chunk_id, sizeof(chunk_id), MSG_WAITALL);
                if (chunks[chunk_id] != NULL) {
                    delete_chunk(chunks[chunk_id]);
                    chunks[chunk_id] = NULL;
                }
                break;
            }
        }
    }

    closesocket(client);
    closesocket(server);
    WSACleanup();
    return 0;
}
