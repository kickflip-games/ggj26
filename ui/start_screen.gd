class_name StartScreen
extends CanvasLayer

signal start_game
signal quit_game

@onready var _start_button: Button = $Root/Panel/Content/Buttons/StartButton
@onready var _quit_button: Button = $Root/Panel/Content/Buttons/QuitButton

func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	
	call_deferred("_focus_start")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_start_pressed()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_quit_pressed()
		return

func _on_start_pressed() -> void:
	print("StartScreen: Start button pressed, emitting start_game signal")
	start_game.emit()

func _on_quit_pressed() -> void:
	print("StartScreen: Quit button pressed, emitting quit_game signal")
	quit_game.emit()

func _focus_start() -> void:
	if is_instance_valid(_start_button):
		_start_button.grab_focus()
