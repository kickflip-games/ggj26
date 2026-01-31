class_name EndScreen
extends CanvasLayer

signal primary_action
signal secondary_action

@export var title_text := "You Died."
@export var subtitle_text := ""
@export var primary_text := "RETRY"
@export var secondary_text := "QUIT"
@export var show_secondary := true

@onready var _title: Label = $Root/Panel/Content/Title
@onready var _primary: Button = $Root/Panel/Content/Buttons/Primary
@onready var _secondary: Button = $Root/Panel/Content/Buttons/Secondary

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_update_ui()

	_primary.pressed.connect(func():
		primary_action.emit()
	)
	_secondary.pressed.connect(func():
		secondary_action.emit()
	)

	call_deferred("_focus_primary")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		primary_action.emit()
		return
	if show_secondary and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		secondary_action.emit()
		return

func _update_ui() -> void:
	_title.text = title_text
	_primary.text = primary_text
	_secondary.text = secondary_text
	_secondary.visible = show_secondary

func _focus_primary() -> void:
	if is_instance_valid(_primary):
		_primary.grab_focus()
