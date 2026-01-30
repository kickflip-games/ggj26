extends Control

@onready var _bar: ProgressBar = $ProgressBar

func _ready() -> void:
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.show_percentage = false

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_energy_changed.connect(_on_mask_energy_changed)
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_energy_changed(mask_manager.mask_energy, mask_manager.max_mask_energy, mask_manager.mask_energy / max(0.0001, mask_manager.max_mask_energy))
		_on_mask_toggled(mask_manager.mask_on)

func _on_mask_energy_changed(_current: float, _max: float, ratio: float) -> void:
	_bar.value = clampf(ratio, 0.0, 1.0)

func _on_mask_toggled(mask_on: bool) -> void:
	_bar.modulate = Color(0.9, 0.9, 1.0, 1.0) if mask_on else Color(0.65, 0.65, 0.65, 1.0)
