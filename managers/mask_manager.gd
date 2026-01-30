extends Node

signal mask_toggled(mask_on: bool)
signal mask_energy_changed(current: float, max: float, ratio: float)

@export var start_mask_on := false
@export var max_mask_energy := 6.0
@export var drain_per_second := 1.0
@export var regen_per_second := 0.5
@export var auto_disable_on_empty := true

var _mask_on := false
var mask_on: bool:
	get:
		return _mask_on
	set(value):
		_set_mask_on(value)

var mask_energy := 0.0

func _ready() -> void:
	_ensure_input_map()
	mask_energy = max_mask_energy
	_set_mask_on(start_mask_on)
	_emit_energy()

func toggle() -> void:
	if _mask_on:
		_set_mask_on(false)
		return
	if mask_energy <= 0.001:
		return
	_set_mask_on(true)

func _set_mask_on(value: bool) -> void:
	if _mask_on == value:
		return
	_mask_on = value
	mask_toggled.emit(_mask_on)

func _ensure_input_map() -> void:
	# Movement: add WASD in addition to the built-in arrow keys.
	_ensure_key(&"ui_left", KEY_A)
	_ensure_key(&"ui_right", KEY_D)
	_ensure_key(&"ui_up", KEY_W)
	_ensure_key(&"ui_down", KEY_S)
	_ensure_key(&"ui_accept", KEY_SPACE)

	# Core gameplay actions.
	_ensure_key(&"mask_toggle", KEY_F)
	_ensure_key(&"interact", KEY_E)

	# Debug.
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

func refill_energy() -> void:
	mask_energy = max_mask_energy
	_emit_energy()

func _process(delta: float) -> void:
	if max_mask_energy <= 0.0:
		return

	if mask_energy > max_mask_energy:
		mask_energy = max_mask_energy

	var prev := mask_energy

	if _mask_on:
		mask_energy = max(0.0, mask_energy - drain_per_second * delta)
		if auto_disable_on_empty and mask_energy <= 0.001:
			_set_mask_on(false)
	else:
		mask_energy = min(max_mask_energy, mask_energy + regen_per_second * delta)

	if absf(prev - mask_energy) > 0.0001:
		_emit_energy()

func _emit_energy() -> void:
	var ratio := 0.0
	if max_mask_energy > 0.0:
		ratio = clampf(mask_energy / max_mask_energy, 0.0, 1.0)
	mask_energy_changed.emit(mask_energy, max_mask_energy, ratio)
