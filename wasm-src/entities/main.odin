package entities

CreateEntityStore :: proc() -> ^EntityStore {
    chunks := make([dynamic]ChunkData, 1)
    entityStore := new(EntityStore)
    entityStore^ = {
        entitySet = EntitySet{
            entities = make([dynamic]EntityId),
            freeList = make([dynamic]u32),
            entityInChunk = make([dynamic]ChunkIndex),
            entityInChunkIndex = make([dynamic]u8),
        },
        archetypes = make([dynamic]Archetype),
        chunks = chunks,
    }
    chunks[0] = ChunkData {
        data= make([dynamic]u8, 128)[:],
        entityCount= 0,
        archetype= &entityStore.nullArchetype,
    }
    return entityStore
}

DeleteEntityStore :: proc(store: ^EntityStore) {
    // Delete all the chunks
    for &chunk, i in store.chunks {
        delete(chunk.data)
    }
    delete(store.chunks)
    delete(store.freeChunk)
    
    // Delete all the archetypes
    for &archetype in store.archetypes {
        delete(archetype.chunkData)
        delete(archetype.componentTypeToOffsetForRandom)
        delete(archetype.componentTypes)
    }
    delete(store.archetypes)

    // Delete the entity set
    delete(store.entitySet.entities)
    delete(store.entitySet.freeList)
    delete(store.entitySet.entityInChunk)
    delete(store.entitySet.entityInChunkIndex)

    // Delete the store
    free(store)
}

// This function finds all entities that have the given components
// and is very slow. It is not recommended to use this function in
// performance critical code.
// This function is useful for debugging and testing.
// Ideally, you should use a query system to find entities with
// specific components.
//
// A query system is a system that keeps track of entities with specific components
// and updates the list of entities when a component is added or removed.
// This way, the query system can quickly return the list of entities with
// specific components.
FindEntitiesWithComponents :: proc(store: ^EntityStore, componentTypes: []typeid) -> []EntityId {
    for archetype, i in store.archetypes {
        if len(archetype.componentTypes) != len(componentTypes) {
            continue
        }
        match := true
        for componentType, j in componentTypes {
            if componentType != archetype.componentTypes[j] {
                match = false
                break
            }
        }
        if match {
            result := make([dynamic]EntityId)
            for chunkIndex in archetype.chunkData {
                chunk := &store.chunks[chunkIndex]
                for i in 0..<chunk.entityCount {
                    append(&result, chunk.entityIds[i])
                }
            }
            return result[:]
        }
    }
    return nil
}

SetComponentData :: proc(store: ^EntityStore, entity: EntityId, data: ^$componentType) {
    component := GetComponentDataRW(store, entity, componentType)
    component^ = data^
}

GetComponentData :: proc(store: ^EntityStore, entity: EntityId, $componentType: typeid) -> componentType {
    return GetComponentDataRW(store, entity, componentType)^
}

GetComponentDataRW :: proc(store: ^EntityStore, entity: EntityId, $componentType: typeid) -> ^componentType {
    chunkIndex := store.entitySet.entityInChunk[entity.index]
    indexInChunk := store.entitySet.entityInChunkIndex[entity.index]
    archetype := store.chunks[chunkIndex].archetype
    offset := archetype.componentTypeToOffsetForRandom[componentType]
    return transmute(^componentType) &store.chunks[chunkIndex].data[u16(indexInChunk)*u16(size_of(componentType)) + offset]
}

AddEntityWithComponents :: proc(store: ^EntityStore, componentTypes: []typeid) -> EntityId {
    archetype := GetOrCreateArchetype(store, componentTypes)
    entity := AddEntityId(&store.entitySet)
    AddChunkToEntityId(store, entity, archetype)
    return entity
}

GetOrCreateArchetype :: proc(store: ^EntityStore, componentTypes: []typeid) -> ^Archetype {
    for archetype, i in store.archetypes {
        if len(archetype.componentTypes) != len(componentTypes) {
            continue
        }
        match := true
        for componentType, j in componentTypes {
            if componentType != archetype.componentTypes[j] {
                match = false
                break
            }
        }
        if match {
            return &store.archetypes[i]
        }
    }

    componentTypesToStore := make([]typeid, len(componentTypes))
    copy(componentTypesToStore, componentTypes)
    archetype := Archetype{
        componentTypes=componentTypesToStore,
        chunkData = make([dynamic]ChunkIndex),
        componentTypeToOffsetForRandom = make(map[typeid]u16),
    }
    for componentType, i in componentTypes {
        size := u16(size_of(componentType))
        archetype.componentTypeToOffsetForRandom[componentType] = u16(archetype.sizePerEntity * 128)
        archetype.sizePerEntity += size
    }
    append(&store.archetypes, archetype)
    return &store.archetypes[len(store.archetypes) - 1]
}

StealFreeChunkSlotInArchetype :: proc(store: ^EntityStore, archetype: ^Archetype) -> (ChunkIndex, u8) {
    for chunkIndex, i in archetype.chunkData {
        if store.chunks[chunkIndex].entityCount < 128 {
            return chunkIndex, store.chunks[chunkIndex].entityCount
        }
    }

    if len(store.freeChunk) > 0 {
        chunkIndex := store.freeChunk[len(store.freeChunk) - 1]
        unordered_remove(&store.freeChunk, len(store.freeChunk) - 1)
        return chunkIndex, 0
    }

    chunkIndex := u32(len(store.chunks))
    append(&store.chunks, ChunkData{
        data= make([dynamic]u8, archetype.sizePerEntity * 128)[:],
        entityCount= 0,
        archetype= archetype,
    })
    append(&archetype.chunkData, chunkIndex)
    return chunkIndex, 0
}

