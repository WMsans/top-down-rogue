#include "biome_def.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void BiomeDef::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_display_name"), &BiomeDef::get_display_name);
    ClassDB::bind_method(D_METHOD("set_display_name", "v"), &BiomeDef::set_display_name);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "display_name"),
                 "set_display_name", "get_display_name");

    ClassDB::bind_method(D_METHOD("get_cave_noise_scale"), &BiomeDef::get_cave_noise_scale);
    ClassDB::bind_method(D_METHOD("set_cave_noise_scale", "v"), &BiomeDef::set_cave_noise_scale);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cave_noise_scale"),
                 "set_cave_noise_scale", "get_cave_noise_scale");

    ClassDB::bind_method(D_METHOD("get_cave_threshold"), &BiomeDef::get_cave_threshold);
    ClassDB::bind_method(D_METHOD("set_cave_threshold", "v"), &BiomeDef::set_cave_threshold);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cave_threshold"),
                 "set_cave_threshold", "get_cave_threshold");

    ClassDB::bind_method(D_METHOD("get_ridge_weight"), &BiomeDef::get_ridge_weight);
    ClassDB::bind_method(D_METHOD("set_ridge_weight", "v"), &BiomeDef::set_ridge_weight);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ridge_weight"),
                 "set_ridge_weight", "get_ridge_weight");

    ClassDB::bind_method(D_METHOD("get_ridge_scale"), &BiomeDef::get_ridge_scale);
    ClassDB::bind_method(D_METHOD("set_ridge_scale", "v"), &BiomeDef::set_ridge_scale);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ridge_scale"),
                 "set_ridge_scale", "get_ridge_scale");

    ClassDB::bind_method(D_METHOD("get_octaves"), &BiomeDef::get_octaves);
    ClassDB::bind_method(D_METHOD("set_octaves", "v"), &BiomeDef::set_octaves);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "octaves"), "set_octaves", "get_octaves");

    ClassDB::bind_method(D_METHOD("get_background_material"), &BiomeDef::get_background_material);
    ClassDB::bind_method(D_METHOD("set_background_material", "v"),
                         &BiomeDef::set_background_material);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "background_material"),
                 "set_background_material", "get_background_material");

    ClassDB::bind_method(D_METHOD("get_pool_materials"), &BiomeDef::get_pool_materials);
    ClassDB::bind_method(D_METHOD("set_pool_materials", "v"), &BiomeDef::set_pool_materials);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "pool_materials",
                              PROPERTY_HINT_ARRAY_TYPE, "PoolDef"),
                 "set_pool_materials", "get_pool_materials");

    ClassDB::bind_method(D_METHOD("get_room_templates"), &BiomeDef::get_room_templates);
    ClassDB::bind_method(D_METHOD("set_room_templates", "v"), &BiomeDef::set_room_templates);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "room_templates",
                              PROPERTY_HINT_ARRAY_TYPE, "RoomTemplate"),
                 "set_room_templates", "get_room_templates");

    ClassDB::bind_method(D_METHOD("get_boss_templates"), &BiomeDef::get_boss_templates);
    ClassDB::bind_method(D_METHOD("set_boss_templates", "v"), &BiomeDef::set_boss_templates);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "boss_templates",
                              PROPERTY_HINT_ARRAY_TYPE, "RoomTemplate"),
                 "set_boss_templates", "get_boss_templates");

    ClassDB::bind_method(D_METHOD("get_secret_ring_thickness"),
                         &BiomeDef::get_secret_ring_thickness);
    ClassDB::bind_method(D_METHOD("set_secret_ring_thickness", "v"),
                         &BiomeDef::set_secret_ring_thickness);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "secret_ring_thickness"),
                 "set_secret_ring_thickness", "get_secret_ring_thickness");

    ClassDB::bind_method(D_METHOD("get_tint"), &BiomeDef::get_tint);
    ClassDB::bind_method(D_METHOD("set_tint", "v"), &BiomeDef::set_tint);
    ADD_PROPERTY(PropertyInfo(Variant::COLOR, "tint"), "set_tint", "get_tint");
}

} // namespace toprogue
