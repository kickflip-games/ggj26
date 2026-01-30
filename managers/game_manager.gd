extends Node

signal room_registered(room: Node)
signal room_reset()
signal key_changed(has_key: bool)

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

var _player_spawn: Transform3D
var _monster_spawns_by_id: Dictionary = {}
var _keys_by_id: Dictionary = {}

func register_room(room: Node) -> void:
	current_room = room
	has_key = false
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

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		if mask_manager.has_method("refill_energy"):
			mask_manager.refill_energy()
		mask_manager.mask_on = false

	has_key = false

	if player != null:
		player.global_transform = _player_spawn
		player.velocity = Vector3.ZERO

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
	reset_room()

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
