class_name CameraRig
extends Node3D

@export var headbob_enabled := true
@export var headbob_freq_hz := 0.4
@export var headbob_amp_x := 0.03
@export var headbob_amp_y := 0.06
@export var headbob_pitch_deg := 0.6
@export var headbob_smooth := 12.0

@export var move_sway_enabled := true
@export var move_sway_roll_deg := 2.0
@export var move_sway_pitch_deg := 1.2
@export var move_sway_smooth := 10.0

@onready var camera: Camera3D = $Camera3D

var _base_camera_pos: Vector3
var _base_camera_rot: Vector3
var _bob_t: float = 0.0
var _bob_offset: Vector3 = Vector3.ZERO
var _bob_pitch: float = 0.0
var _sway_roll: float = 0.0
var _sway_pitch: float = 0.0

func _ready() -> void:
	_base_camera_pos = camera.position
	_base_camera_rot = camera.rotation
	camera.make_current()

func reset_pose() -> void:
	_bob_t = 0.0
	_bob_offset = Vector3.ZERO
	_bob_pitch = 0.0
	_sway_roll = 0.0
	_sway_pitch = 0.0
	camera.position = _base_camera_pos
	camera.rotation = _base_camera_rot
	rotation = Vector3.ZERO

func update_motion(delta: float, look_pitch: float, input_dir: Vector2, current_speed: float, player_velocity: Vector3, is_grounded: bool) -> void:
	var horiz_speed := Vector3(player_velocity.x, 0.0, player_velocity.z).length()
	var moving := is_grounded and horiz_speed > 0.05
	var move_amt := clampf(horiz_speed / max(current_speed, 0.001), 0.0, 1.0) if moving else 0.0

	var w_bob := _smooth_factor(delta, headbob_smooth)
	var w_sway := _smooth_factor(delta, move_sway_smooth)

	var desired_offset := Vector3.ZERO
	var desired_bob_pitch := 0.0
	if headbob_enabled and moving:
		var omega := TAU * headbob_freq_hz
		_bob_t += delta * horiz_speed
		desired_offset.x = cos(_bob_t * omega * 0.5) * headbob_amp_x * move_amt
		desired_offset.y = sin(_bob_t * omega) * headbob_amp_y * move_amt
		desired_bob_pitch = sin(_bob_t * omega) * deg_to_rad(headbob_pitch_deg) * move_amt
	else:
		_bob_t = 0.0

	_bob_offset = _bob_offset.lerp(desired_offset, w_bob)
	_bob_pitch = lerp(_bob_pitch, desired_bob_pitch, w_bob)

	var desired_roll := 0.0
	var desired_sway_pitch := 0.0
	if move_sway_enabled:
		desired_roll = -input_dir.x * deg_to_rad(move_sway_roll_deg) * move_amt
		desired_sway_pitch = -input_dir.y * deg_to_rad(move_sway_pitch_deg) * move_amt

	_sway_roll = lerp(_sway_roll, desired_roll, w_sway)
	_sway_pitch = lerp(_sway_pitch, desired_sway_pitch, w_sway)

	camera.position = _base_camera_pos + _bob_offset
	camera.rotation = Vector3(
		_base_camera_rot.x + look_pitch + _bob_pitch + _sway_pitch,
		_base_camera_rot.y,
		_base_camera_rot.z
	)

	rotation = Vector3(0.0, 0.0, _sway_roll)

func _smooth_factor(delta: float, sharpness: float) -> float:
	return 1.0 - exp(-delta * max(sharpness, 0.0001))
