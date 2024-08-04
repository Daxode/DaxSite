const mem = new WebAssembly.Memory({ initial: 256, maximum: 65536, shared: false });
const memInterface = new odin.WasmMemoryInterface();
memInterface.setMemory(mem);
const wgpuInterface = new odin.WebGPUInterface(memInterface);

odin.runWasm("wasm-src.wasm", null, { wgpu: wgpuInterface.getInterface(),
    dax_dom: {
        fetch: function(urlPtr, urlLen, promiseWithIntResposePtr) {
            var url = memInterface.loadString(urlPtr, urlLen);
            const malloc = memInterface.exports.malloc;
            fetch(url).then(response => response.arrayBuffer()).then((buffer) => {
                malloc(buffer.byteLength, promiseWithIntResposePtr+1);
                const ptrToMem = memInterface.loadUint(promiseWithIntResposePtr+1);
                memInterface.loadBytes(ptrToMem, buffer.byteLength).set(new Uint8Array(buffer));
                memInterface.storeU8(promiseWithIntResposePtr, 1);
                memInterface.storeUint(promiseWithIntResposePtr+1+4, buffer.byteLength);
            });
            return promiseWithIntResposePtr;
        }
    }
}, memInterface, /*intSize=8*/).then(() => {
    console.log("odin_exports", memInterface.exports);
});