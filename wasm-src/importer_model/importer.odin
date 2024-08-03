package importer_model

import "core:fmt"
import gltf2 "../glTF2"
import renderer "../renderer"

load_model :: proc {
    load_model_from_data,
    load_model_from_buffer,
}

load_model_from_buffer :: proc(buffer: []byte, state: ^renderer.RenderManagerState) {
    model_data, model_load_error := gltf2.parse(buffer, gltf2.Options{
        is_glb = true,
    })
    if model_load_error != nil {
        fmt.panicf("Failed to load model", model_load_error)
    }
    load_model_from_data(model_data, state)
}

load_model_from_data :: proc(model_data: ^gltf2.Data, state: ^renderer.RenderManagerState) {
    for mesh in model_data.meshes {
        fmt.println("Creating mesh for", mesh.name)
        for primitive in mesh.primitives {
            pos_attr_index, has_pos_attr := primitive.attributes["POSITION"]
            assert(has_pos_attr, "Mesh has no position attribute")
            pos_attr := model_data.accessors[pos_attr_index]
            mesh_verts := make([dynamic]renderer.Vertex, pos_attr.count)
            fmt.println("Mesh has", pos_attr.count, "vertices", "with accessor", pos_attr)

            if buffer_view_index, buffer_view_ok := pos_attr.buffer_view.?; buffer_view_ok {
                buffer_view := model_data.buffer_views[buffer_view_index]
                // fmt.println("Buffer view has", buffer_view)
                buffer := model_data.buffers[buffer_view.buffer]
                switch buffer_uri in buffer.uri {
                    case string:
                        fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                    case []byte:
                        stride, _ := buffer_view.byte_stride.?
                        for &vert, i in mesh_verts {
                            index := u32(i)*stride + buffer_view.byte_offset + pos_attr.byte_offset
                            vert.position = (transmute(^[3]f32)raw_data(buffer_uri[index:]))^
                            // fmt.println("Position", i, "is", vert)
                        }
                }
            }

            if normal_attr_index, has_normal_attr := primitive.attributes["NORMAL"]; has_normal_attr {
                normal_attr := model_data.accessors[normal_attr_index]
                if buffer_view_index, buffer_view_ok := normal_attr.buffer_view.?; buffer_view_ok {
                    buffer_view := model_data.buffer_views[buffer_view_index]
                    // fmt.println("Buffer view has", buffer_view)
                    buffer := model_data.buffers[buffer_view.buffer]
                    switch buffer_uri in buffer.uri {
                        case string:
                            fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                        case []byte:
                            stride, _ := buffer_view.byte_stride.?
                            for &vert, i in mesh_verts {
                                index := u32(i)*stride + buffer_view.byte_offset + normal_attr.byte_offset
                                vert.normal = (transmute(^[3]f32)raw_data(buffer_uri[index:]))^
                                // fmt.println("Normal", i, "is", vert)
                            }
                    }
                }
            }


            index_attr_index, has_index_attr := primitive.indices.?
            assert(has_index_attr, "Mesh has no index attribute")
            index_attr := model_data.accessors[index_attr_index]
            mesh_indices := make([dynamic]u32, index_attr.count)
            if buffer_view_index, buffer_view_ok := index_attr.buffer_view.?; buffer_view_ok {
                buffer_view := model_data.buffer_views[buffer_view_index]
                // fmt.println("Buffer view has", buffer_view)
                buffer := model_data.buffers[buffer_view.buffer]
                switch buffer_uri in buffer.uri {
                    case string:
                        fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                    case []byte:
                        for &mesh_index, i in mesh_indices {
                            index := u32(i)*2 + buffer_view.byte_offset
                            mesh_index = u32((transmute(^u16)raw_data(buffer_uri[index:]))^)
                            // fmt.println("Index", i, "is", mesh_index)
                        }
                }
            }
            // fmt.println("Creating mesh with", len(mesh_verts), "vertices and", len(mesh_indices), "indices")
            // fmt.println("Vertices", mesh_verts)
            // fmt.println("Indices", mesh_indices)

            append(&state.meshes, renderer.createMesh(state.device, mesh_verts[:], mesh_indices[:], &state.material[0]))
        }
    }
}