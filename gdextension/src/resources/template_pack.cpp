#include "template_pack.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace toprogue {

int TemplatePack::register_template(const Ref<RoomTemplate> &tmpl) {
    if (tmpl.is_null()) {
        UtilityFunctions::push_error("TemplatePack.register: null template");
        return -1;
    }
    int sc = tmpl->size_class;
    Vector<Entry> &bucket = _by_size[sc];
    int idx = bucket.size();
    Entry e;
    e.tmpl = tmpl;
    e.image = Ref<Image>();
    bucket.push_back(e);
    return idx;
}

void TemplatePack::build_arrays() {
    Object *array_builder = Engine::get_singleton()->get_singleton("TextureArrayBuilder");
    if (array_builder == nullptr) {
        UtilityFunctions::push_error("TemplatePack: TextureArrayBuilder autoload missing");
        return;
    }

    for (KeyValue<int, Vector<Entry>> &kv : _by_size) {
        int sc = kv.key;
        Vector<Entry> &bucket = kv.value;
        Array images;
        for (int i = 0; i < bucket.size(); i++) {
            Entry &e = bucket.write[i];
            String path = e.tmpl.is_valid() ? e.tmpl->png_path : String();
            Ref<Image> img = Image::load_from_file(path);
            if (img.is_null()) {
                UtilityFunctions::push_error(String("TemplatePack: failed to load ") + path);
                continue;
            }
            if (img->get_width() != sc || img->get_height() != sc) {
                Ref<Image> padded = Image::create(sc, sc, false, Image::FORMAT_RGBA8);
                padded->fill(Color(0, 0, 0, 0));
                int ox = (sc - img->get_width()) / 2;
                int oy = (sc - img->get_height()) / 2;
                padded->blit_rect(img,
                                  Rect2i(0, 0, img->get_width(), img->get_height()),
                                  Vector2i(ox, oy));
                img = padded;
            }
            e.image = img;
            images.push_back(img);
        }
        if (!images.is_empty()) {
            Variant result = array_builder->call("build_from_images", images);
            _arrays[sc] = Ref<Texture2DArray>(result);
        }
    }
}

Ref<Texture2DArray> TemplatePack::get_array(int size_class) const {
    const Ref<Texture2DArray> *p = _arrays.getptr(size_class);
    return p ? *p : Ref<Texture2DArray>();
}

Ref<Image> TemplatePack::get_image(int size_class, int index) const {
    const Vector<Entry> *bucket = _by_size.getptr(size_class);
    if (bucket == nullptr) return Ref<Image>();
    if (index < 0 || index >= bucket->size()) return Ref<Image>();
    return (*bucket)[index].image;
}

Array TemplatePack::collect_markers(int size_class, int index) const {
    Array result;
    Ref<Image> img = get_image(size_class, index);
    if (img.is_null()) return result;
    int w = img->get_width();
    int h = img->get_height();
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            Color c = img->get_pixel(x, y);
            if (c.get_a8() != 255) continue;
            int marker = c.get_g8();
            if (marker > 0) {
                Dictionary d;
                d["pos"]  = Vector2i(x, y);
                d["type"] = marker;
                result.push_back(d);
            }
        }
    }
    return result;
}

Array TemplatePack::get_size_classes() const {
    Array result;
    for (const KeyValue<int, Vector<Entry>> &kv : _by_size) {
        result.push_back(kv.key);
    }
    return result;
}

int TemplatePack::template_count(int size_class) const {
    const Vector<Entry> *bucket = _by_size.getptr(size_class);
    return bucket ? bucket->size() : 0;
}

void TemplatePack::_bind_methods() {
    ClassDB::bind_method(D_METHOD("register", "tmpl"), &TemplatePack::register_template);
    ClassDB::bind_method(D_METHOD("build_arrays"),     &TemplatePack::build_arrays);
    ClassDB::bind_method(D_METHOD("get_array", "size_class"), &TemplatePack::get_array);
    ClassDB::bind_method(D_METHOD("get_image", "size_class", "index"), &TemplatePack::get_image);
    ClassDB::bind_method(D_METHOD("collect_markers", "size_class", "index"),
                         &TemplatePack::collect_markers);
    ClassDB::bind_method(D_METHOD("get_size_classes"), &TemplatePack::get_size_classes);
    ClassDB::bind_method(D_METHOD("template_count", "size_class"),
                         &TemplatePack::template_count);
}

} // namespace toprogue
