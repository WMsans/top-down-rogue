#pragma once

#include "../resources/biome_def.h"
#include "../resources/room_template.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace toprogue {

// Mirrors src/core/sector_grid.gd's nested `RoomSlot` 1:1.
// Promoted to a top-level RefCounted class so GDScript callsites that
// receive a `RoomSlot` and read its fields keep working unchanged.
class RoomSlot : public godot::RefCounted {
    GDCLASS(RoomSlot, godot::RefCounted);

public:
    bool is_empty       = false;
    bool is_boss        = false;
    int  template_index = -1;
    int  rotation       = 0;
    int  template_size  = 0;

    RoomSlot() = default;

    bool get_is_empty() const       { return is_empty; }
    void set_is_empty(bool v)       { is_empty = v; }
    bool get_is_boss() const        { return is_boss; }
    void set_is_boss(bool v)        { is_boss = v; }
    int  get_template_index() const { return template_index; }
    void set_template_index(int v)  { template_index = v; }
    int  get_rotation() const       { return rotation; }
    void set_rotation(int v)        { rotation = v; }
    int  get_template_size() const  { return template_size; }
    void set_template_size(int v)   { template_size = v; }

protected:
    static void _bind_methods();
};

class SectorGrid : public godot::RefCounted {
    GDCLASS(SectorGrid, godot::RefCounted);

public:
    static constexpr int    SECTOR_SIZE_PX     = 384;
    static constexpr int    BOSS_RING_DISTANCE = 10;
    static constexpr double EMPTY_WEIGHT       = 1.5;

    int64_t              _seed = 0;
    godot::Ref<BiomeDef> _biome;

    SectorGrid() = default;

    // GDScript-callable shim for `SectorGrid.new(world_seed, biome)`.
    // godot-cpp can't bind `_init` with arguments; same shim approach used
    // for `TerrainCell.init_args` in step 3. Callsites in
    // `src/autoload/level_manager.gd` are migrated in Task 5 step 1.
    void init_args(int64_t world_seed, const godot::Ref<BiomeDef> &biome);

    godot::Vector2i world_to_sector(const godot::Vector2 &world_pos) const;
    godot::Vector2i sector_to_world_center(const godot::Vector2i &coord) const;
    int             chebyshev_distance(const godot::Vector2i &a, const godot::Vector2i &b) const;
    godot::Ref<RoomSlot> resolve_sector(const godot::Vector2i &coord) const;
    godot::Ref<RoomTemplate> get_template_for_slot(const godot::Ref<RoomSlot> &slot) const;

    static int    get_sector_size_px()     { return SECTOR_SIZE_PX; }
    static int    get_boss_ring_distance() { return BOSS_RING_DISTANCE; }
    static double get_empty_weight()       { return EMPTY_WEIGHT; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
