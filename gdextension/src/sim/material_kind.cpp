#include "material_kind.h"
#include "material_table.h"

namespace toprogue {

static MaterialKindTable g_table = {};

const MaterialKindTable &material_kind_table() { return g_table; }

void rebuild_material_kind_table() {
	for (int i = 0; i < 256; i++) g_table.kind[i] = KIND_INERT;
	MaterialTable *mt = MaterialTable::get_singleton();
	if (!mt) return;
	g_table.kind[mt->get_MAT_LAVA()] = KIND_LAVA;
	g_table.kind[mt->get_MAT_GAS()] = KIND_GAS;
}

} // namespace toprogue
