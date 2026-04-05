#include "generation_test_planet.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

#define PORT 9000
#define REQ_GENERATE 1
#define REQ_DELETE 2

typedef struct {
    int chunk_id;
    float x;
    float y;
    float z;

    float *arr;

    VertexArray v_a;
} Chunk;

Chunk* make_chunk(int chunk_id, float x, float y, float z) {
    Chunk *c;
    c = malloc(sizeof(Chunk));

    c->chunk_id = chunk_id;
    c->x = x;
    c->y = y;
    c->z = z;

    c->arr = malloc(CHUNK_SIDE_LEN * CHUNK_SIDE_LEN * CHUNK_SIDE_LEN * sizeof(float));
    fill_chunk_array(c->arr, x, y, z);
    c->v_a = march_and_build_mesh(c->arr);

    return c;
}

void delete_chunk(Chunk *c) {
    free(c->arr);
    delete_vertex_array(&(c->v_a));
    free(c);
}


static int send_all(int sock, const void *buf, size_t len) {
    const char *p = (const char *)buf;
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(sock, p + sent, len - sent, 0);
        if (n <= 0) return -1;
        sent += (size_t)n;
    }
    return 0;
}

int main() {
    // array of chunks, some will be active and malloced, those that are deleted are freed
    Chunk *chunks[MAX_NUM_CHUNKS] = {NULL}; // define to null in case we call free on it
    
    // socket listening stuff
    int server = socket(AF_INET, SOCK_STREAM, 0);

    // allow immediate reuse of port after restart
    int opt = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {0};
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(PORT);
    addr.sin_addr.s_addr = INADDR_ANY;

    bind(server, (struct sockaddr*)&addr, sizeof(addr));
    listen(server, 1);

    printf("[SERVER] server starting on port %d\n", PORT);
    fflush(stdout);

    int client = accept(server, NULL, NULL); // blocks until godot connects
    printf("[SERVER] client connected\n");
    fflush(stdout);

    while (1) {
        // read request type
        uint8_t req_type;
        int r = recv(client, &req_type, 1, MSG_WAITALL);
        if (r <= 0) break;  // godot disconnected

        switch(req_type) {
            case REQ_GENERATE: {
                // recieve args
                int chunk_id; // read chunk id
                recv(client, &chunk_id, sizeof(chunk_id), MSG_WAITALL);
                float chunk_pos[3]; // read chunk position
                recv(client, chunk_pos, sizeof(chunk_pos), MSG_WAITALL);

                printf("[SERVER] generating chunk %d at %.1f %.1f %.1f\n", chunk_id, chunk_pos[0], chunk_pos[1], chunk_pos[2]);
                fflush(stdout);

                // generate chunk and assign pointer to chunks (chunk is responsible for mallocing)
                Chunk *c_pointer = make_chunk(chunk_id, chunk_pos[0], chunk_pos[1], chunk_pos[2]);
                chunks[chunk_id] = c_pointer;
                
                printf("[SERVER] sending %d vertices\n", c_pointer->v_a.size);
                fflush(stdout);
                
                // send generated list of verticies, size and list, godot will remove duplicates and generate mesh
                // send(client, &c_pointer->v_a.size, sizeof(int), 0);
                //send(client, c_pointer->v_a.v_arr, c_pointer->v_a.size * sizeof(Vertex), 0);
                send_all(client, &c_pointer->v_a.size, sizeof(c_pointer->v_a.size));
                send_all(client, c_pointer->v_a.v_arr, (size_t)c_pointer->v_a.size * sizeof(Vertex));
                break;
            }
            case REQ_DELETE: {
                //TODO
                // chunk will get freed, list of verticies with a simplified mesh will be returned
                break;
            }
        }
    }

    close(client);
    close(server);
    return 0;
}