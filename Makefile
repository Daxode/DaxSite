Build:
	odin build ./wasm-src -target="js_wasm32" -extra-linker-flags:"--export-table --import-memory --initial-memory=131072000 --max-memory=4294967296"

Run:
	python -m http.server