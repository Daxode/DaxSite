package renderer

import "core:fmt"
import "vendor:wgpu"

resize_screen :: proc(render_manager: ^RenderManagerState) {
    wgpu.SurfaceConfigure(render_manager.surface, &render_manager.config)
    if render_manager.depthTexture != nil {
        // Destroy the old depth texture
        wgpu.TextureViewRelease(render_manager.depthView)
        wgpu.TextureDestroy(render_manager.depthTexture)
        wgpu.TextureRelease(render_manager.depthTexture)
    }
    
    // Create Depth Texture
    depthFormat := wgpu.TextureFormat.Depth24Plus
    render_manager.depthTexture = wgpu.DeviceCreateTexture(render_manager.device, &wgpu.TextureDescriptor{
        label = "Depth Texture",
        size = {render_manager.config.width, render_manager.config.height, 1},
        mipLevelCount = 1,
        sampleCount = 1,
        dimension = ._2D,
        format = .Depth24Plus,
        usage = {.RenderAttachment},
        viewFormatCount = 1,
        viewFormats = &depthFormat,
    });
    render_manager.depthView = wgpu.TextureCreateView(render_manager.depthTexture, &wgpu.TextureViewDescriptor{
        label = "Depth Texture View",
        format = .Depth24Plus,
        dimension = ._2D,
        aspect = .DepthOnly,
        baseMipLevel = 0,
        mipLevelCount = 1,
        baseArrayLayer = 0,
        arrayLayerCount = 1,
    });
}