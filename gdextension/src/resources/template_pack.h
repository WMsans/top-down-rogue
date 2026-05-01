#pragma once

#include "room_template.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace toprogue {

class TemplatePack : public godot::RefCounted {
    GDCLASS(TemplatePack, godot::RefCounted);

    struct Entry {
        godot::Ref<RoomTemplate> tmpl;
        godot::Ref<godot::Image> image;
    };

    godot::HashMap<int, godot::Vector<Entry>> _by_size;
    godot::HashMap<int, godot::Ref<godot::Texture2DArray>> _arrays;

public:
    TemplatePack() = default;

    int  register_template(const godot::Ref<RoomTemplate> &tmpl);
    void build_arrays();
    godot::Ref<godot::Texture2DArray> get_array(int size_class) const;
    godot::Ref<godot::Image>          get_image(int size_class, int index) const;
    godot::Array                      collect_markers(int size_class, int index) const;
    godot::Array                      get_size_classes() const;
    int                               template_count(int size_class) const;

protected:
    static void _bind_methods();
};

} // namespace toprogue
