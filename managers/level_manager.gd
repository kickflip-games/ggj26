extends Node

@export_dir var rooms_dir := "res://rooms"
@export var room_prefix := "room"
@export var loop_after_last := false

var _levels: Array[String] = []

func _ready() -> void:
	_refresh_levels()

func refresh() -> void:
	_refresh_levels()

func load_next() -> bool:
	_refresh_levels()
	if _levels.is_empty():
		push_warning("LevelManager: No levels found in %s" % rooms_dir)
		return false

	var current_path := ""
	if get_tree().current_scene != null:
		current_path = get_tree().current_scene.scene_file_path

	var idx := _levels.find(current_path)
	var next_idx := 0 if idx == -1 else (idx + 1)

	if next_idx >= _levels.size():
		if loop_after_last:
			next_idx = 0
		else:
			return false

	return load_path(_levels[next_idx])

func restart_current() -> bool:
	_refresh_levels()
	if get_tree().current_scene == null:
		return false
	var path := get_tree().current_scene.scene_file_path
	if path.is_empty():
		return false
	return load_path(path)

func load_path(path: String) -> bool:
	if path.is_empty():
		return false
	var err := get_tree().change_scene_to_file(path)
	return err == OK

func _refresh_levels() -> void:
	var dir := DirAccess.open(rooms_dir)
	if dir == null:
		_levels = []
		return

	var files := dir.get_files()
	var levels: Array[String] = []
	for file_name in files:
		if not file_name.ends_with(".tscn"):
			continue
		if not room_prefix.is_empty() and not file_name.to_lower().begins_with(room_prefix.to_lower()):
			continue
		levels.append(rooms_dir.path_join(file_name))

	levels.sort_custom(func(a: String, b: String) -> bool:
		return _natural_less(a.get_file().get_basename(), b.get_file().get_basename())
	)

	_levels = levels

static func _natural_less(a: String, b: String) -> bool:
	var ka := _natural_key(a)
	var kb := _natural_key(b)
	if ka.prefix != kb.prefix:
		return ka.prefix < kb.prefix
	if ka.has_num and kb.has_num and ka.num != kb.num:
		return ka.num < kb.num
	if ka.rest != kb.rest:
		return ka.rest < kb.rest
	return a < b

static func _natural_key(s: String) -> Dictionary:
	var lower := s.to_lower()
	var i := 0
	while i < lower.length() and not lower[i].is_valid_int():
		i += 1

	var prefix := lower.substr(0, i)
	var j := i
	while j < lower.length() and lower[j].is_valid_int():
		j += 1

	var has_num := j > i
	var num := int(lower.substr(i, j - i)) if has_num else -1
	var rest := lower.substr(j, lower.length() - j)
	return {
		"prefix": prefix,
		"has_num": has_num,
		"num": num,
		"rest": rest,
	}
