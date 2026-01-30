extends Node

signal show_monsters_changed(show: bool)

var _show_monsters := false
var show_monsters: bool:
	get:
		return _show_monsters
	set(value):
		if _show_monsters == value:
			return
		_show_monsters = value
		show_monsters_changed.emit(_show_monsters)

func toggle_show_monsters() -> void:
	show_monsters = not show_monsters
