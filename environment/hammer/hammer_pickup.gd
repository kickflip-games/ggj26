class_name HammerPickup
extends Node3D

@export var model_offset := Vector3.ZERO
@export var model_rotation_degrees := Vector3.ZERO
@export var model_scale := Vector3.ONE

@onready var pickup_area: Area3D = $PickupArea
@onready var model: Node3D = get_node_or_null("Model")

var _collected := false

func _ready() -> void:
	_apply_model_transform()
	pickup_area.body_entered.connect(_on_body_entered)
	visible = not _collected

func reset_pickup() -> void:
	_collected = false
	visible = true
	pickup_area.set_deferred("monitoring", true)

func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if not (body is Player):
		return

	_collected = true
	GameManager.has_hammer = true
	if body.has_method("equip_hammer"):
		body.equip_hammer()
	
	# Display pickup message
	if body.has_method("flash_message_hud"):
		body.flash_message_hud("Hammer picked up. You can now smash monitors")

	visible = false
	pickup_area.set_deferred("monitoring", false)

func _apply_model_transform() -> void:
	if model == null:
		return
	model.position = model_offset
	model.rotation_degrees = model_rotation_degrees
	model.scale = model_scale
