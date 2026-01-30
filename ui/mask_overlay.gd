extends ColorRect

@export var fade_seconds := 0.12

@export var effect_scale := 1.06
@export var effect_border_mask := 2.0
@export var effect_strength := 10.0
@export var effect_tint := Color(0.55, 0.80, 1.0, 1.0)
@export var effect_tint_strength := 0.14
@export var mask_on_alpha := 1.0

var _alpha := 0.0
var _tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchors_preset = Control.PRESET_FULL_RECT
	color = Color(1, 1, 1, 1)

	_apply_shader_params()
	_set_alpha(0.0)

	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null:
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		_on_mask_toggled(mask_manager.mask_on)

func _on_mask_toggled(mask_on: bool) -> void:
	_tween_alpha(mask_on_alpha if mask_on else 0.0)

func _tween_alpha(target: float) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _alpha, target, fade_seconds)

func _set_alpha(value: float) -> void:
	_alpha = clampf(value, 0.0, 1.0)
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("alpha", _alpha)

func _apply_shader_params() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("scale", effect_scale)
	mat.set_shader_parameter("border_mask", effect_border_mask)
	mat.set_shader_parameter("strength", effect_strength)
	mat.set_shader_parameter("tint", effect_tint)
	mat.set_shader_parameter("tint_strength", effect_tint_strength)
