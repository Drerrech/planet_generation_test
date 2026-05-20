#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class ChunkServer : public Node {
    GDCLASS(ChunkServer, Node)

    static const int MAX_CHUNKS = 262144; // big magic number
    void *chunks[MAX_CHUNKS];
    char user_dir[512];

public:
    ChunkServer();
    ~ChunkServer();

    void set_user_dir(String path);
    Dictionary generate_chunk(int chunk_id, float x, float y, float z);
    PackedVector3Array update_chunk(int chunk_id, float x, float y, float z, Dictionary delta);
    void free_chunk(int chunk_id);

protected:
    static void _bind_methods();
};

} // namespace godot
