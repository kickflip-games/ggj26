extends Node3D


const SCREEN_SURFACE := 1

@export var on_energy := 3.0
@export var off_energy := 0.0
@export var light_path: NodePath
@export var static_intensity := 0.3

var screen_mat: StandardMaterial3D
var uses_shader := false
@onready var screen_mesh := $computerScreen as MeshInstance3D
@onready var screen_light := get_node_or_null(light_path) as Light3D
@onready var proximity_area := $ProximityArea as Area3D
@onready var static_noise := $StaticNoisePlayer as AudioStreamPlayer3D

func _ready() -> void:
	var mat := screen_mesh.get_active_material(SCREEN_SURFACE)
	if mat is ShaderMaterial:
		uses_shader = true
		screen_mesh.set_instance_shader_parameter("static_intensity", static_intensity)
	else:
		# Duplicate standard material so each monitor is independent.
		if mat:
			screen_mat = mat.duplicate() as StandardMaterial3D
		else:
			screen_mat = StandardMaterial3D.new()
		screen_mesh.set_surface_override_material(SCREEN_SURFACE, screen_mat)
		screen_mat.emission_enabled = true
	turn_off()
	
	# Connect proximity area signals
	proximity_area.body_entered.connect(_on_proximity_body_entered)
	proximity_area.body_exited.connect(_on_proximity_body_exited)

func turn_on() -> void:
	if uses_shader:
		screen_mesh.set_instance_shader_parameter("power", on_energy)
	else:
		screen_mat.emission_energy_multiplier = on_energy
	if screen_light:
		screen_light.visible = true
	if static_noise:
		static_noise.play()

func turn_off() -> void:
	if uses_shader:
		screen_mesh.set_instance_shader_parameter("power", off_energy)
	else:
		screen_mat.emission_energy_multiplier = off_energy
	if screen_light:
		screen_light.visible = false
	if static_noise:
		static_noise.stop()


func _on_proximity_body_entered(body: Node3D) -> void:
	turn_on()


func _on_proximity_body_exited(body: Node3D) -> void:
	turn_off()
