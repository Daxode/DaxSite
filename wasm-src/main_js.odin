package main

import "vendor:wasm/js"
import "js_ext"
import "base:runtime"
import "core:fmt"
import "core:strconv"
import "vendor:wgpu"

import "vendor:microui"

OS :: struct {
    initialized: bool,
    input: InputState,
    ctx: ^runtime.Context,
    uiCtx: ^microui.Context,

    mouse_left_pressed: bool,
    mouse_right_pressed: bool,
    mouse_middle_pressed: bool,

    buf: [1024]u8,
    currentBufSize: int,
}

@(private="file")
g_os: ^OS

os_init :: proc(os: ^OS, ctx: ^runtime.Context) {
    g_os = os
    g_os.ctx = ctx
    context = ctx^

    assert(js.add_window_event_listener(.Resize, nil, size_callback))
    // assert(js.add_event_listener("start", .Click, os, start_callback))
    // assert(js.add_event_listener("stop", .Click, os, stop_callback))

    // js.add_window_event_listener(.Pointer_Move, nil, proc(e: js.Event) {
    //     if (0 in e.mouse.buttons)
    //     {
    //         g_os.input.clicked += f64(e.mouse.movement.x)/200
    //         g_os.input.clicked = clamp(g_os.input.clicked, 0, 1)
    //         js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", g_os.input.clicked))
    //     }
    // })

    // js.add_custom_event_listener("pos-x", "input", nil, proc(e: js.Event) {
    //     data : [256]byte;
    //     g_os.input.pos.x = f32(strconv.atof(js.get_element_value_string("pos-x", data[:])))
    // })

    // js.add_custom_event_listener("pos-y", "input", nil, proc(e: js.Event) {
    //     data : [256]byte;
    //     g_os.input.pos.y = f32(strconv.atof(js.get_element_value_string("pos-y", data[:])))
    // })

    // js.add_custom_event_listener("pos-z", "input", nil, proc(e: js.Event) {
    //     data : [256]byte;
    //     g_os.input.pos.z = f32(strconv.atof(js.get_element_value_string("pos-z", data[:])))
    // })

    // js.add_custom_event_listener("cam-x", "input", nil, proc(e: js.Event) {
    //     data : [256]byte;
    //     g_os.input.cam_pos.x = f32(strconv.atof(js.get_element_value_string("cam-x", data[:])))
    // })

    // js.add_custom_event_listener("cam-y", "input", nil, proc(e: js.Event) {
    //     data : [256]byte;
    //     g_os.input.cam_pos.y = f32(strconv.atof(js.get_element_value_string("cam-y", data[:])))
    // })

    // js.add_custom_event_listener("cam-z", "input", nil, proc(e: js.Event) {
    //     data : [256]byte;
    //     g_os.input.cam_pos.z = f32(strconv.atof(js.get_element_value_string("cam-z", data[:])))
    // })


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

    if (g_os.uiCtx != nil) {
        frame_microui(g_os, g_os.uiCtx)
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
    g_os.input.clicked += 0.1
    g_os.input.clicked = clamp(g_os.input.clicked, 0, 1)
    js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", g_os.input.clicked))
}

stop_callback :: proc(e: js.Event) {
    g_os.input.clicked = 0
    js_ext.set_element_text_string("start", fmt.aprintf("Increment: %.2f", g_os.input.clicked))
}

@(export)
malloc :: proc "contextless" (size: int, ptrToAlocatedPtr: ^rawptr) {
    context = g_os.ctx^
	assert(size_of(rawptr) == size_of(u32), "rawptr is not the same size as u32")
	data, ok := runtime.mem_alloc_bytes(size)
	ptrToAlocatedPtr^ = raw_data(data)
}

// @(private="file")
JS_KEY_TO_MICROUI_KEY := map[string]microui.Key {
    "Shift" = microui.Key.SHIFT,
    "Control" = microui.Key.CTRL,
    "Alt" = microui.Key.ALT,
    "Backspace" = microui.Key.BACKSPACE,
    "Delete" = microui.Key.DELETE,
    "Enter" = microui.Key.RETURN,
    "ArrowLeft" = microui.Key.LEFT,
    "ArrowRight" = microui.Key.RIGHT,
    "Home" = microui.Key.HOME,
    "End" = microui.Key.END,
    "a" = microui.Key.A,
    "A" = microui.Key.A,
    "x" = microui.Key.X,
    "X" = microui.Key.X,
    "c" = microui.Key.C,
    "C" = microui.Key.C,
    "v" = microui.Key.V,
    "V" = microui.Key.V,
}

impl_microui :: proc(os: ^OS, uiCtx: ^microui.Context) {
    microui.init(uiCtx, 
        set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
            os := transmute(^OS)user_data
            js_ext.copyToClipboard(text)
			return true
		},
		get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
            os := transmute(^OS)user_data
            text = string(clipboardText.buffer)
			ok = true
			return
		},
        clipboard_user_data = os
    )
    os.uiCtx = uiCtx
    js.add_window_event_listener(.Pointer_Down, nil, proc(e: js.Event) {
        if 0 in e.mouse.buttons {
            microui.input_mouse_down(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y), .LEFT)
        }
        if 1 in e.mouse.buttons {
            microui.input_mouse_down(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y), .RIGHT)
        }
        if 2 in e.mouse.buttons {
            microui.input_mouse_down(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y), .MIDDLE)
        }
    })

    js.add_window_event_listener(.Pointer_Up, nil, proc(e: js.Event) {
        
        if 0 not_in e.mouse.buttons {
            microui.input_mouse_up(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y), .LEFT)
        }
        if 1 not_in e.mouse.buttons {
            microui.input_mouse_up(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y), .RIGHT)
        }
        if 2 not_in e.mouse.buttons {
            microui.input_mouse_up(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y), .MIDDLE)
        }
    })

    js.add_window_event_listener(.Pointer_Move, nil, proc(e: js.Event) {
        microui.input_mouse_move(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y))
    })
    js.add_window_event_listener(.Touch_Move, nil, proc(e: js.Event) {
        microui.input_mouse_move(g_os.uiCtx, i32(e.mouse.client.x), i32(e.mouse.client.y))
        js.event_stop_immediate_propagation()
        js.event_prevent_default()
    })

    js.add_window_event_listener(.Key_Down, nil, proc(e: js.Event) {
        if key, ok := JS_KEY_TO_MICROUI_KEY[e.key.key]; ok {
            microui.input_key_down(g_os.uiCtx, key)
            // fmt.println("Key down:", e.key.key)
            if key == microui.Key.C || key == microui.Key.V || key == microui.Key.X || key == microui.Key.A {
                if microui.Key.CTRL in g_os.uiCtx.key_down_bits {
                    // if key == microui.Key.C {
                    //     fmt.println("Copy")
                    // } else if key == microui.Key.V {
                    //     fmt.println("Paste")
                    // } else if key == microui.Key.X {
                    //     fmt.println("Cut")
                    // } else if key == microui.Key.A {
                    //     fmt.println("Select All")
                    // }
                } else {
                    g_os.buf[g_os.currentBufSize] = u8(e.key.key[0])
                    g_os.currentBufSize += 1
                }
            }
        } else {
            // fmt.println("Key down:", e.key)
            if len(e.key.key) > 1 {
               return; 
            }

            g_os.buf[g_os.currentBufSize] = u8(e.key.key[0])
            g_os.currentBufSize += 1
        }
    })

    js.add_window_event_listener(.Key_Up, nil, proc(e: js.Event) {
        if key, ok := JS_KEY_TO_MICROUI_KEY[e.key.key]; ok {
            microui.input_key_up(g_os.uiCtx, key)
            // fmt.println("Key up:", e.key.key)
        }
    })
    js.add_event_listener("c", .Wheel, nil, proc(e: js.Event) {
        microui.input_scroll(g_os.uiCtx, i32(e.scroll.delta.x*0.1), i32(e.scroll.delta.y*0.1))
    })

    
}

clipboardText: ^js_ext.clipboard_promise_raw

frame_microui :: proc(os: ^OS, uiCtx: ^microui.Context) {
    microui.input_text(uiCtx, string(os.buf[:os.currentBufSize]))
    os.currentBufSize = 0

    if clipboardText == nil {
        clipboardText = js_ext.getClipboardText()
    } else {
        js_ext.getClipboardText_update(clipboardText)
    }
    // if clipboardText.is_done {
    //     fmt.println("Clipboard text:", clipboardText.buffer)
    // }
}