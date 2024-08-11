package js_ext

foreign import dom_lib "odin_dom"
foreign import dax_lib "dax_dom"

get_current_url :: proc "contextless" (buf: []byte) -> string {
	@(default_calling_convention="contextless")
	foreign dom_lib {
		@(link_name="get_current_url")
		_get_current_url :: proc(buf: []byte) -> int ---
	}
	n := _get_current_url(buf)
	return string(buf[:n])
}

fetch_promise_raw :: struct #packed {
	is_done: u8, 
	buffer: [^]byte,
	buffer_length: u32
}

fetch :: proc (url: string) -> (promise: ^fetch_promise_raw) {
	@(default_calling_convention="contextless")
	foreign dax_lib {
		@(link_name="fetch")
		_fetch :: proc(url: string, promise_ptr: ^fetch_promise_raw) ---
	}
	promise = new(fetch_promise_raw)
	_fetch(url, promise)
	return promise
}

fetch_free :: proc (promise: ^fetch_promise_raw) {
	if promise.buffer != nil {
		free(promise.buffer)
	}
	free(promise)
}

clipboard_promise_raw :: struct #packed {
	is_done: b8,
	buffer: cstring
}

getClipboardText :: proc () -> (promise: ^clipboard_promise_raw) {
	@(default_calling_convention="contextless")
	foreign dax_lib {
		@(link_name="getClipboardText")
		_getClipboardText :: proc(promise_ptr: ^clipboard_promise_raw) ---
	}
	promise = new(clipboard_promise_raw)
	_getClipboardText(promise)
	return promise
}

getClipboardText_update :: proc (promise: ^clipboard_promise_raw) {
	@(default_calling_convention="contextless")
	foreign dax_lib {
		@(link_name="getClipboardText")
		_getClipboardText :: proc(promise_ptr: ^clipboard_promise_raw) ---
	}
	_getClipboardText(promise)
}

getClipboardText_free :: proc (promise: ^clipboard_promise_raw) {
	if transmute(rawptr)promise.buffer != nil {
		free(transmute(rawptr)promise.buffer)
	}
	free(promise)
}


copyToClipboard :: proc (text: string) {
	@(default_calling_convention="contextless")
	foreign dax_lib {
		@(link_name="copyToClipboard")
		_copyToClipboard :: proc(text: string) ---
	}
	_copyToClipboard(text)
}

@(default_calling_convention="contextless")
foreign dom_lib {
	set_element_text_string :: proc(id: string, value: string) ---
}