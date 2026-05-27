class_name TemplatePack
extends RefCounted

# Per size_class, a list of (template, image)
var _by_size: Dictionary = {}        # int → Array[Dictionary]{template, image}
var _arrays: Dictionary = {}         # int → Texture2DArray


func register(tmpl: RoomTemplate) -> int:
	if not _by_size.has(tmpl.size_class):
		_by_size[tmpl.size_class] = []
	var bucket: Array = _by_size[tmpl.size_class]
	var idx := bucket.size()
	bucket.append({"template": tmpl, "image": null})
	return idx


func build_arrays() -> void:
	for size_class in _by_size.keys():
		var bucket: Array = _by_size[size_class]
		var images: Array[Image] = []
		for entry in bucket:
			var tmpl: RoomTemplate = entry["template"]
			var img := Image.load_from_file(tmpl.png_path)
			if img == null:
				push_error("TemplatePack: failed to load %s" % tmpl.png_path)
				continue
			# Pad/resize to size_class if needed
			if img.get_width() != size_class or img.get_height() != size_class:
				var padded := Image.create(size_class, size_class, false, Image.FORMAT_RGBA8)
				padded.fill(Color(0, 0, 0, 0))
				var ox : int = (size_class - img.get_width()) / 2
				var oy : int = (size_class - img.get_height()) / 2
				padded.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(ox, oy))
				img = padded
			entry["image"] = img
			images.append(img)
		if not images.is_empty():
			_arrays[size_class] = TextureArrayBuilder.build_from_images(images)


func get_array(size_class: int) -> Texture2DArray:
	return _arrays.get(size_class, null)


func get_image(size_class: int, index: int) -> Image:
	if not _by_size.has(size_class):
		return null
	var bucket: Array = _by_size[size_class]
	if index < 0 or index >= bucket.size():
		return null
	return bucket[index]["image"]


# Returns Array of {pos: Vector2i (local), type: int}
func collect_markers(size_class: int, index: int) -> Array:
	var result: Array = []
	var img := get_image(size_class, index)
	if img == null:
		return result
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if int(c.a8) != 255:
				continue
			var marker := int(c.g8)
			if marker > 0:
				result.append({"pos": Vector2i(x, y), "type": marker})
	return result


func get_size_classes() -> Array:
	return _by_size.keys()


func template_count(size_class: int) -> int:
	if not _by_size.has(size_class):
		return 0
	return (_by_size[size_class] as Array).size()
