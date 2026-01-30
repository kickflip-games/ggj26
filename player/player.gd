class_name Player
extends CharacterBody3D

@export var speed := 6.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export_range(0.0, 1.0, 0.01) var mask_speed_multiplier := 0.15

var gravity := 9.8

@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Control = $MaskUI/HUD

var pitch := 0.0
var _mask_on := true

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_toggled(mask_manager.mask_on)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	if camera_rig != null:
		camera_rig.update_motion(delta, pitch, input_dir, current_speed, velocity, is_on_floor())

	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Monster:
			GameManager.player_caught()

func _on_mask_toggled(mask_on: bool) -> void:
	_mask_on = mask_on

func set_interact_prompt(text: String) -> void:
	if hud != null and hud.has_method("set_interact_prompt"):
		hud.set_interact_prompt(text)

func clear_interact_prompt() -> void:
	if hud != null and hud.has_method("clear_interact_prompt"):
		hud.clear_interact_prompt()

func flash_message(text: String) -> void:
	if hud != null and hud.has_method("flash_message"):
		hud.flash_message(text)
