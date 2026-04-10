class_name TextureArrayBuilder

static func build_from_paths(paths: Array[String]) -> Texture2DArray:
	var images: Array[Image] = []
	for path in paths:
		var img := Image.load_from_file(path)
		images.append(img)
	return build_from_images(images)

static func build_from_images(images: Array[Image]) -> Texture2DArray:
	if images.is_empty():
		push_error("TextureArrayBuilder: No images provided")
		return null

	var ref_size := images[0].get_size()
	var ref_format := images[0].get_format()

	for i in images.size():
		var img := images[i]
		if img.get_size() != ref_size:
			push_error("TextureArrayBuilder: Image %d size %s doesn't match reference size %s" % [i, img.get_size(), ref_size])
			return null
		if img.get_format() != ref_format:
			push_error("TextureArrayBuilder: Image %d format doesn't match" % i)
			return null

	var tex := Texture2DArray.new()
	var err := tex.create_from_images(images)
	if err != OK:
		push_error("TextureArrayBuilder: Failed to create texture array: %s" % err)
		return null
	return tex


static func save_texture_array(tex: Texture2DArray, path: String) -> int:
	return ResourceSaver.save(tex, path)


static func create_placeholder_image(size: Vector2i, color: Color) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img