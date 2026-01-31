extends Node3D


const SCREEN_SURFACE := 1
const IMAGE_TEXTURE_PARAM := "image_texture"
const USE_IMAGE_PARAM := "use_image_texture"

@export var on_energy := 3.0
@export var off_energy := 0.0
@export var light_path: NodePath
@export var static_intensity := 0.3
@export var key_image: Texture2D = preload("res://environment/props/tvs_n_items/scenes/key_image.jpg")
@export var key_scene: PackedScene = preload("res://environment/key/key.tscn")
@export var key_spawn_path: NodePath
@export var key_spawn_offset := Vector3(0.0, 0.18, 0.0)
@export var has_key := false

@export var break_fx_scene: PackedScene
@export var break_fx_count := 18
@export var break_fx_lifetime := 0.7
@export var break_fx_speed := 1.8
@export var break_fx_spread := Vector3(0.12, 0.08, 0.12)
@export var break_fx_color := Color(0.9, 0.95, 1.0, 1.0)
@export var interaction_action := "interact"
@export var prompt_with_hammer := "Smash monitor"
@export var prompt_without_hammer := "Need a hammer"

var screen_mat: StandardMaterial3D
var screen_shader: ShaderMaterial
var uses_shader := false
var _broken := false
var _spawned_key: Node3D = null
var _player_in_trigger := false
var _player: Player = null
var _screen_surface := SCREEN_SURFACE
@onready var screen_mesh := $computerScreen as MeshInstance3D
@onready var screen_light := get_node_or_null(light_path) as Light3D
@onready var proximity_area := $ProximityArea as Area3D
@onready var static_noise := $StaticNoisePlayer as AudioStreamPlayer3D
@onready var _key_spawn := get_node_or_null(key_spawn_path) as Node3D

func _ready() -> void:
	var mat := _get_screen_material()
	if mat is ShaderMaterial:
		uses_shader = true
		# Duplicate shader material so each monitor is independent.
		screen_shader = mat.duplicate() as ShaderMaterial
		if screen_shader == null:
			screen_shader = mat
		screen_mesh.set_surface_override_material(_screen_surface, screen_shader)
		screen_shader.set_shader_parameter("static_intensity", static_intensity)
		_apply_key_texture()
	else:
		# Duplicate standard material so each monitor is independent.
		if mat:
			screen_mat = mat.duplicate() as StandardMaterial3D
		else:
			screen_mat = StandardMaterial3D.new()
		screen_mesh.set_surface_override_material(_screen_surface, screen_mat)
		screen_mat.emission_enabled = true
	turn_off()
	
	# Connect proximity area signals
	proximity_area.body_entered.connect(_on_proximity_body_entered)
	proximity_area.body_exited.connect(_on_proximity_body_exited)

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_toggled(mask_manager.mask_on)

func turn_on() -> void:
	if _broken:
		return
	if uses_shader:
		if screen_shader != null:
			screen_shader.set_shader_parameter("power", on_energy)
	else:
		screen_mat.emission_energy_multiplier = on_energy
	if screen_light:
		screen_light.visible = true
	if static_noise:
		static_noise.play()

func turn_off() -> void:
	if uses_shader:
		if screen_shader != null:
			screen_shader.set_shader_parameter("power", off_energy)
	else:
		screen_mat.emission_energy_multiplier = off_energy
	if screen_light:
		screen_light.visible = false
	if static_noise:
		static_noise.stop()


func _on_proximity_body_entered(body: Node3D) -> void:
	if _broken:
		return
	if body is Player:
		_player_in_trigger = true
		_player = body as Player
		_update_prompt()
	turn_on()


func _on_proximity_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_trigger = false
		if _player != null:
			_player.clear_interact_prompt()
		_player = null
	turn_off()

func break_with_hammer(_hit: Dictionary = {}) -> void:
	_try_break()

func reset_pickup() -> void:
	_broken = false
	if _spawned_key != null:
		_spawned_key.queue_free()
		_spawned_key = null
	_player_in_trigger = false
	if _player != null:
		_player.clear_interact_prompt()
	_player = null
	if proximity_area != null:
		proximity_area.set_deferred("monitoring", true)
	turn_off()

func _try_break() -> void:
	if _broken:
		return
	if not GameManager.has_hammer:
		if _player != null:
			_player.flash_message(prompt_without_hammer)
		return
	_broken = true
	turn_off()
	if uses_shader:
		if screen_shader != null:
			screen_shader.set_shader_parameter(USE_IMAGE_PARAM, false)
	if proximity_area != null:
		proximity_area.set_deferred("monitoring", false)
	_spawn_break_fx()
	_drop_key()
	_update_prompt()

