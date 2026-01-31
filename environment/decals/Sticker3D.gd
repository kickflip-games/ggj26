@tool
extends Node3D

const LOCAL_FRONT := Vector3(0.0, 0.0, 1.0) # QuadMesh front face points +Z.

var _texture: Texture2D
var _size_meters := Vector2(1.0, 1.0)
var _mode := "WALL"
var _offset_meters := 0.003
var _alpha_mode := "SCISSOR"
var _alpha_scissor_threshold := 0.5
var _unshaded := false
var _double_sided := true
var _emissive := false
var _emission_color := Color(1, 1, 1)
var _emission_energy := 2.0
var _visible_only_when_mask_on := true
var _editor_show_preview := true
var _editor_preview_color := Color(0.2, 0.9, 1.0, 0.9)
var _editor_preview_size := 0.12
var _editor_snap_to_surface := false

@export var texture: Texture2D:
	set(value):
		_texture = value
		_queue_rebuild()
	get:
		return _texture

@export var size_meters := Vector2(1.0, 1.0):
	set(value):
		_size_meters = value
		_queue_rebuild()
	get:
		return _size_meters

@export_enum("FLOOR", "WALL", "CUSTOM") var mode := "WALL":
	set(value):
		_mode = value
		_queue_rebuild()
	get:
		return _mode

@export var offset_meters := 0.003:
	set(value):
		_offset_meters = value
		_queue_rebuild()
	get:
		return _offset_meters

@export_enum("SCISSOR", "BLEND") var alpha_mode := "SCISSOR":
	set(value):
		_alpha_mode = value
		_queue_rebuild()
	get:
		return _alpha_mode

@export var alpha_scissor_threshold := 0.5:
	set(value):
		_alpha_scissor_threshold = value
		_queue_rebuild()
	get:
		return _alpha_scissor_threshold

@export var unshaded := false:
	set(value):
		_unshaded = value
		_queue_rebuild()
	get:
		return _unshaded

@export var double_sided := true:
	set(value):
		_double_sided = value
		_queue_rebuild()
	get:
		return _double_sided

@export var emissive := false:
	set(value):
		_emissive = value
		_queue_rebuild()
	get:
		return _emissive

@export var emission_color := Color(1, 1, 1):
	set(value):
		_emission_color = value
		_queue_rebuild()
	get:
		return _emission_color

@export var emission_energy := 2.0:
	set(value):
		_emission_energy = value
		_queue_rebuild()
	get:
		return _emission_energy

@export var visible_only_when_mask_on := true:
	set(value):
		_visible_only_when_mask_on = value
		_update_mask_visibility(_mask_on)
	get:
		return _visible_only_when_mask_on

@export var editor_show_preview := true:
	set(value):
		_editor_show_preview = value
		_update_preview_visibility()
	get:
		return _editor_show_preview

@export var editor_preview_color := Color(0.2, 0.9, 1.0, 0.9):
	set(value):
		_editor_preview_color = value
		_update_preview()
	get:
		return _editor_preview_color

@export var editor_preview_size := 0.12:
	set(value):
		_editor_preview_size = value
		_update_preview()
	get:
		return _editor_preview_size

@export var editor_snap_to_surface := false:
	set(value):
		_editor_snap_to_surface = value
		if Engine.is_editor_hint() and _editor_snap_to_surface:
			_snap_to_surface()
			_editor_snap_to_surface = false
	get:
		return _editor_snap_to_surface

var _mesh_instance: MeshInstance3D
var _quad: QuadMesh
var _material: StandardMaterial3D
var _pending_rebuild := false
var _preview_mesh_instance: MeshInstance3D
var _preview_mesh: ImmediateMesh
var _preview_material: StandardMaterial3D
var _mask_on := true


func _ready() -> void:
	_ensure_mesh_instance()
	_rebuild()
	_connect_mask_manager()


func apply_to_surface(global_surface_normal: Vector3) -> void:
	if global_surface_normal == Vector3.ZERO:
		return
	var normal := global_surface_normal.normalized()
	var up := Vector3.UP
	if abs(normal.dot(up)) > 0.98:
		up = Vector3.RIGHT
	# look_at uses -Z as forward, so target is opposite the normal to align +Z with it.
	look_at(global_transform.origin - normal, up)
	_apply_offset_local(LOCAL_FRONT)


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		if _pending_rebuild:
			return
		_pending_rebuild = true
		call_deferred("_rebuild")
		return
	_rebuild()


func _rebuild() -> void:
	_pending_rebuild = false
	_ensure_mesh_instance()
	_configure_mesh()
	_configure_material()
	_apply_mode_orientation()
	_apply_offset_local(LOCAL_FRONT)
	_update_mask_visibility(_mask_on)
	_update_preview()


func _ensure_mesh_instance() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance)


func _configure_mesh() -> void:
	if _quad == null:
		_quad = QuadMesh.new()
	_mesh_instance.mesh = _quad
	var safe_size := Vector2(max(size_meters.x, 0.01), max(size_meters.y, 0.01))
	_quad.size = safe_size


