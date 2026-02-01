extends Node

var _start_screen: StartScreen = null
@export var game_scene_path := "res://main/main_v2.tscn"

func _ready() -> void:
	print("MainMenu: Initializing main menu")
	var start_screen_scene: PackedScene = preload("res://ui/start_screen.tscn")
	_start_screen = start_screen_scene.instantiate() as StartScreen
	add_child(_start_screen)
	
	_start_screen.start_game.connect(_on_start_game)
	_start_screen.quit_game.connect(_on_quit_game)
	print("MainMenu: Signals connected")

func _on_start_game() -> void:
	print("MainMenu: Start game signal received")
	print("MainMenu: Attempting to load scene: ", game_scene_path)
	if _start_screen:
		_start_screen.queue_free()
		_start_screen = null
	get_tree().change_scene_to_file(game_scene_path)

func _on_quit_game() -> void:
	get_tree().quit()
