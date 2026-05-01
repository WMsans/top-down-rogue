#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string.hpp>

namespace toprogue {

class RoomTemplate : public godot::Resource {
    GDCLASS(RoomTemplate, godot::Resource);

public:
    godot::String png_path;
    double weight     = 1.0;
    int    size_class = 64;
    bool   is_secret  = false;
    bool   is_boss    = false;
    bool   rotatable  = true;

    RoomTemplate() = default;

    godot::String get_png_path() const          { return png_path; }
    void          set_png_path(const godot::String &v) { png_path = v; }
    double        get_weight() const            { return weight; }
    void          set_weight(double v)          { weight = v; }
    int           get_size_class() const        { return size_class; }
    void          set_size_class(int v)         { size_class = v; }
    bool          get_is_secret() const         { return is_secret; }
    void          set_is_secret(bool v)         { is_secret = v; }
    bool          get_is_boss() const           { return is_boss; }
    void          set_is_boss(bool v)           { is_boss = v; }
    bool          get_rotatable() const         { return rotatable; }
    void          set_rotatable(bool v)         { rotatable = v; }

protected:
    static void _bind_methods();
};

} // namespace toprogue