func _configure_material() -> void:
	# Duplicate per sticker so edits are not shared across instances.
	_material = StandardMaterial3D.new()
	_mesh_instance.material_override = _material
	_material.albedo_texture = texture
	# Ensure PNGs are imported with alpha + mipmaps to avoid fringes/shimmering.

	match alpha_mode:
		"SCISSOR":
			# Scissor is faster and more reliable on Web, but only hard edges.
			_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			_material.alpha_scissor_threshold = clamp(alpha_scissor_threshold, 0.0, 1.0)
		"BLEND":
			# Blend can look nicer on soft edges, but sorting can be tricky.
			_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_material.alpha_scissor_threshold = 0.0
		_:
			_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			_material.alpha_scissor_threshold = clamp(alpha_scissor_threshold, 0.0, 1.0)

	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK

	if emissive:
		_material.emission_enabled = true
		_material.emission = emission_color
		_material.set("emission_energy_multiplier", max(0.0, emission_energy))
	else:
		_material.emission_enabled = false


func _apply_mode_orientation() -> void:
	match mode:
		"FLOOR":
			# Rotate so the QuadMesh front (+Z) faces up (+Y).
			var yaw := rotation_degrees.y
			rotation_degrees = Vector3(-90.0, yaw, 0.0)
		"WALL":
			# Rotate so the QuadMesh front (+Z) faces forward (-Z).
			rotation_degrees = Vector3(0.0, 180.0, 0.0)
		"CUSTOM":
			# Do not force rotation.
			pass


func _apply_offset_local(local_normal: Vector3) -> void:
	if _mesh_instance == null:
		return
	_mesh_instance.position = local_normal.normalized() * max(0.0, offset_meters)


func _connect_mask_manager() -> void:
	if Engine.is_editor_hint():
		return
	var mask_manager := get_node_or_null("/root/MaskManager")
	if mask_manager != null and mask_manager.has_signal("mask_toggled"):
		mask_manager.mask_toggled.connect(_on_mask_toggled)
		if mask_manager.has_method("get"):
			_on_mask_toggled(mask_manager.mask_on)


func _on_mask_toggled(mask_on: bool) -> void:
	_mask_on = mask_on
	_update_mask_visibility(mask_on)


func _update_mask_visibility(mask_on: bool) -> void:
	if _mesh_instance == null:
		return
	if _visible_only_when_mask_on:
		_mesh_instance.visible = mask_on
	else:
		_mesh_instance.visible = true


func _ensure_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if _preview_mesh_instance != null and is_instance_valid(_preview_mesh_instance):
		return
	_preview_mesh_instance = MeshInstance3D.new()
	_preview_mesh_instance.name = "EditorPreview"
	_preview_mesh_instance.visible = editor_show_preview
	add_child(_preview_mesh_instance, false, Node.INTERNAL_MODE_FRONT)

	_preview_mesh = ImmediateMesh.new()
	_preview_mesh_instance.mesh = _preview_mesh

	_preview_material = StandardMaterial3D.new()
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.vertex_color_use_as_albedo = true
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview_mesh_instance.material_override = _preview_material


func _update_preview_visibility() -> void:
	if _preview_mesh_instance == null:
		return
	_preview_mesh_instance.visible = Engine.is_editor_hint() and editor_show_preview


func _update_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_preview()
	if _preview_mesh == null:
		return
	_update_preview_visibility()
	_preview_mesh.clear_surfaces()
	if not editor_show_preview:
		return

	var half_w: float = max(0.01, size_meters.x) * 0.5
	var half_h: float = max(0.01, size_meters.y) * 0.5
	var normal_len: float = max(0.02, editor_preview_size)

	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _preview_material)
	_preview_mesh.surface_set_color(editor_preview_color)
	# Normal line (shows facing and offset direction).
	_preview_mesh.surface_add_vertex(Vector3.ZERO)
	_preview_mesh.surface_add_vertex(LOCAL_FRONT * (offset_meters + normal_len))
	# Tiny cross on the plane for scale.
	_preview_mesh.surface_add_vertex(Vector3(-half_w, 0.0, 0.0))
	_preview_mesh.surface_add_vertex(Vector3(half_w, 0.0, 0.0))
	_preview_mesh.surface_add_vertex(Vector3(0.0, -half_h, 0.0))
	_preview_mesh.surface_add_vertex(Vector3(0.0, half_h, 0.0))
	_preview_mesh.surface_end()


func _snap_to_surface() -> void:
	var world := get_world_3d()
	if world == null:
		return
	var dir := -global_transform.basis.z
	if mode == "FLOOR":
		dir = Vector3.DOWN
	var from := global_transform.origin + (dir * 0.05)
	var to := from + (dir * 5.0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	var hit := world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return
	global_position = hit.position
	apply_to_surface(hit.normal)
