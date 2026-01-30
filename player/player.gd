class_name Player
extends CharacterBody3D

@export var speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export_range(0.0, 1.0, 0.01) var mask_speed_multiplier := 0.15
@export var acceleration := 24.0
@export var deceleration := 28.0
@export var air_acceleration := 10.0
@export var footstep_stream: AudioStream
@export var footstep_volume_db := -12.0
@export_range(0.0, 10.0, 0.05) var footstep_min_speed := 0.2
@export_range(0.1, 2.0, 0.05) var footstep_pitch_min := 0.8
@export_range(0.1, 2.0, 0.05) var footstep_pitch_max := 1.2
@export var stop_footsteps_when_idle := true
@export var hammer_held_scene: PackedScene = preload("res://environment/hammer/hammer_held.tscn")
@export var hammer_swing_range := 2.0
@export var hammer_swing_cooldown_sec := 0.35

var gravity := 9.8

@onready var camera_rig: CameraRig = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var hud: Control = $MaskUI/HUD
@onready var _footsteps: AudioStreamPlayer3D = get_node_or_null("Footsteps")

var pitch := 0.0
var _mask_on := true
var _cam_input_dir := Vector2.ZERO
var _cam_current_speed := 0.0
var _cam_velocity := Vector3.ZERO
var _cam_grounded := false
var _rng := RandomNumberGenerator.new()
var _held_hammer: Node3D = null
var _hammer_cooldown := 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_toggled(mask_manager.mask_on)

func _process(delta: float) -> void:
	if camera_rig != null:
		camera_rig.update_motion(delta, pitch, _cam_input_dir, _cam_current_speed, _cam_velocity, _cam_grounded)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif GameManager != null and GameManager.has_hammer:
			_use_hammer()

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Yaw (left/right)
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Pitch (up/down)
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -PI/2, PI/2)

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("mask_toggle"):
		var mask_manager := get_node_or_null("/root/MaskManager")
		if mask_manager != null:
			mask_manager.toggle()

	if event.is_action_pressed("debug_toggle_monsters"):
		var debug_manager := get_node_or_null("/root/DebugManager")
		if debug_manager != null:
			debug_manager.toggle_show_monsters()
			flash_message("DEBUG: Monsters %s" % ("visible" if debug_manager.show_monsters else "hidden"))

func _physics_process(delta):
	var prev_pos := global_position
	_hammer_cooldown = maxf(0.0, _hammer_cooldown - delta)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if is_on_floor() and not _mask_on and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	# Movement input
	var input_dir := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
        "ui_down"
	)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := speed if not _mask_on else (speed * mask_speed_multiplier)

	var target_velocity := Vector3(direction.x * current_speed, velocity.y, direction.z * current_speed)
	var accel := acceleration if is_on_floor() else air_acceleration
	var decel := deceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, (accel if absf(target_velocity.x) > absf(velocity.x) else decel) * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, (accel if absf(target_velocity.z) > absf(velocity.z) else decel) * delta)

	move_and_slide()
	_try_play_footsteps(prev_pos)
	_cam_input_dir = input_dir
	_cam_current_speed = current_speed
	_cam_velocity = velocity
	_cam_grounded = is_on_floor()

	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Monster:
			GameManager.player_caught()

func _on_mask_toggled(mask_on: bool) -> void:
	_mask_on = mask_on

func equip_hammer() -> void:
	if _held_hammer != null:
		return
	if hammer_held_scene == null:
		return
	var instance := hammer_held_scene.instantiate()
	_held_hammer = instance as Node3D
	if _held_hammer == null:
		instance.free()
		return
	if camera_rig != null:
		camera_rig.add_child(_held_hammer)

func unequip_hammer() -> void:
	if _held_hammer == null:
		return
	_held_hammer.queue_free()
	_held_hammer = null

func _use_hammer() -> void:
	if _hammer_cooldown > 0.0:
		return
	_hammer_cooldown = maxf(hammer_swing_cooldown_sec, 0.05)

	_animate_hammer_swing()
	_try_hammer_hit()

func _animate_hammer_swing() -> void:
	if _held_hammer == null:
		return
	var start_rot := _held_hammer.rotation
	var tween := create_tween()
	tween.tween_property(_held_hammer, "rotation", start_rot + Vector3(deg_to_rad(-65.0), deg_to_rad(10.0), 0.0), 0.08)
	tween.tween_property(_held_hammer, "rotation", start_rot, 0.12)

func _try_hammer_hit() -> void:
	if _camera == null:
		return

	var world := get_world_3d()
	if world == null:
		return
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state

	var from := _camera.global_position
	var to := from + (-_camera.global_transform.basis.z).normalized() * maxf(hammer_swing_range, 0.1)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [self]

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider") as Object
	if collider == null:
		return

	if collider.has_method("break_with_hammer"):
		collider.call("break_with_hammer", hit)
		return
	if collider.has_method("on_hit_by_hammer"):
		collider.call("on_hit_by_hammer", hit)
		return

func _try_play_footsteps(prev_pos: Vector3) -> void:
	if _footsteps == null:
		return
	if footstep_stream != null:
		_footsteps.stream = footstep_stream
	_footsteps.volume_db = footstep_volume_db

	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var moved := (global_position - prev_pos).length() > 0.0005
	var moving := is_on_floor() and moved and horiz_speed > footstep_min_speed

	if not moving:
		if stop_footsteps_when_idle and _footsteps.playing:
			_footsteps.stop()
		return

	if _footsteps.stream == null:
		return

	if not _footsteps.playing:
		_footsteps.pitch_scale = _rng.randf_range(footstep_pitch_min, footstep_pitch_max)
		_footsteps.play()

func set_interact_prompt(text: String) -> void:
	if hud != null and hud.has_method("set_interact_prompt"):
		hud.set_interact_prompt(text)

func clear_interact_prompt() -> void:
	if hud != null and hud.has_method("clear_interact_prompt"):
		hud.clear_interact_prompt()

func flash_message(text: String) -> void:
	if hud != null and hud.has_method("flash_message"):
		hud.flash_message(text)
