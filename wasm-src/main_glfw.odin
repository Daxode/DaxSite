//+build !js
package main

import "core:time"

import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"
import "core:fmt"

import "vendor:microui"
import "core:strings"
import "base:runtime"

OS :: struct {
	window: glfw.WindowHandle,
    input: InputState,
    uiCtx: ^microui.Context,
    ctx: ^runtime.Context,
    buf: [1024]u8,
    currentBufSize: int,
}

os_init :: proc(os: ^OS, ctx: ^runtime.Context) {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}
    os.ctx = ctx
    
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	os.window = glfw.CreateWindow(960, 540, "WGPU Native Triangle", nil, nil)
    glfw.SetWindowUserPointer(os.window, os)
    glfw.SetKeyCallback(os.window, proc "c" (window: glfw.WindowHandle, key: i32, scancode: i32, action: i32, mods: i32) {
        if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
            glfw.SetWindowShouldClose(window, true)
        }
    })

	glfw.SetFramebufferSizeCallback(os.window, size_callback)
}

os_run :: proc(os: ^OS) {
    dt: f32

	for !glfw.WindowShouldClose(os.window) {
		start := time.tick_now()
        os.currentBufSize = 0

		glfw.PollEvents()

        // arrow keys change the camera position
        if glfw.GetKey(os.window, glfw.KEY_UP) == glfw.PRESS {
            os.input.pos.y += 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_DOWN) == glfw.PRESS {
            os.input.pos.y -= 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_LEFT) == glfw.PRESS {
            os.input.pos.x += 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_RIGHT) == glfw.PRESS {
            os.input.pos.x -= 0.1
        }
        
        // wasd keys change the camera target
        if glfw.GetKey(os.window, glfw.KEY_W) == glfw.PRESS {
            os.input.cam_pos.y -= 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_S) == glfw.PRESS {
            os.input.cam_pos.y += 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_A) == glfw.PRESS {
            os.input.cam_pos.x -= 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_D) == glfw.PRESS {
            os.input.cam_pos.x += 0.1
        }

        // q and e keys change the camera target z
        if glfw.GetKey(os.window, glfw.KEY_Q) == glfw.PRESS {
            os.input.cam_pos.z += 0.1
        }
        if glfw.GetKey(os.window, glfw.KEY_E) == glfw.PRESS {
            os.input.cam_pos.z -= 0.1
        }

        // r and f keys change the clicked value
        if glfw.GetKey(os.window, glfw.KEY_R) == glfw.PRESS {
            os.input.clicked += 0.1
            os.input.clicked = clamp(os.input.clicked, 0, 1)
        }
        if glfw.GetKey(os.window, glfw.KEY_F) == glfw.PRESS {
            os.input.clicked -= 0.1
            os.input.clicked = clamp(os.input.clicked, 0, 1)
        }

        if (os.uiCtx != nil) {
            frame_microui(os, os.uiCtx)
        }
		frame(dt)

		dt = f32(time.duration_seconds(time.tick_since(start)))
	}

	finish()

	glfw.DestroyWindow(os.window)
	glfw.Terminate()
}

os_get_render_bounds :: proc(os: ^OS) -> (width, height: u32) {
	iw, ih := glfw.GetWindowSize(os.window)
	return u32(iw), u32(ih)
}

os_get_surface :: proc(os: ^OS, instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, os.window)
}

@(private="file")
size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	resize()
}

@(private="file")
GLFW_KEY_TO_MICROUI_KEY := map[i32]microui.Key {
    glfw.KEY_LEFT_SHIFT = microui.Key.SHIFT,
    glfw.KEY_RIGHT_SHIFT =  microui.Key.SHIFT,
    glfw.KEY_LEFT_CONTROL = microui.Key.CTRL,
    glfw.KEY_RIGHT_CONTROL = microui.Key.CTRL,
    glfw.KEY_LEFT_ALT = microui.Key.ALT,
    glfw.KEY_RIGHT_ALT = microui.Key.ALT,
    glfw.KEY_BACKSPACE = microui.Key.BACKSPACE,
    glfw.KEY_DELETE = microui.Key.DELETE,
    glfw.KEY_ENTER = microui.Key.RETURN,
    glfw.KEY_LEFT = microui.Key.LEFT,
    glfw.KEY_RIGHT = microui.Key.RIGHT,
    glfw.KEY_HOME = microui.Key.HOME,
    glfw.KEY_END = microui.Key.END,
    glfw.KEY_A = microui.Key.A,
    glfw.KEY_X = microui.Key.X,
    glfw.KEY_C = microui.Key.C,
    glfw.KEY_V = microui.Key.V,
}


