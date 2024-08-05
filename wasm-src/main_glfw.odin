//+build !js
package main

import "core:time"

import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"
import "core:fmt"

OS :: struct {
	window: glfw.WindowHandle,
    input: InputState,
}

os_init :: proc(os: ^OS) {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	os.window = glfw.CreateWindow(960, 540, "WGPU Native Triangle", nil, nil)
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
