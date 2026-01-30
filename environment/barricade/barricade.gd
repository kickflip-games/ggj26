class_name Barricade
extends Node3D

@export var requires_hammer := true
@export var interaction_action := "interact"
@export var prompt_with_hammer := "Press E to break"
@export var prompt_without_hammer := "Need a hammer"
@export_range(1.0, 179.0, 1.0) var interaction_angle_deg := 45.0
@export var interaction_max_distance := 2.5

@export var debris_scene: PackedScene = preload("res://environment/barricade/plank_debris.tscn")
@export var debris_count := 4
@export var debris_spawn_spread := Vector3(0.8, 0.6, 0.3)
@export var debris_impulse := 4.0
@export var debris_torque := 6.0

@onready var trigger_area: Area3D = $TriggerArea
@onready var model: Node3D = get_node_or_null("Model")
@onready var blocker: StaticBody3D = get_node_or_null("Blocker")

var _broken := false
var _player_in_trigger := false
var _player: Player = null
var _blocker_layer := 0
var _blocker_mask := 0

func _ready() -> void:
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)
	if blocker != null:
		_blocker_layer = blocker.collision_layer
		_blocker_mask = blocker.collision_mask
	_apply_state()

func reset_pickup() -> void:
	# Integrates with GameManager.reset_room() pickup reset scan.
	_broken = false
	_player_in_trigger = false
	_player = null
	_apply_state()

func break_with_hammer(_hit: Dictionary = {}) -> void:
	_try_break()

func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_trigger = true
		_player = body as Player
		_update_prompt()

func _on_body_exited(body: Node) -> void:
	if body is Player:
		_player_in_trigger = false
		if _player != null:
			_player.clear_interact_prompt()
		_player = null

func _process(_delta: float) -> void:
	if _broken:
		return
	if not _player_in_trigger or _player == null:
		return

	_update_prompt()

	if not Input.is_action_just_pressed(interaction_action):
		return
	if not _player_facing_barricade():
		return
	_try_break()

func _player_facing_barricade() -> bool:
	if _player == null:
		return false
	var camera: Camera3D = _player.get_node_or_null(^"CameraRig/Camera3D") as Camera3D
	if camera == null:
		return true

	var origin := camera.global_position
	var to_me := global_position - origin
	var dist := to_me.length()
	if dist <= 0.001:
		return true
	if dist > maxf(interaction_max_distance, 0.0):
		return false

	var forward := (-camera.global_transform.basis.z).normalized()
	var dir := to_me / dist
	var dot := clampf(forward.dot(dir), -1.0, 1.0)
	var threshold := cos(deg_to_rad(clampf(interaction_angle_deg, 1.0, 179.0)))
	return dot >= threshold

func _update_prompt() -> void:
	if _player == null:
		return
	if _broken or not _player_in_trigger:
		_player.clear_interact_prompt()
		return

	if not _player_facing_barricade():
		_player.clear_interact_prompt()
		return

	if requires_hammer and not GameManager.has_hammer:
		_player.set_interact_prompt("%s (E)" % prompt_without_hammer)
	else:
		_player.set_interact_prompt(prompt_with_hammer)

func _try_break() -> void:
	if _broken:
		return
	if requires_hammer and not GameManager.has_hammer:
		if _player != null:
			_player.flash_message(prompt_without_hammer)
		return

	_broken = true
	_apply_state()
	_spawn_debris()

func _apply_state() -> void:
	if model != null:
		model.visible = not _broken
	if blocker != null:
		blocker.visible = not _broken
		blocker.process_mode = Node.PROCESS_MODE_INHERIT
		blocker.set_deferred("collision_layer", 0 if _broken else _blocker_layer)
		blocker.set_deferred("collision_mask", 0 if _broken else _blocker_mask)
	if trigger_area != null:
		trigger_area.set_deferred("monitoring", not _broken)

func _spawn_debris() -> void:
	if debris_scene == null:
		return
	if debris_count <= 0:
		return

	var parent_node: Node = get_parent() if get_parent() != null else get_tree().root
	var base := global_transform

	for i in range(debris_count):
		var instance := debris_scene.instantiate()
		var body := instance as RigidBody3D
		if body == null:
			instance.free()
			continue

		var offset := Vector3(
			randf_range(-debris_spawn_spread.x, debris_spawn_spread.x),
			randf_range(0.0, debris_spawn_spread.y),
			randf_range(-debris_spawn_spread.z, debris_spawn_spread.z)
		)
		body.global_transform = base.translated_local(offset)
		parent_node.add_child(body)

		var impulse_dir := (global_transform.basis.z * -1.0 + Vector3.UP * 0.35).normalized()
		body.apply_impulse(Vector3.ZERO, impulse_dir * debris_impulse * randf_range(0.6, 1.2))
		body.apply_torque_impulse(Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized() * debris_torque * randf_range(0.6, 1.2))
