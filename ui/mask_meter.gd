extends Control

@onready var _bar: ProgressBar = $ProgressBar

@export_range(0.05, 1.0, 0.01) var low_energy_threshold := 0.2
@export_range(0.5, 8.0, 0.1) var low_pulse_speed := 3.0
@export_range(0.0, 1.0, 0.05) var low_pulse_strength := 0.7
@export var low_pulse_color := Color(1.0, 0.2, 0.2, 1.0)
@export var normal_on_color := Color(0.9, 0.9, 1.0, 1.0)
@export var normal_off_color := Color(0.65, 0.65, 0.65, 1.0)

var _mask_on := true
var _ratio := 1.0
var _low_active := false
var _pulse_phase := 0.0

func _ready() -> void:
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.show_percentage = false
	set_process(false)

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_energy_changed.connect(_on_mask_energy_changed)
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_energy_changed(mask_manager.mask_energy, mask_manager.max_mask_energy, mask_manager.mask_energy / max(0.0001, mask_manager.max_mask_energy))
		_on_mask_toggled(mask_manager.mask_on)
	else:
		_apply_base_color()

func _on_mask_energy_changed(_current: float, _max: float, ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_bar.value = _ratio
	_update_low_state()

func _on_mask_toggled(mask_on: bool) -> void:
	_mask_on = mask_on
	_update_low_state()

func _process(delta: float) -> void:
	if not _low_active:
		return
	_pulse_phase += delta * low_pulse_speed * TAU
	_apply_pulse(_pulse_phase)

func _update_low_state() -> void:
	var should_pulse := _ratio <= low_energy_threshold
	if should_pulse != _low_active:
		_low_active = should_pulse
		_pulse_phase = 0.0
		set_process(_low_active)
	if _low_active:
		_apply_pulse(_pulse_phase)
	else:
		_apply_base_color()

func _apply_base_color() -> void:
	_bar.modulate = normal_on_color if _mask_on else normal_off_color

func _apply_pulse(phase: float) -> void:
	var t := (sin(phase) + 1.0) * 0.5
	var base := normal_on_color if _mask_on else normal_off_color
	var blend := t * low_pulse_strength
	_bar.modulate = base.lerp(low_pulse_color, blend)
