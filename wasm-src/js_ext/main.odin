package js_ext

foreign import dom_lib "odin_dom"

get_current_url :: proc "contextless" (buf: []byte) -> string {
	@(default_calling_convention="contextless")
	foreign dom_lib {
		@(link_name="get_current_url")
		_get_current_url :: proc(buf: []byte) -> int ---
	}
	n := _get_current_url(buf)
	return string(buf[:n])
}

@(default_calling_convention="contextless")
foreign dom_lib {
	set_element_text_string :: proc(id: string, value: string) ---
}