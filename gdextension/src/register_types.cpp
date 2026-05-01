#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sim/material_table.h"

using namespace godot;

static MaterialTable *s_material_table = nullptr;

void initialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // Register MaterialTable first — every later class may reference material IDs.
    ClassDB::register_class<MaterialTable>();
    s_material_table = memnew(MaterialTable);
    Engine::get_singleton()->register_singleton("MaterialTable", s_material_table);

    // Step 3+ will register Resource subclasses, Chunk, Simulator, etc. here.
}

void uninitialize_toprogue_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    if (s_material_table) {
        Engine::get_singleton()->unregister_singleton("MaterialTable");
        memdelete(s_material_table);
        s_material_table = nullptr;
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
