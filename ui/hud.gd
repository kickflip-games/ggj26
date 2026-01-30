extends Control

@export var message_seconds := 1.2

@onready var _interact_label: Label = $InteractLabel
@onready var _message_label: Label = $MessageLabel
@onready var _key_label: Label = $KeyLabel

var _message_tween: Tween = null

func _ready() -> void:
	_interact_label.text = ""
	_interact_label.visible = false

	_message_label.text = ""
	_message_label.visible = false

	_key_label.visible = GameManager.has_key
	GameManager.key_changed.connect(_on_key_changed)

func set_interact_prompt(text: String) -> void:
	_interact_label.text = text
	_interact_label.visible = not text.is_empty()

func clear_interact_prompt() -> void:
	set_interact_prompt("")

func flash_message(text: String) -> void:
	if _message_tween != null:
		_message_tween.kill()
		_message_tween = null
	_message_label.text = text
	_message_label.visible = true
	_message_label.modulate.a = 1.0

	_message_tween = create_tween()
	_message_tween.tween_interval(message_seconds)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.2)
	_message_tween.tween_callback(func(): _message_label.visible = false)

func _on_key_changed(has_key: bool) -> void:
	_key_label.visible = has_key