AddChunkToEntityId :: proc(store: ^EntityStore, entity: EntityId, archetype: ^Archetype) {
    chunkIndex, indexInChunk := StealFreeChunkSlotInArchetype(store, archetype)
    store.entitySet.entityInChunk[entity.index] = chunkIndex
    store.entitySet.entityInChunkIndex[entity.index] = indexInChunk
    store.chunks[chunkIndex].entityCount += 1
    store.chunks[chunkIndex].entityIds[indexInChunk] = entity
}

RemoveEntityWithComponents :: proc(store: ^EntityStore, entity: EntityId) {
    RemoveChunkDataFromEntityId(store, entity)
    RemoveEntityId(&store.entitySet, entity)
}

RemoveChunkDataFromEntityId :: proc(store: ^EntityStore, entity: EntityId) {
    if !EntityIdExists(&store.entitySet, entity) {
        return
    }
    if !EntityHasChunkData(store, entity) {
        return
    }

    chunkIndex := store.entitySet.entityInChunk[entity.index]
    indexInChunk := store.entitySet.entityInChunkIndex[entity.index]
    chunk := &store.chunks[chunkIndex];
    chunk.entityCount -= 1

    // Move data from the last entity in the chunk to the removed entity
    if chunk.entityCount > 0 && indexInChunk != chunk.entityCount {
        lastEntityId := chunk.entityIds[chunk.entityCount]
        lastEntityIndexInChunk := store.entitySet.entityInChunkIndex[lastEntityId.index]
        lastEntityChunkIndex := store.entitySet.entityInChunk[lastEntityId.index]
        archetype := chunk.archetype
        runningComponentOffset := u16(0)
        for componentType, i in archetype.componentTypes {
            currentOffset := u16(indexInChunk) * size_of(componentType) + runningComponentOffset
            lastOffset := u16(lastEntityChunkIndex) * size_of(componentType) + runningComponentOffset
            copy(chunk.data[currentOffset:currentOffset+size_of(componentType)], chunk.data[lastOffset:lastOffset+size_of(componentType)])
            runningComponentOffset += size_of(componentType) * 128
        }
        store.entitySet.entityInChunkIndex[lastEntityId.index] = indexInChunk
        store.entitySet.entityInChunk[lastEntityId.index] = chunkIndex
    }

    // Remove the chunk if there are no more entities
    if chunk.entityCount == 0 {
        archetypeForChunk := chunk.archetype
        chunksForArchetype := &archetypeForChunk.chunkData
        // Remove the chunk from the archetype
        for chunkIndexInArchetype, i in chunksForArchetype {
            if chunkIndexInArchetype == chunkIndex {
                unordered_remove(chunksForArchetype, i)
                break
            }
        }

        // Remove the chunk from the store
        append(&store.freeChunk, chunkIndex)

        // Remove the archetype if there are no more chunks
        if len(chunksForArchetype) == 0 {
            indexToRemove := -1
            for &archetype, i in store.archetypes {
                if &archetype == archetypeForChunk {
                    delete(archetype.chunkData)
                    delete(archetype.componentTypeToOffsetForRandom)
                    delete(archetype.componentTypes)
                    indexToRemove = i
                    break
                }
            }
            if indexToRemove != -1 {
                unordered_remove(&store.archetypes, indexToRemove)
            }
        }
    }

    // Remove the entity from the entity set
    store.entitySet.entityInChunk[entity.index] = 0
    store.entitySet.entityInChunkIndex[entity.index] = 0
}

EntityHasChunkData :: proc(store: ^EntityStore, entity: EntityId) -> bool {
    return store.entitySet.entityInChunk[entity.index] != 0
}

EntityIdExists :: proc(set: ^EntitySet, entity: EntityId) -> bool {
    if entity.index >= u32(len(set.entities)) {
        return false
    }
    if set.entities[entity.index].version != entity.version {
        return false
    }
    return true
}

AddEntityId :: proc(set: ^EntitySet) -> EntityId {
    if len(set.freeList) > 0 {
        index := set.freeList[len(set.freeList) - 1]
        unordered_remove(&set.freeList, len(set.freeList) - 1)
        return EntityId{index=index, version=set.entities[index].version}
    }
    index := u32(len(set.entities))
    append(&set.entities, EntityId{index=index, version=1})
    append(&set.entityInChunk, 0)
    append(&set.entityInChunkIndex, 0)
    return EntityId{index= index, version=1}
}

RemoveEntityId :: proc(set: ^EntitySet, entity: EntityId) {
    set.entities[entity.index].version += 1
    append(&set.freeList, entity.index)

    // Assert that the entity is not in a chunk
    assert(set.entityInChunk[entity.index] == 0, "Entity is in a chunk (has chunk index)")
    assert(set.entityInChunkIndex[entity.index] == 0, "Entity is in a chunk (has index in chunk)")
}