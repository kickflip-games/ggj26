class_name Player
extends CharacterBody3D

@export var speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export_range(0.1, 1.0, 0.01) var mask_speed_multiplier := 0.9
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
@export var death_impact_sound: AudioStream = preload("res://player/player_caught.mp3")
@export var death_bite_sound: AudioStream
@export_range(0.05, 0.4, 0.01) var death_impact_duration := 0.1
@export_range(0.1, 1.0, 0.01) var death_pull_duration := 0.4
@export_range(0.05, 0.6, 0.01) var death_bite_duration := 0.2
@export_range(0.1, 0.6, 0.01) var death_fade_duration := 0.3
@export_range(0.05, 0.3, 0.01) var death_fade_out_duration := 0.12
@export_range(-30.0, 0.0, 0.1) var death_pull_fov_delta := -6.0
@export_range(0.0, 1.5, 0.01) var death_pull_stop_distance := 0.85
@export_range(0.0, 10.0, 0.1) var death_wobble_deg := 2.0
@export_range(0.0, 6.0, 0.1) var death_wobble_cycles := 2.0
@export_range(-15.0, 15.0, 0.1) var death_jolt_pitch_deg := -4.0
@export_range(0.1, 2.0, 0.05) var death_pull_forward_fallback := 0.8
@export var death_marker_offset_local := Vector3(0.0, 0.4, 0.0)
@export var mask_equip_scene: PackedScene = preload("res://player/Clown Mask.glb")
@export var mask_equip_start_local := Vector3(0.0, -0.6, -0.2)
@export var mask_equip_end_local := Vector3(0.0, -0.07, -0.12)
@export var mask_equip_rotation_deg := Vector3(0.0, 90.0, 0.0)
@export var mask_equip_scale := Vector3(0.68, 0.68, 0.68)
@export_range(0.05, 2.0, 0.01) var mask_equip_slide_duration := 0.4
@export_range(0.0, 1.0, 0.01) var mask_shader_lead_time := 0.2
@export var mask_equip_pull_offset := Vector3(0.0, 0.0, 0.2)
@export_range(0.05, 0.6, 0.01) var mask_equip_pull_duration := 0.12

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
var _death_sequence_active := false
var _death_fade_layer: CanvasLayer = null
var _death_fade_rect: ColorRect = null
var _death_fade_alpha := 0.0
var _death_base_fov := 70.0
var _death_wobble_base_cam_rot := Vector3.ZERO
var _mask_initialized := false
var _mask_equip_active := false

func _ready():
	_ensure_input_map()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	if _camera != null:
		_death_base_fov = _camera.fov
	if GameManager != null and GameManager.player == null:
		GameManager.player = self
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_toggled(mask_manager.mask_on)
	_mask_initialized = true

func _process(delta: float) -> void:
	if _death_sequence_active:
		return
	if camera_rig != null:
		camera_rig.update_motion(delta, pitch, _cam_input_dir, _cam_current_speed, _cam_velocity, _cam_grounded)

func _input(event):
	if _death_sequence_active:
		return
	if event.is_action_pressed("interact"):
		if GameManager != null and GameManager.has_hammer:
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
			if mask_manager.mask_on:
				_request_mask_unequip(mask_manager)
			else:
				_request_mask_equip(mask_manager)

	if event.is_action_pressed("debug_toggle_monsters"):
		var debug_manager := get_node_or_null("/root/DebugManager")
		if debug_manager != null:
			debug_manager.toggle_show_monsters()
			flash_message("DEBUG: Monsters %s" % ("visible" if debug_manager.show_monsters else "hidden"))

func _physics_process(delta):
	if _death_sequence_active:
		velocity = Vector3.ZERO
		return
	var prev_pos := global_position
	_hammer_cooldown = maxf(0.0, _hammer_cooldown - delta)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	# Movement input
	var input_dir := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
        "ui_down"
	)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed_scale := 1.0
	if _mask_on:
		speed_scale = maxf(mask_speed_multiplier, 0.1)
	var current_speed := speed * speed_scale

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
			GameManager.player_caught(collider)

