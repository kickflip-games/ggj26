extends Node3D

@export var lifetime := 0.7
@export var auto_destroy := true

@onready var particles := $GPUParticles3D as GPUParticles3D

func _ready() -> void:
	if particles != null:
		particles.emitting = true
	
	if auto_destroy:
		var timer := get_tree().create_timer(lifetime + 0.2)
		timer.timeout.connect(queue_free)