func _on_mask_toggled(mask_on: bool) -> void:
	if not uses_shader:
		if screen_mat == null:
			return
		if _broken:
			screen_mat.albedo_texture = null
			screen_mat.emission_texture = null
			return
		if mask_on and has_key and key_image != null:
			screen_mat.albedo_texture = key_image
			screen_mat.emission_texture = key_image
		else:
			screen_mat.albedo_texture = null
			screen_mat.emission_texture = null
		return
	if _broken:
		if screen_shader != null:
			screen_shader.set_shader_parameter(USE_IMAGE_PARAM, false)
		return
	_apply_key_texture()
	if screen_shader != null:
		screen_shader.set_shader_parameter(USE_IMAGE_PARAM, mask_on and has_key and key_image != null)

func _process(_delta: float) -> void:
	if _broken:
		return
	if not _player_in_trigger or _player == null:
		return
	_update_prompt()
	if not Input.is_action_just_pressed(interaction_action):
		return
	_try_break()

func _update_prompt() -> void:
	if _player == null:
		return
	if _broken or not _player_in_trigger:
		_player.clear_interact_prompt()
		return
	if not GameManager.has_hammer:
		_player.set_interact_prompt("%s (E)" % prompt_without_hammer)
	else:
		_player.set_interact_prompt("%s (E)" % prompt_with_hammer)

func _apply_key_texture() -> void:
	if not uses_shader:
		return
	if key_image == null:
		return
	if screen_shader != null:
		screen_shader.set_shader_parameter(IMAGE_TEXTURE_PARAM, key_image)

func _get_screen_material() -> Material:
	_screen_surface = SCREEN_SURFACE
	if screen_mesh == null:
		return null
	var direct := screen_mesh.get_active_material(_screen_surface)
	if direct != null:
		return direct
	var mesh := screen_mesh.mesh
	if mesh == null:
		return null
	for i in range(mesh.get_surface_count()):
		var candidate := screen_mesh.get_active_material(i)
		if candidate is ShaderMaterial or candidate is StandardMaterial3D:
			_screen_surface = i
			return candidate
	return null

func _drop_key() -> void:
	if not has_key:
		return
	if key_scene == null:
		return
	if _spawned_key != null:
		return
	var instance := key_scene.instantiate()
	var key := instance as Node3D
	if key == null:
		instance.free()
		return
	var parent_node := get_parent() if get_parent() != null else get_tree().root
	parent_node.add_child(key)
	key.global_transform = _get_key_spawn_transform()
	_spawned_key = key

func _get_key_spawn_transform() -> Transform3D:
	if _key_spawn != null:
		return _key_spawn.global_transform
	return global_transform.translated_local(key_spawn_offset)

func _spawn_break_fx() -> void:
	if not is_inside_tree():
		return
	var parent_node := get_parent() if get_parent() != null else get_tree().root
	var origin := global_position
	if screen_mesh != null and screen_mesh.is_inside_tree():
		origin = screen_mesh.global_position

	if break_fx_scene != null:
		var instance := break_fx_scene.instantiate()
		var fx := instance as Node3D
		if fx == null:
			instance.free()
			return
		parent_node.add_child(fx)
		fx.global_position = origin
		return

	var fx_root := Node3D.new()
	fx_root.name = "BreakFx"
	fx_root.global_position = origin
	parent_node.add_child(fx_root)

	var particles := GPUParticles3D.new()
	particles.amount = break_fx_count
	particles.lifetime = break_fx_lifetime
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emitting = true

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = break_fx_spread
	process.gravity = Vector3(0.0, -3.0, 0.0)
	process.direction = Vector3(0.0, 0.4, -1.0).normalized()
	process.initial_velocity_min = break_fx_speed * 0.6
	process.initial_velocity_max = break_fx_speed
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.albedo_color = break_fx_color
	quad_mat.emission_enabled = true
	quad_mat.emission = break_fx_color
	quad.material = quad_mat
	particles.draw_pass_1 = quad

	fx_root.add_child(particles)

	var timer := get_tree().create_timer(break_fx_lifetime + 0.2)
	timer.timeout.connect(func() -> void:
		if fx_root != null:
			fx_root.queue_free()
	)
