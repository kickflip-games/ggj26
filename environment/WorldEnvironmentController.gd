extends WorldEnvironment

@export_range(-5.0, 5.0, 0.01) var mask_background_energy_boost := 0.25

var _base_background_energy_multiplier := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var env := environment
	if env == null:
		return

	_base_background_energy_multiplier = env.background_energy_multiplier
	_connect_mask_manager()


func _connect_mask_manager() -> void:
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null and mask_manager.has_signal("mask_toggled"):
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		if mask_manager.has_method("get"):
			_on_mask_toggled(mask_manager.mask_on)


func _on_mask_toggled(mask_on: bool) -> void:
	var env := environment
	if env == null:
		return

	var target := _base_background_energy_multiplier
	if mask_on:
		target += mask_background_energy_boost
	env.background_energy_multiplier = max(0.0, target)
