class_name KeyPickup
extends Node3D

@onready var pickup_area: Area3D = $PickupArea
@onready var model: Node3D = get_node_or_null("Model")
@onready var _sfx: AudioStreamPlayer3D = get_node_or_null("SfxPickup")

var _collected := false
var _player_in_area := false
var _anim_time: float = 0.0
var _base_model_pos: Vector3

@export var model_offset := Vector3.ZERO
@export var model_rotation_degrees := Vector3.ZERO
@export var model_scale := Vector3.ONE
@export var pickup_stream: AudioStream
@export var pickup_volume_db := -6.0
@export var spin_degrees_per_second := 90.0
@export var bob_amplitude := 0.12
@export var bob_cycles_per_second := 0.75

func _ready() -> void:
	_apply_model_transform()
	_apply_audio()
	pickup_area.body_entered.connect(_on_body_entered)
	pickup_area.body_exited.connect(_on_body_exited)

	_base_model_pos = model_offset
	visible = not _collected

func reset_pickup() -> void:
	_collected = false
	_player_in_area = false
	pickup_area.set_deferred("monitoring", true)
	visible = true

func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_area = true
		_collect()

func _on_body_exited(body: Node) -> void:
	if body is Player:
		_player_in_area = false

func _collect() -> void:
	if _collected:
		return
	_collected = true
	_play_pickup_sfx()
	GameManager.has_key = true
	visible = false
	pickup_area.set_deferred("monitoring", false)

func _process(delta: float) -> void:
	if _collected or model == null:
		return

	_anim_time += delta
	model.rotation_degrees = model_rotation_degrees + Vector3(0.0, spin_degrees_per_second * _anim_time, 0.0)

	var bob: float = sin(_anim_time * TAU * bob_cycles_per_second) * bob_amplitude
	model.position = _base_model_pos + Vector3(0.0, bob, 0.0)

func _apply_model_transform() -> void:
	if model == null:
		return
	model.position = model_offset
	model.rotation_degrees = model_rotation_degrees
	model.scale = model_scale

func _apply_audio() -> void:
	if _sfx == null:
		return
	if pickup_stream != null:
		_sfx.stream = pickup_stream
	_sfx.volume_db = pickup_volume_db

func _play_pickup_sfx() -> void:
	if _sfx == null:
		return
	if _sfx.stream == null and pickup_stream != null:
		_sfx.stream = pickup_stream
	if _sfx.stream == null:
		return
	_sfx.play()
