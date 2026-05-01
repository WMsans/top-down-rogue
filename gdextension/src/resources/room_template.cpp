#include "room_template.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace toprogue {

void RoomTemplate::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_png_path"), &RoomTemplate::get_png_path);
    ClassDB::bind_method(D_METHOD("set_png_path", "v"), &RoomTemplate::set_png_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "png_path"), "set_png_path", "get_png_path");

    ClassDB::bind_method(D_METHOD("get_weight"), &RoomTemplate::get_weight);
    ClassDB::bind_method(D_METHOD("set_weight", "v"), &RoomTemplate::set_weight);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "weight"), "set_weight", "get_weight");

    ClassDB::bind_method(D_METHOD("get_size_class"), &RoomTemplate::get_size_class);
    ClassDB::bind_method(D_METHOD("set_size_class", "v"), &RoomTemplate::set_size_class);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "size_class"), "set_size_class", "get_size_class");

    ClassDB::bind_method(D_METHOD("get_is_secret"), &RoomTemplate::get_is_secret);
    ClassDB::bind_method(D_METHOD("set_is_secret", "v"), &RoomTemplate::set_is_secret);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_secret"), "set_is_secret", "get_is_secret");

    ClassDB::bind_method(D_METHOD("get_is_boss"), &RoomTemplate::get_is_boss);
    ClassDB::bind_method(D_METHOD("set_is_boss", "v"), &RoomTemplate::set_is_boss);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_boss"), "set_is_boss", "get_is_boss");

    ClassDB::bind_method(D_METHOD("get_rotatable"), &RoomTemplate::get_rotatable);
    ClassDB::bind_method(D_METHOD("set_rotatable", "v"), &RoomTemplate::set_rotatable);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "rotatable"), "set_rotatable", "get_rotatable");
}

} // namespace toprogue
