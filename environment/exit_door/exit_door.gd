class_name ExitDoor
extends Node3D

@export var requires_key := false
@export_file("*.tscn") var next_scene_path := ""
@export var interaction_action := "interact"
@export var prompt_when_unlocked := "Press E to open"
@export var prompt_when_locked := "Needs a key"
@export var model_offset := Vector3.ZERO
@export var model_rotation_degrees := Vector3.ZERO
@export var model_scale := Vector3.ONE
@export var open_stream: AudioStream
@export var locked_stream: AudioStream
@export var open_volume_db := -6.0
@export var locked_volume_db := -6.0
@export var open_delay_seconds := 0.12

@onready var trigger_area: Area3D = $TriggerArea
@onready var model: Node3D = get_node_or_null("Model")
@onready var _sfx_open: AudioStreamPlayer3D = get_node_or_null("SfxOpen")
@onready var _sfx_locked: AudioStreamPlayer3D = get_node_or_null("SfxLocked")

var _player_in_trigger := false
var _player: Player = null

func _ready() -> void:
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)

	_apply_model_transform()
	_apply_audio()

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_toggled(mask_manager.mask_on)

func _on_mask_toggled(mask_on: bool) -> void:
	visible = mask_on
	_update_prompt()

func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
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
	if not _player_in_trigger or _player == null:
		return
	if not Input.is_action_just_pressed(interaction_action):
		return
	_try_exit()

func _try_exit() -> void:
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager == null or not mask_manager.mask_on:
		return

	if requires_key and not GameManager.has_key:
		if _player != null:
			_play_locked_sfx()
			_player.flash_message(prompt_when_locked)
			_update_prompt()
		return

	_play_open_sfx()
	if open_delay_seconds > 0.0:
		await get_tree().create_timer(open_delay_seconds).timeout

	if next_scene_path.is_empty():
		var level_manager := get_node_or_null("/root/LevelManager")
		if level_manager != null and level_manager.has_method("load_next"):
			var ok: bool = level_manager.load_next()
			if not ok:
				get_tree().quit()
			return
		get_tree().quit()
		return

	get_tree().change_scene_to_file(next_scene_path)

func _update_prompt() -> void:
	if _player == null:
		return
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager == null or not mask_manager.mask_on:
		_player.clear_interact_prompt()
		return
	if not _player_in_trigger:
		_player.clear_interact_prompt()
		return

	if requires_key and not GameManager.has_key:
		_player.set_interact_prompt("%s (E)" % prompt_when_locked)
	else:
		_player.set_interact_prompt(prompt_when_unlocked)

func _apply_model_transform() -> void:
	if model == null:
		return
	model.position = model_offset
	model.rotation_degrees = model_rotation_degrees
	model.scale = model_scale

func _apply_audio() -> void:
	if _sfx_open != null:
		if open_stream != null:
			_sfx_open.stream = open_stream
		_sfx_open.volume_db = open_volume_db
	if _sfx_locked != null:
		if locked_stream != null:
			_sfx_locked.stream = locked_stream
		_sfx_locked.volume_db = locked_volume_db

func _play_open_sfx() -> void:
	if _sfx_open == null:
		return
	if _sfx_open.stream == null and open_stream != null:
		_sfx_open.stream = open_stream
	if _sfx_open.stream == null:
		return
	_sfx_open.play()

func _play_locked_sfx() -> void:
	if _sfx_locked == null:
		return
	if _sfx_locked.stream == null and locked_stream != null:
		_sfx_locked.stream = locked_stream
	if _sfx_locked.stream == null:
		return
	_sfx_locked.play()
