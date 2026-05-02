#pragma once

#include <cstdint>

namespace toprogue {

enum SimMaterialKind : uint8_t {
	KIND_INERT = 0,
	KIND_LAVA = 1,
	KIND_GAS = 2,
	KIND_BURNING = 3,
};

struct MaterialKindTable {
	uint8_t kind[256];
};

const MaterialKindTable &material_kind_table();
void rebuild_material_kind_table();

} // namespace toprogue
