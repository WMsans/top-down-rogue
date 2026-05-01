#include "register_types.h"

#include "sim/material_table.h"
#include "sim/simulator.h"

#include "resources/biome_def.h"
#include "resources/pool_def.h"
#include "resources/room_template.h"
#include "resources/template_pack.h"
#include "resources/terrain_cell.h"

#include "generation/generator.h"
#include "generation/simplex_cave_generator.h"

#include "physics/collider_builder.h"
#include "physics/gas_injector.h"
#include "physics/terrain_collider.h"
#include "terrain/chunk.h"
#include "terrain/generation_context.h"
#include "terrain/sector_grid.h"
#include "terrain/terrain_collision_helper.h"
#include "terrain/terrain_modifier.h"
#include "terrain/terrain_physical.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;
using namespace toprogue;

static MaterialTable *g_material_table = nullptr;

void initialize_toprogue_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_CLASS(MaterialDef);
	GDREGISTER_CLASS(MaterialTable);

	// Resources — register dependencies before dependents:
	// BiomeDef references PoolDef and RoomTemplate; TemplatePack references RoomTemplate.
	GDREGISTER_CLASS(TerrainCell);
	GDREGISTER_CLASS(PoolDef);
	GDREGISTER_CLASS(RoomTemplate);
	GDREGISTER_CLASS(BiomeDef);
	GDREGISTER_CLASS(TemplatePack);

	// Leaf types — register dependencies before dependents.
	// SectorGrid takes a Ref<BiomeDef>; BiomeDef must already be registered (it is, above).
	GDREGISTER_CLASS(GenerationContext);
	GDREGISTER_CLASS(Chunk);
	GDREGISTER_CLASS(RoomSlot); // Inner type of SectorGrid; register before SectorGrid.
	GDREGISTER_CLASS(SectorGrid);

	// Collider + physics — register before TerrainCollisionHelper, which calls them.
	GDREGISTER_CLASS(ColliderBuilder);
	GDREGISTER_CLASS(TerrainCollider);
	GDREGISTER_CLASS(GasInjector);
	GDREGISTER_CLASS(TerrainCollisionHelper);
	GDREGISTER_CLASS(TerrainModifier);
	GDREGISTER_CLASS(TerrainPhysical);

	// Generation
	GDREGISTER_CLASS(Generator);
	GDREGISTER_CLASS(SimplexCaveGenerator);

	// Simulation
	GDREGISTER_CLASS(Simulator);

	g_material_table = memnew(MaterialTable);
	Engine::get_singleton()->register_singleton("MaterialTable", g_material_table);
}

void uninitialize_toprogue_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	Engine::get_singleton()->unregister_singleton("MaterialTable");
	if (g_material_table) {
		memdelete(g_material_table);
		g_material_table = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT toprogue_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_toprogue_module);
	init_obj.register_terminator(uninitialize_toprogue_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