impl_microui :: proc(os: ^OS, uiCtx: ^microui.Context) {
    microui.init(uiCtx, 
        set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
            os := transmute(^OS)user_data
			cstr := strings.clone_to_cstring(text)
			glfw.SetClipboardString(os.window, cstr)
			delete(cstr)
			return true
		},
		get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
            os := transmute(^OS)user_data
            text = glfw.GetClipboardString(os.window)
			ok = true
			return
		},
        clipboard_user_data = os
    )
    os.uiCtx = uiCtx

    glfw.SetMouseButtonCallback(os.window, proc "c" (window: glfw.WindowHandle, button: i32, action: i32, mods: i32) {
        os := transmute(^OS)glfw.GetWindowUserPointer(window)
        context = os.ctx^
        mouse_pos_x_raw, mouse_pos_y_raw := glfw.GetCursorPos(os.window)
        mouse_pos_x, mouse_pos_y := i32(mouse_pos_x_raw), i32(mouse_pos_y_raw)

        if action == glfw.PRESS {
            if button == glfw.MOUSE_BUTTON_LEFT {
                microui.input_mouse_down(os.uiCtx, mouse_pos_x, mouse_pos_y, .LEFT)
            }
            if button == glfw.MOUSE_BUTTON_RIGHT {
                microui.input_mouse_down(os.uiCtx, mouse_pos_x, mouse_pos_y, .RIGHT)
            }
            if button == glfw.MOUSE_BUTTON_MIDDLE {
                microui.input_mouse_down(os.uiCtx, mouse_pos_x, mouse_pos_y, .MIDDLE)
            }
        } else if action == glfw.RELEASE {
            if button == glfw.MOUSE_BUTTON_LEFT {
                microui.input_mouse_up(os.uiCtx, mouse_pos_x, mouse_pos_y, .LEFT)
            }
            if button == glfw.MOUSE_BUTTON_RIGHT {
                microui.input_mouse_up(os.uiCtx, mouse_pos_x, mouse_pos_y, .RIGHT)
            }
            if button == glfw.MOUSE_BUTTON_MIDDLE {
                microui.input_mouse_up(os.uiCtx, mouse_pos_x, mouse_pos_y, .MIDDLE)
            }
        }
    })

    glfw.SetCharCallback(os.window, proc "c" (window: glfw.WindowHandle, codepoint: rune) {
        os := transmute(^OS)glfw.GetWindowUserPointer(window)
        context = os.ctx^
        os.buf[os.currentBufSize] = u8(codepoint)
        os.currentBufSize += 1
    })

    glfw.SetKeyCallback(os.window, proc "c" (window: glfw.WindowHandle, key: i32, scancode: i32, action: i32, mods: i32) {
        os := transmute(^OS)glfw.GetWindowUserPointer(window)
        context = os.ctx^
        if action == glfw.PRESS || action == glfw.REPEAT {
            if code, code_ok := GLFW_KEY_TO_MICROUI_KEY[key]; code_ok {
                microui.input_key_down(os.uiCtx, code)
            }
        } else if action == glfw.RELEASE {
            if code, code_ok := GLFW_KEY_TO_MICROUI_KEY[key]; code_ok {
                microui.input_key_up(os.uiCtx, code)
            }
        }
    })

    glfw.SetScrollCallback(os.window, proc "c" (window: glfw.WindowHandle, xoff, yoff: f64) {
        os := transmute(^OS)glfw.GetWindowUserPointer(window)
        context = os.ctx^
        microui.input_scroll(os.uiCtx, i32(xoff*30), i32(-yoff*30))
    })
}

frame_microui :: proc(os: ^OS, uiCtx: ^microui.Context) {
    mouse_pos_x_raw, mouse_pos_y_raw := glfw.GetCursorPos(os.window)
    mouse_pos_x, mouse_pos_y := i32(mouse_pos_x_raw), i32(mouse_pos_y_raw)
    microui.input_mouse_move(uiCtx, mouse_pos_x, mouse_pos_y)
    microui.input_text(uiCtx, string(os.buf[:os.currentBufSize]))
}