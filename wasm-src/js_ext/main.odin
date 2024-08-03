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

@(default_calling_convention="contextless")
foreign dom_lib {
	set_element_text_string :: proc(id: string, value: string) ---
}