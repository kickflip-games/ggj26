extends StaticBody3D

@export var target_path: NodePath

func break_with_hammer(hit: Dictionary = {}) -> void:
	var target := _resolve_target()
	if target == null:
		return
	if target.has_method("break_with_hammer"):
		target.call("break_with_hammer", hit)
		return
	if target.has_method("on_hit_by_hammer"):
		target.call("on_hit_by_hammer", hit)

func _resolve_target() -> Node:
	if target_path != NodePath():
		var node := get_node_or_null(target_path)
		if node != null:
			return node
	return get_parent()
