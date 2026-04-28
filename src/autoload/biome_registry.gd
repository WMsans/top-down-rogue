extends Node

const BIOME_PATHS := [
	"res://assets/biomes/caves.tres",
	"res://assets/biomes/mines.tres",
	"res://assets/biomes/magma.tres",
	"res://assets/biomes/frozen.tres",
	"res://assets/biomes/vault.tres",
]

var biomes: Array[BiomeDef] = []
var template_pack: TemplatePack
var _template_index_for_template: Dictionary = {}  # RoomTemplate → int index in size class


func _ready() -> void:
	template_pack = TemplatePack.new()
	for path in BIOME_PATHS:
		var b: BiomeDef = load(path)
		if b == null:
			push_error("BiomeRegistry: failed to load %s" % path)
			continue
		biomes.append(b)
		for tmpl in b.room_templates:
			_register(tmpl as RoomTemplate)
		for tmpl in b.boss_templates:
			_register(tmpl as RoomTemplate)
	template_pack.build_arrays()


func _register(tmpl: RoomTemplate) -> void:
	if _template_index_for_template.has(tmpl):
		return
	var idx := template_pack.register(tmpl)
	_template_index_for_template[tmpl] = idx


func get_biome(floor_number: int) -> BiomeDef:
	if biomes.is_empty():
		push_error("BiomeRegistry: no biomes loaded")
		return null
	var i: int = (floor_number - 1) % biomes.size()
	return biomes[i]


func get_template_index(tmpl: RoomTemplate) -> int:
	return _template_index_for_template.get(tmpl, -1)


func get_template_arrays() -> Dictionary:
	var d: Dictionary = {}
	for sc in template_pack.get_size_classes():
		d[sc] = template_pack.get_array(sc)
	return d
