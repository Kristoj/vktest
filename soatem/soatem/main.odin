package soatem

import "core:fmt"
import "core:mem"
import "core:c"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:math/bits"

import rl "vendor:raylib"

shouldClose := false
NULL_ENTITY_HANDLE :: 0

Vec3 :: linalg.Vector3f32

EntityGroup :: struct($T: typeid)
{
	data:     #soa []T,
	count:    int,
	capacity: int,
	
	entityHandles: []EntityHandle,
	destroyBits:   []u128,
	typeHandle:    u8
}

Zombie :: struct
{
	position: Vec3,
	health:   i32,
}
zombies: EntityGroup(Zombie)

EntityHandle :: distinct u32
Entity :: bit_field(u64)
{
	index:      u32 | 32,
	version:    u32 | 32,
}
entities: [dynamic]Entity = {Entity{}}

entityTypes := [dynamic]typeid {
	Zombie,
	Chicken
}

Chicken :: struct
{
	position: Vec3,
	health:   i32,
}
chickens: EntityGroup(Chicken)

create_entity :: proc(group: EntityGroup($T))
{
	if group.count >= group.capacity - 1
	{
		fmt.panicf("Failed to create entity because groups entity count exceeded capacity.")
	}
	
	ent: Entity
	ent.index = group.count
	ent.version = 0
	append(&entities, ent)

	group.entityHandles[group.count] = EntityHandle(len(entities))
	group.count += 1
}

destroy_marked_entities :: proc()
{
	destroy_entity_group :: proc(group: ^EntityGroup($T))
	{
		for page in group.destroyBits
		{
			for page != 0
			{
				index := bits.count_leading_zeros(page)
				destroy_entity(group, u32(index))
			}
		}
	}

	destroy_entity_group(&zombies)
}

destroy_entity :: proc(group: ^EntityGroup($T), index: u32) 
{
	// Move data
	last := group.capacity - 1
	group.data[index] = group.data[last]

	entities[group.entityHandles[last]].index = index // Moved entity
	entities[group.entityHandles[index]].version += 1 // Removed entity
	group.entityHandles[index] = group.entityHandles[last]
	group.entityHandles[last] = NULL_ENTITY_HANDLE
}

tick_move_system :: proc()
{
	move_shit :: proc(pos: ^Vec3, target: ^Vec3)
	{
		
	}

	for &z in zombies.data
	{
		move_shit(&z.position, nil)
	}
}


//// ----------- Window shit

main :: proc()
{
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(800, 600, "Soatem")
	
	for !shouldClose
	{
		rl.PollInputEvents()
		process_input()
		rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK)
		rl.EndDrawing()
	}

	rl.CloseWindow()
}


process_input :: proc()
{
	if rl.IsKeyDown(.ESCAPE)
	{
		shouldClose = true
	}
}

