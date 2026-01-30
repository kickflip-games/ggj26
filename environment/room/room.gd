class_name Room
extends Node3D

@export var reset_keys_on_reset := true
@export var player_spawn_path: NodePath = ^"PlayerSpawn"

func _ready() -> void:
	GameManager.register_room(self)

func should_reset_keys() -> bool:
	return reset_keys_on_reset

func get_player_spawn_transform() -> Transform3D:
	var spawn := get_node_or_null(player_spawn_path)
	if spawn is Node3D:
		return spawn.global_transform
	return global_transform

func get_player() -> Player:
	var players := find_children("*", "Player", true, false)
	return players[0] as Player if players.size() > 0 else null

func get_monsters() -> Array[Monster]:
	var result: Array[Monster] = []
	for node in find_children("*", "Monster", true, false):
		result.append(node as Monster)
	return result
