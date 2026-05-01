#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/templates/vector.hpp>

namespace godot {

struct MaterialDef {
    int id = 0;
    String name;
    String texture_path;
    bool flammable = false;
    int ignition_temp = 0;
    int burn_health = 0;
    bool has_collider = false;
    bool has_wall_extension = false;
    Color tint_color;
    bool fluid = false;
    int damage = 0;
    float glow = 1.0f;
};

class MaterialTable : public Object {
    GDCLASS(MaterialTable, Object);

public:
    static const int MAT_AIR = 0;
    static const int MAT_WOOD = 1;
    static const int MAT_STONE = 2;
    static const int MAT_GAS = 3;
    static const int MAT_LAVA = 4;
    static const int MAT_DIRT = 5;
    static const int MAT_COAL = 6;
    static const int MAT_ICE = 7;
    static const int MAT_WATER = 8;
    static const int MAT_COUNT = 9;

    MaterialTable();
    ~MaterialTable();

    void populate();

    // C++ fast path (not called from GDScript)
    const MaterialDef &def(int p_id) const;

    // Bound to GDScript — match old MaterialRegistry API exactly.
    // Property getters.
    int get_MAT_AIR() const { return MAT_AIR; }
    int get_MAT_WOOD() const { return MAT_WOOD; }
    int get_MAT_STONE() const { return MAT_STONE; }
    int get_MAT_GAS() const { return MAT_GAS; }
    int get_MAT_LAVA() const { return MAT_LAVA; }
    int get_MAT_DIRT() const { return MAT_DIRT; }
    int get_MAT_COAL() const { return MAT_COAL; }
    int get_MAT_ICE() const { return MAT_ICE; }
    int get_MAT_WATER() const { return MAT_WATER; }

    // Method bindings — signatures match old MaterialRegistry API exactly.
    bool is_flammable(int p_material_id) const;
    int get_ignition_temp(int p_material_id) const;
    bool has_collider(int p_material_id) const;
    bool has_wall_extension(int p_material_id) const;
    Color get_tint_color(int p_material_id) const;
    Array get_fluids() const;
    bool is_fluid(int p_material_id) const;
    int get_damage(int p_material_id) const;
    float get_glow(int p_material_id) const;

    // Return all materials as an Array of Dictionary so GDScript iteration
    // patterns (for m in MaterialTable.materials) continue to work.
    Array get_materials() const;

    // Bounds-checked helper, used by all getters above.
    bool _valid_id(int p_id) const;

protected:
    static void _bind_methods();

private:
    Vector<MaterialDef> defs;
};

} // namespace godot
