extends Node

signal room_registered(room: Node)
signal room_reset()
signal key_changed(has_key: bool)
signal hammer_changed(has_hammer: bool)
signal game_over()
signal game_won()

var current_room: Node = null
var player: Player = null
var _has_key := false
var has_key: bool:
	get:
		return _has_key
	set(value):
		if _has_key == value:
			return
			_has_key = value
			key_changed.emit(_has_key)

var _has_hammer := false
var has_hammer: bool:
	get:
		return _has_hammer
	set(value):
		if _has_hammer == value:
			return
		_has_hammer = value
		hammer_changed.emit(_has_hammer)

var _player_spawn: Transform3D
var _monster_spawns_by_id: Dictionary = {}
var _keys_by_id: Dictionary = {}

enum GameState { PLAYING, GAME_OVER, WON }
var state: GameState = GameState.PLAYING

var _end_screen_scene: PackedScene = preload("res://ui/end_screen.tscn")
var _end_screen: EndScreen = null
var _pending_next_scene_path := ""
var _pending_use_level_manager := false

func register_room(room: Node) -> void:
	current_room = room
	has_key = false
	has_hammer = false
	state = GameState.PLAYING
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null and mask_manager.has_method("refill_energy"):
		mask_manager.refill_energy()
	if mask_manager != null:
		mask_manager.mask_on = false
	_cache_room_state(room)
	room_registered.emit(room)

func reset_room() -> void:
	if current_room == null:
		return
	if state != GameState.PLAYING:
		_resume_playing()

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		if mask_manager.has_method("refill_energy"):
			mask_manager.refill_energy()
		mask_manager.mask_on = false

	has_key = false
	has_hammer = false

	if player != null:
		player.global_transform = _player_spawn
		player.velocity = Vector3.ZERO
		if player.has_method("unequip_hammer"):
			player.unequip_hammer()

	for instance_id in _monster_spawns_by_id.keys():
		var monster := instance_from_id(instance_id)
		if monster == null:
			continue
		monster.global_transform = _monster_spawns_by_id[instance_id]
		if monster.has_method("reset_patrol"):
			monster.reset_patrol()
		if monster is CharacterBody3D:
			monster.velocity = Vector3.ZERO

	var should_reset_keys := true
	if current_room.has_method("should_reset_keys"):
		should_reset_keys = current_room.should_reset_keys()

	if should_reset_keys:
		for instance_id in _keys_by_id.keys():
			var key := instance_from_id(instance_id)
			if key == null:
				continue
			if key.has_method("reset_pickup"):
				key.reset_pickup()

	room_reset.emit()

func player_caught() -> void:
	if state != GameState.PLAYING:
		return
	_show_game_over()

func player_won(next_scene_path: String = "") -> void:
	if state != GameState.PLAYING:
		return
	_show_win(next_scene_path)

func _show_game_over() -> void:
	state = GameState.GAME_OVER
	game_over.emit()
	_pause_and_show_end_screen(
		"GAME OVER",
		"You were caught.",
		"Retry",
		"Quit",
		true
	)
	if _end_screen != null:
		_end_screen.primary_action.connect(_on_game_over_retry, Object.CONNECT_ONE_SHOT)
		_end_screen.secondary_action.connect(_on_game_over_quit, Object.CONNECT_ONE_SHOT)

func _show_win(next_scene_path: String) -> void:
	state = GameState.WON
	game_won.emit()
	_pending_next_scene_path = next_scene_path
	_pending_use_level_manager = next_scene_path.is_empty()

	_pause_and_show_end_screen(
		"YOU ESCAPED",
		"Press Enter to continue.",
		"Continue",
		"Restart",
		true
	)
	if _end_screen != null:
		_end_screen.primary_action.connect(_on_win_continue, Object.CONNECT_ONE_SHOT)
		_end_screen.secondary_action.connect(_on_win_restart, Object.CONNECT_ONE_SHOT)

func _pause_and_show_end_screen(title: String, subtitle: String, primary: String, secondary: String, show_secondary: bool) -> void:
	_clear_end_screen()
	if _end_screen_scene == null:
		return

	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var instance := _end_screen_scene.instantiate()
	_end_screen = instance as EndScreen
	if _end_screen == null:
		instance.free()
		return

	_end_screen.title_text = title
	_end_screen.subtitle_text = subtitle
	_end_screen.primary_text = primary
	_end_screen.secondary_text = secondary
	_end_screen.show_secondary = show_secondary

	get_tree().root.add_child(_end_screen)

func _clear_end_screen() -> void:
	if _end_screen != null:
		_end_screen.queue_free()
		_end_screen = null

func _resume_playing() -> void:
	get_tree().paused = false
	_clear_end_screen()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	state = GameState.PLAYING

func _on_game_over_retry() -> void:
	_resume_playing()
	reset_room()

func _on_game_over_quit() -> void:
	get_tree().paused = false
	_clear_end_screen()
	get_tree().quit()

func _on_win_restart() -> void:
	_resume_playing()
	reset_room()

func _on_win_continue() -> void:
	get_tree().paused = false
	_clear_end_screen()
	state = GameState.PLAYING

	if not _pending_next_scene_path.is_empty():
		get_tree().change_scene_to_file(_pending_next_scene_path)
		return

	if _pending_use_level_manager:
		var level_manager := get_node_or_null("/root/LevelManager")
		if level_manager != null and level_manager.has_method("load_next"):
			var ok: bool = level_manager.load_next()
			if ok:
				return

	get_tree().quit()

func _cache_room_state(room: Node) -> void:
	player = null
	_player_spawn = Transform3D.IDENTITY
	_monster_spawns_by_id.clear()
	_keys_by_id.clear()

	# Prefer Room API when present.
	if room.has_method("get_player_spawn_transform"):
		_player_spawn = room.get_player_spawn_transform()
	else:
		var spawn := room.get_node_or_null("PlayerSpawn")
		if spawn is Node3D:
			_player_spawn = spawn.global_transform

	# Prefer explicit Room player reference when present.
	if room.has_method("get_player"):
		player = room.get_player()
	else:
		var players := room.find_children("*", "Player", true, false)
		player = players[0] as Player if players.size() > 0 else null

	for monster in room.find_children("*", "Monster", true, false):
		_monster_spawns_by_id[monster.get_instance_id()] = (monster as Node3D).global_transform

	var stack: Array[Node] = [room]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			if child.has_method("reset_pickup"):
				_keys_by_id[child.get_instance_id()] = true
			stack.append(child)
