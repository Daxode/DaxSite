package importer_model

import "core:fmt"
import gltf2 "../glTF2"
import renderer "../renderer"
import ig "core:image/png"
import "vendor:wgpu"
import "core:math/linalg"

MeshWithMaterial :: struct {
    meshTemplate: renderer.MeshTemplateIndex,
    renderInstance: renderer.RenderInstanceIndex,
}

load_model :: proc {
    load_model_from_data,
    load_model_from_buffer,
}

load_model_from_buffer :: proc(buffer: []byte, render_set: ^renderer.RendererSet($TVert, $TUniform)) -> []MeshWithMaterial {
    model_data, model_load_error := gltf2.parse(buffer, gltf2.Options{
        is_glb = true,
    })
    if model_load_error != nil {
        fmt.panicf("Failed to load model", model_load_error)
    }
    return load_model_from_data(model_data, render_set)
}

load_model_from_data :: proc(model_data: ^gltf2.Data, render_set: ^renderer.RendererSet($TVert, $TUniform)) -> []MeshWithMaterial {
    result := make([dynamic]MeshWithMaterial)
    unique_materials := make(map[string]renderer.RenderInstanceIndex)

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
                        stride, stride_ok := buffer_view.byte_stride.?
                        stride = stride_ok ? stride : 12 
                        for &vert, i in mesh_verts {
                            index := u32(i)*stride + buffer_view.byte_offset + pos_attr.byte_offset
                            vert.position = (transmute(^[3]f32)raw_data(buffer_uri[index:]))^
                            vert.uv = vert.position.xy + 0.5
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
                            stride, stride_ok := buffer_view.byte_stride.?
                            stride = stride_ok ? stride : 12
                            for &vert, i in mesh_verts {
                                index := u32(i)*stride + buffer_view.byte_offset + normal_attr.byte_offset
                                vert.normal = (transmute(^[3]f32)raw_data(buffer_uri[index:]))^
                                // fmt.println("Normal", i, "is", vert)
                            }
                    }
                }
            }

            if uv_attr_index, has_uv_attr := primitive.attributes["TEXCOORD_0"]; has_uv_attr {
                uv_attr := model_data.accessors[uv_attr_index]
                if buffer_view_index, buffer_view_ok := uv_attr.buffer_view.?; buffer_view_ok {
                    buffer_view := model_data.buffer_views[buffer_view_index]
                    // fmt.println("Buffer view has", buffer_view)
                    buffer := model_data.buffers[buffer_view.buffer]
                    switch buffer_uri in buffer.uri {
                        case string:
                            fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                        case []byte:
                            stride, stride_ok := buffer_view.byte_stride.?
                            stride = stride_ok ? stride : 8
                            for &vert, i in mesh_verts {
                                index := u32(i)*stride + buffer_view.byte_offset + uv_attr.byte_offset
                                vert.uv = (transmute(^[2]f32)raw_data(buffer_uri[index:]))^
                                // fmt.println("Normal", i, "is", vert)
                            }
                    }
                }
            }

            for attr, attr_index in primitive.attributes {
                if attr == "POSITION" || attr == "NORMAL" || attr == "TEXCOORD_0" {
                    continue
                }
                attr_data := model_data.accessors[attr_index]
                fmt.println("Attribute", attr, "has accessor", attr_data)
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

            // Get material of primitive
            renderer_material_index: renderer.RenderInstanceIndex
            if material_index, material_ok := primitive.material.?; material_ok{
                material := model_data.materials[material_index]
                material_name := material.name.? or_else "default" // should be unique
                if material_name in unique_materials {
                    renderer_material_index = unique_materials[material_name]
                } else {
                    // Try to create material
                    found_texture_index: renderer.TextureIndex = -1

                    // Get texture of material
                    if metallic_roughness_info, metallic_roughness_ok := material.metallic_roughness.?; metallic_roughness_ok {
                        if base_color_texture_info, base_color_texture_ok := metallic_roughness_info.base_color_texture.?; base_color_texture_ok {
                            base_color_texture := model_data.textures[base_color_texture_info.index]
                            
                            // Get image of texture
                            if base_color_image_index, base_color_image_ok := base_color_texture.source.?; base_color_image_ok {
                                base_color_sampler_index, base_color_sampler_ok := base_color_texture.sampler.?;
                                // assert(base_color_sampler_ok, "Texture has no sampler")
                                // base_color_sampler := model_data.samplers[base_color_sampler_index]
                                base_color_image := model_data.images[base_color_image_index]
    
                                // fmt.println("Base color texture", base_color_image, "with sampler", base_color_sampler)
                                
                                // Load image
                                if buffer_view_index, buffer_view_ok := base_color_image.buffer_view.?; buffer_view_ok {
                                    buffer_view := model_data.buffer_views[buffer_view_index]
                                    buffer := model_data.buffers[buffer_view.buffer]
                                    switch buffer_uri in buffer.uri {
                                        case string:
                                            fmt.panicf("Buffer has URI", buffer_uri, "which is not supported currently.. Might be able to use fetch in future")
                                        case []byte:
                                            data := buffer_uri[buffer_view.byte_offset:buffer_view.byte_offset+buffer_view.byte_length]
                                            image_type, _ := base_color_image.type.?
                                            switch image_type {
                                                case .PNG:
                                                    found_texture_index = create_texture_from_png(render_set, data)
                                                case .JPEG:
                                                    found_texture_index = create_texture_from_png(render_set, #load("../../resources/models/DaxLogoFlatGradientLongerStroked.png"))
                                                    fmt.println("JPEG images are not supported yet, using fallback image")
                                            }
                                    }
                                }
                            }
                        }
                    }

                    if found_texture_index == -1 {
                        found_texture_index = create_texture_from_png(render_set, #load("../../resources/models/DaxLogoFlatGradientLongerStroked.png"))
                    }
                    append(&render_set.renderInstances, renderer.RenderInstance(renderer.Vertex, renderer.UniformData) {renderer.createDefaultMaterialTemplate(render_set.owningState.device), {
                        found_texture_index, -1, -1, -1
                    }});
                    renderer_material_index = renderer.RenderInstanceIndex(len(render_set.renderInstances)-1)
                }
            } else {
                // Create fallback material
                append(&render_set.renderInstances, renderer.RenderInstance(renderer.Vertex, renderer.UniformData) {renderer.createDefaultMaterialTemplate(render_set.owningState.device), {
                    create_texture_from_png(render_set, #load("../../resources/models/DaxLogoFlatGradientLongerStroked.png")), -1, -1, -1
                }});
                renderer_material_index = renderer.RenderInstanceIndex(len(render_set.renderInstances)-1)
            }
            fmt.println("Creating mesh with", len(mesh_verts), "vertices and", len(mesh_indices), "indices")
            // fmt.println("Vertices", mesh_verts)
            // fmt.println("Indices", mesh_indices)

            mesh_template := renderer.createMeshTemplate(render_set.owningState.device, mesh_verts[:], mesh_indices[:], TVert, TUniform)
            append(&render_set.meshTemplates, mesh_template)
            append(&result, MeshWithMaterial{renderer.MeshTemplateIndex(len(render_set.meshTemplates)-1), renderer.RenderInstanceIndex(renderer_material_index)})
        }
    }
    return result[:]
}

create_texture_from_png :: proc(render_set: ^renderer.RendererSet($TVert, $TUniform), image: []byte) -> renderer.TextureIndex {
    result: renderer.Texture
    fmt.println("Image has", len(image), "bytes")
    if img, img_err := ig.load_from_bytes(image); img_err == nil {
        fmt.println("Loaded image", img)

        data := img.pixels.buf
        if img.channels == 3 {
            data = make([dynamic]u8, img.width*img.height*4)
            for pixel_y in 0..<img.height {
                for pixel_x in 0..<img.width {
                    pixel := transmute(^[3]u8)(&img.pixels.buf[(pixel_y*img.width*3 + pixel_x*3)]);
                    (transmute(^[3]u8)&data[pixel_y*img.width*4 + pixel_x*4])^ = pixel^
                    data[pixel_y*img.width*4 + pixel_x*4 + 3] = 255
                }
            }
        }
        assert(img.channels == 3 || img.channels==4, "Image has to have 3/4 channels")
        assert(img.depth == 8, "Image has to have the 4 channels as 8 bit each")
        texture_desc := wgpu.TextureDescriptor{
            label = "Texture",
            size = wgpu.Extent3D{
                width = u32(img.width),
                height = u32(img.height),
                depthOrArrayLayers=1
            },
            mipLevelCount = 1,
            sampleCount = 1,
            dimension = ._2D,
            format = .RGBA8Unorm,
            usage = {.TextureBinding, .CopyDst},
            viewFormatCount = 0,
            viewFormats = nil,
        };
        result.texture = wgpu.DeviceCreateTexture(render_set.owningState.device, &texture_desc)
        dest := wgpu.ImageCopyTexture{
            texture = result.texture,
            mipLevel = 0,
            origin = wgpu.Origin3D{
                x = 0,
                y = 0,
                z = 0,
            },
            aspect = .All
        }
        source := wgpu.TextureDataLayout{
            offset = 0,
            bytesPerRow = u32(4*img.width),
            rowsPerImage = u32(img.height),
        }
        wgpu.QueueWriteTexture(render_set.owningState.queue, &dest, raw_data(data), uint(img.width*img.height*(img.depth/2)), &source, &texture_desc.size)
        result.view = wgpu.TextureCreateView(result.texture, &wgpu.TextureViewDescriptor{
            label = "Material Texture View",
            format = .RGBA8Unorm,
            dimension = ._2D,
            aspect = .All,
            baseMipLevel = 0,
            mipLevelCount = 1,
            baseArrayLayer = 0,
            arrayLayerCount = 1,
        });
        append(&render_set.textures, result)
    } else {
        fmt.panicf("Failed to load image", img_err)
    }
    return renderer.TextureIndex(len(render_set.textures)-1)
}