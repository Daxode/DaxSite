Build:
	odin build ./wasm-src -target="js_wasm32" -extra-linker-flags:"--export-table --import-memory --max-memory=4294967296"

Run:
	python -m http.server

BuildClientVersion:
	odin build ./wasm-src -out:client.exe -target="windows_amd64" -o:none -debug -resource:resources.rc

RunClientVersion:
	./client.exe