func _on_mask_toggled(mask_on: bool) -> void:
	_mask_on = mask_on

func start_death_sequence(captor: Node3D) -> void:
	if _death_sequence_active:
		return
	_death_sequence_active = true
	_cam_input_dir = Vector2.ZERO
	_cam_current_speed = 0.0
	_cam_velocity = Vector3.ZERO
	_cam_grounded = true
	if _footsteps != null:
		_footsteps.stop()

	if _camera == null or camera_rig == null:
		_play_death_sound(death_impact_sound)
		var fallback_fade := _ensure_death_fade()
		_set_death_fade_alpha(1.0)
		if GameManager != null:
			GameManager.finish_death_sequence()
		if fallback_fade != null:
			_clear_death_fade()
		_death_sequence_active = false
		return

	var base_fov := _camera.fov if _camera != null else _death_base_fov
	_play_death_sound(death_impact_sound)
	var impact_half := maxf(death_impact_duration * 0.5, 0.01)
	var impact_tween := create_tween()
	impact_tween.tween_property(
		_camera,
		"rotation:x",
		_camera.rotation.x + deg_to_rad(death_jolt_pitch_deg),
		impact_half
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(
		_camera,
		"rotation:x",
		_camera.rotation.x,
		impact_half
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await impact_tween.finished
	var marker := _get_death_marker(captor)
	if marker != null:
		if camera_rig != null:
			camera_rig.reset_pose()
		_apply_death_target_rotation(marker.global_rotation)
	else:
		_face_captor(captor)
	_death_wobble_base_cam_rot = _camera.rotation

	var target_pos := _compute_death_pull_target(captor)
	if marker != null:
		target_pos = marker.global_position + (marker.global_transform.basis * death_marker_offset_local)
	var pull_tween := create_tween()
	pull_tween.set_parallel(true)
	pull_tween.tween_property(
		_camera,
		"global_position",
		target_pos,
		maxf(death_pull_duration, 0.05)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_fov := clampf(base_fov + death_pull_fov_delta, 10.0, 160.0)
	pull_tween.tween_property(
		_camera,
		"fov",
		target_fov,
		maxf(death_pull_duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pull_tween.tween_method(_set_death_wobble, 0.0, 1.0, maxf(death_pull_duration, 0.05))
	await pull_tween.finished

	if captor != null and captor.has_method("play_bite"):
		captor.call("play_bite")
	_play_death_sound(death_bite_sound)
	if death_bite_duration > 0.0 and get_tree() != null:
		await get_tree().create_timer(death_bite_duration).timeout

	var fade_rect := _ensure_death_fade()
	if fade_rect != null:
		var fade_tween := create_tween()
		fade_tween.tween_method(_set_death_fade_alpha, _death_fade_alpha, 1.0, maxf(death_fade_duration, 0.05)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await fade_tween.finished

	if camera_rig != null:
		camera_rig.reset_pose()
	if _camera != null:
		_camera.fov = base_fov

	if GameManager != null:
		GameManager.finish_death_sequence()

	if fade_rect != null:
		_set_death_fade_alpha(0.0)
		_clear_death_fade()

	_death_sequence_active = false

func _compute_death_pull_target(captor: Node3D) -> Vector3:
	if _camera == null:
		return global_position
	var start := _camera.global_position
	if captor != null:
		var focus := _get_captor_focus_position(captor)
		var from_focus := start - focus
		if from_focus.length_squared() > 0.0001:
			return focus + from_focus.normalized() * maxf(death_pull_stop_distance, 0.05)
		return focus
	var forward := -_camera.global_transform.basis.z
	if forward.length_squared() < 0.0001:
		forward = -global_transform.basis.z
	return start + forward.normalized() * maxf(death_pull_forward_fallback, 0.1)

func _get_captor_focus_position(captor: Node3D) -> Vector3:
	if captor == null:
		if _camera == null:
			return global_position
		return _camera.global_position + (-_camera.global_transform.basis.z).normalized() * maxf(death_pull_forward_fallback, 0.1)
	if captor.has_method("get_death_focus_position"):
		return captor.call("get_death_focus_position")
	return captor.global_position

func _get_death_marker(captor: Node3D) -> Node3D:
	if captor == null:
		return null
	if captor.has_method("get_death_sequence_marker"):
		return captor.call("get_death_sequence_marker") as Node3D
	var direct := captor.get_node_or_null(^"death_sequence_position") as Node3D
	if direct == null:
		direct = captor.find_child("death_sequence_position", true, false) as Node3D
	return direct

func _apply_death_target_rotation(target_rotation: Vector3) -> void:
	if _camera == null:
		return
	_camera.global_rotation = target_rotation
	pitch = clampf(_camera.rotation.x, -PI / 2.0, PI / 2.0)


func _face_captor(captor: Node3D) -> void:
	if _camera == null:
		return
	var focus := _get_captor_focus_position(captor)
	var from := _camera.global_position
	var to_focus := focus - from
	if to_focus.length_squared() < 0.0001:
		return
	var dir := to_focus.normalized()
	var horiz := Vector3(dir.x, 0.0, dir.z)
	if horiz.length_squared() > 0.0001:
		var yaw := atan2(-horiz.x, -horiz.z)
		rotation.y = yaw
	var horiz_len := maxf(horiz.length(), 0.001)
	var target_pitch := -atan2(dir.y, horiz_len)
	pitch = clampf(target_pitch, -PI / 2.0, PI / 2.0)
	var cam_rot := _camera.rotation
	cam_rot.x = pitch
	_camera.rotation = cam_rot

func _set_death_wobble(t: float) -> void:
	if _camera == null:
		return
	var wobble := deg_to_rad(death_wobble_deg)
	var phase := t * maxf(death_wobble_cycles, 0.0) * TAU
	var rot := _death_wobble_base_cam_rot
	rot.z += sin(phase) * wobble
	_camera.rotation = rot

func _ensure_death_fade() -> ColorRect:
	if _death_fade_rect != null and is_instance_valid(_death_fade_rect):
		return _death_fade_rect
	if get_tree() == null or get_tree().root == null:
		return null
	var layer := CanvasLayer.new()
	layer.layer = 200
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	_death_fade_layer = layer
	_death_fade_rect = rect
	_set_death_fade_alpha(0.0)
	return rect

func _set_death_fade_alpha(value: float) -> void:
	_death_fade_alpha = clampf(value, 0.0, 1.0)
	if _death_fade_rect == null:
		return
	var col := _death_fade_rect.color
	col.a = _death_fade_alpha
	_death_fade_rect.color = col

func _request_mask_equip(mask_manager: Node) -> void:
	if _mask_equip_active:
		return
	if mask_manager == null:
		return
	if mask_manager.mask_energy <= 0.001:
		return
	_play_mask_equip_sequence(mask_manager)

func _request_mask_unequip(mask_manager: Node) -> void:
	if _mask_equip_active:
		return
	if mask_manager == null:
		return
	_play_mask_unequip_sequence(mask_manager)

func _play_mask_equip_sequence(mask_manager: Node) -> void:
	if _mask_equip_active:
		return
	if _camera == null or mask_equip_scene == null:
		return
	_mask_equip_active = true
	var instance := mask_equip_scene.instantiate()
	var mask_node := instance as Node3D
	if mask_node == null:
		instance.free()
		_mask_equip_active = false
		return
	_camera.add_child(mask_node)
	mask_node.position = mask_equip_start_local
	mask_node.rotation_degrees = mask_equip_rotation_deg
	mask_node.scale = mask_equip_scale
	_apply_mask_black_material(mask_node)

	var slide_tween := create_tween()
	slide_tween.tween_property(
		mask_node,
		"position",
		mask_equip_end_local,
		maxf(mask_equip_slide_duration, 0.05)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if mask_manager != null:
		var shader_delay := maxf(mask_equip_slide_duration - mask_shader_lead_time, 0.0)
		if shader_delay > 0.0 and get_tree() != null:
			await get_tree().create_timer(shader_delay).timeout
		mask_manager.mask_on = true

	await slide_tween.finished

	var pull_tween := create_tween()
	pull_tween.tween_property(
		mask_node,
		"position",
		mask_equip_end_local + mask_equip_pull_offset,
		maxf(mask_equip_pull_duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await pull_tween.finished

	if mask_node != null and is_instance_valid(mask_node):
		mask_node.queue_free()

	_mask_equip_active = false

func _play_mask_unequip_sequence(mask_manager: Node) -> void:
	if _mask_equip_active:
		return
	if _camera == null or mask_equip_scene == null:
		return
	_mask_equip_active = true
	var instance := mask_equip_scene.instantiate()
	var mask_node := instance as Node3D
	if mask_node == null:
		instance.free()
		_mask_equip_active = false
		return
	_camera.add_child(mask_node)
	mask_node.position = mask_equip_end_local + mask_equip_pull_offset
	mask_node.rotation_degrees = mask_equip_rotation_deg
	mask_node.scale = mask_equip_scale
	_apply_mask_black_material(mask_node)

	var pull_back := create_tween()
	pull_back.tween_property(
		mask_node,
		"position",
		mask_equip_end_local,
		maxf(mask_equip_pull_duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await pull_back.finished

	var slide_down := create_tween()
	slide_down.tween_property(
		mask_node,
		"position",
		mask_equip_start_local,
		maxf(mask_equip_slide_duration, 0.05)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if mask_manager != null:
		var shader_delay := maxf(mask_equip_slide_duration - mask_shader_lead_time, 0.0)
		if shader_delay > 0.0 and get_tree() != null:
			await get_tree().create_timer(shader_delay).timeout
		mask_manager.mask_on = false

	await slide_down.finished

	if mask_node != null and is_instance_valid(mask_node):
		mask_node.queue_free()

	_mask_equip_active = false

func _apply_mask_black_material(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = null
		mat.roughness = 0.85
		mesh_instance.material_override = mat
	for child in root.get_children():
		_apply_mask_black_material(child)

func _clear_death_fade() -> void:
	if _death_fade_layer != null:
		_death_fade_layer.queue_free()
	_death_fade_layer = null
	_death_fade_rect = null
	_death_fade_alpha = 0.0

func _play_death_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _ensure_input_map() -> void:
	_ensure_key(&"ui_left", KEY_A)
	_ensure_key(&"ui_right", KEY_D)
	_ensure_key(&"ui_up", KEY_W)
	_ensure_key(&"ui_down", KEY_S)
	_ensure_key(&"ui_accept", KEY_SPACE)
	_ensure_key(&"mask_toggle", KEY_F)
	_ensure_key(&"interact", KEY_E)
	_ensure_key(&"debug_toggle_monsters", KEY_F1)
	_ensure_key(&"debug_toggle_monsters", KEY_EQUAL)

func _ensure_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).keycode == keycode:
			return

	var new_event := InputEventKey.new()
	new_event.keycode = keycode
	InputMap.action_add_event(action, new_event)

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

	print("[Player] Hammer swung")
	_animate_hammer_swing()
	_try_hammer_hit()

func _animate_hammer_swing() -> void:
	if _held_hammer == null:
		return
	var start_rot := _held_hammer.rotation
	var start_pos := _held_hammer.position
	var tween := create_tween()
	# Wind-up: pull back to the right and slightly back.
	tween.tween_property(
		_held_hammer,
		"rotation",
		start_rot + Vector3(deg_to_rad(30.0), deg_to_rad(-20.0), deg_to_rad(12.0)),
		0.12
	)
	tween.tween_property(
		_held_hammer,
		"position",
		start_pos + Vector3(-0.05, 0.12, 0.18),
		0.12
	)
	# Swing: arc forward to the left.
	tween.tween_property(
		_held_hammer,
		"rotation",
		start_rot + Vector3(deg_to_rad(-40.0), deg_to_rad(35.0), deg_to_rad(-8.0)),
		0.16
	)
	tween.tween_property(
		_held_hammer,
		"position",
		start_pos + Vector3(-0.26, 0.0, -0.22),
		0.16
	)
	# Return to rest.
	tween.tween_property(_held_hammer, "rotation", start_rot, 0.12)
	tween.tween_property(_held_hammer, "position", start_pos, 0.12)

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
