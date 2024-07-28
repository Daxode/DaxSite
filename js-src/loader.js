const mem = new WebAssembly.Memory({ initial: 2000, maximum: 65536, shared: false });
const memInterface = new odin.WasmMemoryInterface();
memInterface.setMemory(mem);
const wgpuInterface = new odin.WebGPUInterface(memInterface);
odin.runWasm("wasm-src.wasm", null, { wgpu: wgpuInterface.getInterface() }, memInterface, /*intSize=8*/);