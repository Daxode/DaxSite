package entities

import "core:testing"

ComponentA :: struct {
    value: u32,
}

ComponentB :: struct {
    value: f32,
}


@(test)
CheckEntityAdded :: proc(t: ^testing.T) {
    store := EntityStore{}
    defer DeleteEntityStore(&store)
    
    AddEntityWithComponents(&store, {ComponentA, ComponentB})
    testing.expect(t, len(store.entitySet.entities) == 1)
    testing.expect(t, len(store.archetypes) == 1)
    testing.expect(t, len(store.chunks) == 1)
    testing.expect(t, store.chunks[0].entityCount == 1)
    testing.expect(t, store.chunks[0].archetype.componentTypes[0] == ComponentA)
    testing.expect(t, store.chunks[0].archetype.componentTypes[1] == ComponentB)
}

@(test)
CheckRemovedEntity :: proc(t: ^testing.T) {
    store := EntityStore{}
    defer DeleteEntityStore(&store)

    entity := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    RemoveEntityWithComponents(&store, entity)
    testing.expect(t, len(store.entitySet.entities) == 1, "Expected 1 entity in entity set as removed entity is not removed from the set but is added in free list")
    testing.expect(t, len(store.archetypes) == 0, "Expected 0 archetypes in store")
    testing.expect(t, len(store.chunks) == 1, "Expected 1 chunk in store, as the chunk is not removed from the store, but is added in chunk free list")
    testing.expect(t, len(store.freeChunk) == 1, "Expected 1 chunk in free list")
    testing.expect(t, store.freeChunk[0] == 0, "Expected free chunk index to be for chunk 0, as that was the chunk that was 'removed'")
    testing.expect(t, len(store.entitySet.freeList)==1, "Expected 1 free entity in free list")
    testing.expect(t, store.entitySet.freeList[0] == 0, "Expected free entity index to be 0")
}

@(test)
CheckChunkIsReused :: proc(t: ^testing.T) {
    store := EntityStore{}
    defer DeleteEntityStore(&store)

    entity := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    RemoveEntityWithComponents(&store, entity)
    entity = AddEntityWithComponents(&store, {ComponentA, ComponentB})
    testing.expect(t, len(store.entitySet.entities) == 1, "Expected 1 entity in entity set as removed entity is not removed from the set but is added in free list")
    testing.expect(t, len(store.archetypes) == 1, "Expected 1 archetype in store")
    testing.expect(t, len(store.chunks) == 1, "Expected 1 chunk in store, as the chunk is not removed from the store, but is added in chunk free list")
    testing.expect(t, len(store.freeChunk) == 0, "Expected 0 chunks in free list")
    testing.expect(t, len(store.entitySet.freeList)==0, "Expected 0 free entity in free list")
}

@(test)
CheckComponentDataIsCorrect :: proc(t: ^testing.T) {
    store := EntityStore{}
    defer DeleteEntityStore(&store)

    entity := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    componentA := GetComponentData(&store, entity, ComponentA)
    componentB := GetComponentData(&store, entity, ComponentB)
    testing.expect(t, componentA.value == 0, "Expected component A value to be 0")
    testing.expect(t, componentB.value == 0, "Expected component B value to be 0")
    componentA.value = 10
    componentB.value = 20
    SetComponentData(&store, entity, &componentA)
    SetComponentData(&store, entity, &componentB)

    componentA = GetComponentData(&store, entity, ComponentA)
    componentB = GetComponentData(&store, entity, ComponentB)
    testing.expect(t, componentA.value == 10, "Expected component A value to be 10")
    testing.expect(t, componentB.value == 20, "Expected component B value to be 20")
}

@(test)
CheckFindEntities :: proc(t: ^testing.T) {
    store := EntityStore{}
    defer DeleteEntityStore(&store)

    entity1  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity2  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity3  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity4  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity5  := AddEntityWithComponents(&store, {ComponentA})
    entity6  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity7  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity8  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity9  := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity10 := AddEntityWithComponents(&store, {ComponentA})
    entity11 := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity12 := AddEntityWithComponents(&store, {ComponentA, ComponentB})
    entity13 := AddEntityWithComponents(&store, {ComponentB})

    entities := FindEntitiesWithComponents(&store, {ComponentA, ComponentB})
    defer delete(entities)
    testing.expect(t, len(entities) == 10, "Expected 10 entities with ComponentA and ComponentB")
}