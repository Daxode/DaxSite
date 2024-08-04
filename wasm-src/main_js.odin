package main

import "vendor:wasm/js"
import "js_ext"
import "base:runtime"
import "core:fmt"
import "core:strconv"
import "vendor:wgpu"

OS :: struct {
    initialized: bool,
}

@(private="file")
g_os: ^OS

os_init :: proc(os: ^OS) {
    g_os = os
    assert(js.add_window_event_listener(.Resize, nil, size_callback))
    assert(js.add_event_listener("start", .Click, os, start_callback))
    assert(js.add_event_listener("stop", .Click, os, stop_callback))

    js.add_window_event_listener(.Touch_Start, nil, proc(e: js.Event) {
        state.touchHeld = true
    })

    js.add_window_event_listener(.Touch_Cancel, nil, proc(e: js.Event) {
        state.touchHeld = false
    })

    js.add_window_event_listener(.Pointer_Move, nil, proc(e: js.Event) {
        if (0 in e.mouse.buttons || state.touchHeld)
        {
            state.clicked += f64(e.mouse.movement.x)/200
            state.clicked = clamp(state.clicked, 0, 1)
            js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", state.clicked))
        }
    })

    js.add_window_event_listener(.Key_Press, nil, proc(e: js.Event) {
        // fmt.println("Key down", e.options)
    })

    js.add_custom_event_listener("pos-x", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.pos.x = f32(strconv.atof(js.get_element_value_string("pos-x", data[:])))
    })

    js.add_custom_event_listener("pos-y", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.pos.y = f32(strconv.atof(js.get_element_value_string("pos-y", data[:])))
    })

    js.add_custom_event_listener("pos-z", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.pos.z = f32(strconv.atof(js.get_element_value_string("pos-z", data[:])))
    })

    js.add_custom_event_listener("cam-x", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.cam_pos.x = f32(strconv.atof(js.get_element_value_string("cam-x", data[:])))
    })

    js.add_custom_event_listener("cam-y", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.cam_pos.y = f32(strconv.atof(js.get_element_value_string("cam-y", data[:])))
    })

    js.add_custom_event_listener("cam-z", "input", nil, proc(e: js.Event) {
        data : [256]byte;
        state.cam_pos.z = f32(strconv.atof(js.get_element_value_string("cam-z", data[:])))
    })


    js.add_window_event_listener(.HashChange, nil, proc(e: js.Event) {
        buf := [256]u8{};
        val := js_ext.get_current_url(buf[:])
        fmt.println("Current URL:", val)
    })
}

// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
os_run :: proc(os: ^OS) {
    os.initialized = true
}

os_get_render_bounds :: proc(os: ^OS) -> (width, height: u32) {
    rect := js.get_bounding_client_rect("c")
    return u32(rect.width), u32(rect.height)
}

os_get_surface :: proc(os: ^OS, instance: wgpu.Instance) -> wgpu.Surface {
    return wgpu.InstanceCreateSurface(
    instance,
    &wgpu.SurfaceDescriptor{
        nextInChain = &wgpu.SurfaceDescriptorFromCanvasHTMLSelector{
            sType = .SurfaceDescriptorFromCanvasHTMLSelector,
            selector = "#c",
        },
    },
    )
}

@(private="file", export)
step :: proc(dt: f32) -> bool {
    if !g_os.initialized {
        return true
    }

    frame(dt)
    return true
}

@(private="file", fini)
os_fini :: proc() {
    js.remove_window_event_listener(.Resize, nil, size_callback)
    js.remove_event_listener("start", .Click, g_os, start_callback)
    js.remove_event_listener("stop", .Click, g_os, stop_callback)

    finish()
}

size_callback :: proc(e: js.Event) {
    resize()
}

start_callback :: proc(e: js.Event) {
    // fmt.println("Clicked!", e)
    state.clicked += 0.1
    state.clicked = clamp(state.clicked, 0, 1)
    js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", state.clicked))
}

stop_callback :: proc(e: js.Event) {
    state.clicked = 0
    js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", state.clicked))
}

@(export)
malloc :: proc "contextless" (size: int, ptrToAlocatedPtr: ^rawptr) {
    context = state.ctx
	assert(size_of(rawptr) == size_of(u32), "rawptr is not the same size as u32")
	data, ok := runtime.mem_alloc_bytes(size)
	ptrToAlocatedPtr^ = raw_data(data)
}