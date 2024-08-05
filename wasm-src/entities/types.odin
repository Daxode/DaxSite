package entities

EntityId :: struct {
    index: u32,
    version: u32,
}

EntitySet :: struct {
    entities: [dynamic]EntityId,
    freeList: [dynamic]u32, // freeList is a stack of free entity indices
    entityInChunk: [dynamic]ChunkIndex, // entityInChunk is a map of entity index to chunk index
    entityInChunkIndex: [dynamic]u8, // entityInChunkIndex is a map of entity index to index in the chunk
}

// ChunkData is a chunk of data that is associated with a set of entities (128 entities per chunk)
ChunkData :: struct {
    data: []u8,
    entityCount: u8,
    archetype: ^Archetype,
    entityIds: [128]EntityId,
}

ChunkIndex :: u32

Archetype :: struct {
    chunkData: [dynamic]ChunkIndex,
    componentTypes: []typeid,
    componentTypeToOffsetForRandom: map[typeid]u16, // componentType is a map of component type to start index in the data array
    sizePerEntity: u16,
}

EntityStore :: struct {
    entitySet: EntitySet,
    archetypes: [dynamic]Archetype,
    chunks: [dynamic]ChunkData,
    freeChunk: [dynamic]ChunkIndex,
}