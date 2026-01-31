class_name Monster
extends CharacterBody3D

@export var speed := 7.5
@export var arrival_distance := 0.25
@export var use_navmesh := true
@export var nav_avoidance_enabled := false
@export var debug_nav_logs := false
@export_range(0.05, 5.0, 0.05) var debug_nav_log_interval_sec := 0.5
@export var footstep_stream: AudioStream
@export var footstep_volume_db := -2.0
@export var footstep_volume_far_db := 6.0
@export var footstep_volume_far_distance := 20.0
@export var footstep_dir := "res://monster/sounds/footsteps"
@export_range(1, 20, 1) var footstep_count := 5
@export var footstep_interval_min_sec := 0.5
@export var footstep_interval_max_sec := 0.8
@export_range(0.0, 5.0, 0.05) var footstep_min_speed := 0.3
@export var idle_source_scene: PackedScene
@export var walk_source_scene: PackedScene
@export var idle_animation_name: StringName = &""
@export var walk_animation_name: StringName = &""
@export var freeze_when_mask_on := true
@export var freeze_when_seen := true
@export var eyes_bone_name: StringName = &""
@export var eyes_bone_hint := "head"
@export_range(1.0, 179.0, 1.0) var seen_angle_deg := 45.0
@export_range(1.0, 179.0, 1.0) var seen_release_angle_deg := 55.0
@export var seen_max_distance := 40.0
@export var seen_require_line_of_sight := true
@export var seen_los_collision_mask := -1
@export var debug_seen_logs := false
@export_range(0.05, 5.0, 0.05) var debug_seen_log_interval_sec := 0.5
@export var debug_animation_logs := false
@export_range(0.05, 10.0, 0.05) var debug_log_interval_sec := 1.0

var _step_accum := 0.0
var _footstep_time_left := 0.0
var _footstep_streams: Array[AudioStream] = []
var _rng := RandomNumberGenerator.new()
var _next_debug_log_time_ms := 0
var _debug_setup_summary := ""

@onready var _footsteps: AudioStreamPlayer3D = get_node_or_null("Footsteps")
@onready var _visual: Node = get_node_or_null("Visual")
@onready var _nav_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
@onready var _mask_manager: Node = get_node_or_null("/root/MaskManager")
@onready var _debug_manager: Node = get_node_or_null("/root/DebugManager")

var _anim_player: AnimationPlayer
var _idle_anim: StringName = &""
var _walk_anim: StringName = &""
var _nav_safe_velocity := Vector3.ZERO
var _nav_safe_velocity_valid := false
var _frozen_by_seen := false
var _anim_speed_scale_before_freeze := 1.0
var _seen_last_dot := 0.0
var _seen_last_los := false
var _next_seen_debug_time_ms := 0
var _hunt_target := Vector3.ZERO
var _next_nav_debug_time_ms := 0
var _eyes: Node3D
var _eyes_attachment: BoneAttachment3D

func _ready() -> void:
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	_load_footstep_streams()
	_setup_navigation()
	_setup_animations()
	_setup_eyes_attachment()
	_reduce_material_shininess()
	_sync_animation(false)
	_debug_log_force("ready: mask_on=%s debug_show=%s" % [_mask_manager != null and _mask_manager.mask_on, _debug_manager != null and _debug_manager.show_monsters])

	if _mask_manager != null:
		_mask_manager.mask_toggled.connect(_on_mask_toggled)
	if _debug_manager != null:
		_debug_manager.show_monsters_changed.connect(_on_debug_show_monsters_changed)
	_update_visibility()
	if not _debug_enabled():
		print("[Monster:%s] debug disabled (set debug_animation_logs=true or press '=' to toggle DebugManager.show_monsters)" % [str(get_instance_id())])

func reset_patrol() -> void:
	velocity = Vector3.ZERO
	_step_accum = 0.0
	_stop_navigation_velocity()
	_hunt_target = global_position

func _physics_process(delta: float) -> void:
	var should_freeze_seen := _update_seen_freeze()
	_set_seen_frozen(should_freeze_seen)
	_debug_seen_state()
	if should_freeze_seen:
		velocity = Vector3.ZERO
		_stop_navigation_velocity()
		_step_accum = 0.0
		_stop_footsteps()
		return

	if freeze_when_mask_on and _mask_manager != null and _mask_manager.mask_on:
		velocity = Vector3.ZERO
		_stop_navigation_velocity()
		_sync_animation(false)
		_stop_footsteps()
		_debug_log("frozen_by_mask: anim=%s" % [_anim_name()])
		return

	var prev_pos := global_position

	var target := _get_hunt_target(delta)
	var to_target := target - global_position
	to_target.y = 0.0

	var dir := _get_nav_direction(target, to_target)
	var desired_velocity := dir * speed
	if nav_avoidance_enabled and _nav_agent != null and _nav_agent.has_method("set_velocity"):
		_nav_safe_velocity_valid = false
		_nav_agent.set_velocity(desired_velocity)
		velocity = _nav_safe_velocity if _nav_safe_velocity_valid else desired_velocity
	else:
		velocity = desired_velocity
	move_and_slide()

	_try_play_footsteps(prev_pos, delta)
	_sync_animation(true)
	_debug_nav_state(delta, target)
	_debug_log("moving: vel=%.2f target=%s current=%s" % [Vector2(velocity.x, velocity.z).length(), String(_desired_anim_name(true)), _anim_name()])

	if velocity.length_squared() > 0.001:
		look_at(global_position + Vector3(velocity.x, 0.0, velocity.z), Vector3.UP)

	for i in range(get_slide_collision_count()):
		var collider := get_slide_collision(i).get_collider()
		if collider is Player:
			GameManager.player_caught()

func _on_mask_toggled(mask_on: bool) -> void:
	_update_visibility()
	if freeze_when_mask_on and mask_on:
		velocity = Vector3.ZERO
		_step_accum = 0.0
		_sync_animation(false)
		_stop_footsteps()
	_debug_log_force("mask_toggled: %s anim=%s" % [mask_on, _anim_name()])

func _on_debug_show_monsters_changed(_show: bool) -> void:
	_update_visibility()
	_debug_log_force("debug_show_monsters_changed: %s" % [_debug_manager != null and _debug_manager.show_monsters])
	if _debug_manager != null and _debug_manager.show_monsters and _debug_setup_summary != "":
		print("[Monster:%s] %s" % [str(get_instance_id()), _debug_setup_summary])

func _setup_navigation() -> void:
	if _nav_agent == null:
		return

	_nav_agent.path_desired_distance = arrival_distance
	_nav_agent.target_desired_distance = arrival_distance
	_nav_agent.avoidance_enabled = nav_avoidance_enabled

	if nav_avoidance_enabled and not _nav_agent.velocity_computed.is_connected(_on_nav_velocity_computed):
		_nav_agent.velocity_computed.connect(_on_nav_velocity_computed)

func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	_nav_safe_velocity = safe_velocity
	_nav_safe_velocity_valid = true

func _stop_navigation_velocity() -> void:
	if _nav_agent == null:
		return
	if nav_avoidance_enabled and _nav_agent.has_method("set_velocity"):
		_nav_agent.set_velocity(Vector3.ZERO)

func _get_nav_direction(target: Vector3, to_target_flat: Vector3) -> Vector3:
	if not use_navmesh or _nav_agent == null:
		return to_target_flat.normalized()

	_nav_agent.target_position = target
	var next_pos := _nav_agent.get_next_path_position()
	var to_next := next_pos - global_position
	to_next.y = 0.0

	if to_next.length_squared() > 0.0001:
		return to_next.normalized()
	return to_target_flat.normalized()

func _get_hunt_target(delta: float) -> Vector3:
	var player: Player = null
	if GameManager != null:
		player = GameManager.player

	if player == null:
		_hunt_target = global_position
		_debug_log("hunt: no player, holding position")
		return _hunt_target

	var desired: Vector3 = _project_point_to_navmesh(player.global_position) if use_navmesh else player.global_position
	_hunt_target = desired
	if _nav_agent != null:
		_nav_agent.target_position = desired

	return _hunt_target

func _debug_nav_state(delta: float, target: Vector3) -> void:
	if not (debug_nav_logs or (_debug_manager != null and _debug_manager.show_monsters)):
		return
	var now := Time.get_ticks_msec()
	if now < _next_nav_debug_time_ms:
		return
	_next_nav_debug_time_ms = now + int(debug_nav_log_interval_sec * 1000.0)

	var mode := "Hunt"
	var to_target := target - global_position
	to_target.y = 0.0
	var dist_target := to_target.length()

	var next_pos := Vector3.ZERO
	var dist_next := -1.0
	var reachable_txt := "?"
	var finished_txt := "?"
	var path_len := -1
	var path_idx := -1

	if _nav_agent != null:
		next_pos = _nav_agent.get_next_path_position()
		var to_next := next_pos - global_position
		to_next.y = 0.0
		dist_next = to_next.length()
		if _nav_agent.has_method("is_target_reachable"):
			reachable_txt = "Y" if _nav_agent.is_target_reachable() else "N"
		if _nav_agent.has_method("is_navigation_finished"):
			finished_txt = "Y" if _nav_agent.is_navigation_finished() else "N"
		if _nav_agent.has_method("get_current_navigation_path"):
			var p: PackedVector3Array = _nav_agent.get_current_navigation_path()
			path_len = p.size()
		if _nav_agent.has_method("get_current_navigation_path_index"):
			path_idx = int(_nav_agent.get_current_navigation_path_index())

	print("[Monster:%s] nav mode=%s vel=%.2f dist_target=%.2f dist_next=%s reachable=%s finished=%s path=%s idx=%s target=%s next=%s" % [
		str(get_instance_id()),
		mode,
		Vector2(velocity.x, velocity.z).length(),
		dist_target,
		"?" if dist_next < 0.0 else "%.2f" % dist_next,
		reachable_txt,
		finished_txt,
		"?" if path_len < 0 else str(path_len),
		"?" if path_idx < 0 else str(path_idx),
		str(target),
		str(next_pos)
	])

func _get_navigation_map_rid() -> RID:
	var map_rid := RID()
	var world: World3D = get_world_3d()
	if world == null:
		return map_rid

	var maybe: Variant = world.get("navigation_map")
	if typeof(maybe) == TYPE_RID:
		map_rid = maybe
	elif world.has_method("get_navigation_map"):
		map_rid = world.get_navigation_map()

	return map_rid

func _navigation_map_ready(map_rid: RID) -> bool:
	if not map_rid.is_valid():
		return false
	if NavigationServer3D.has_method("map_get_iteration_id"):
		return int(NavigationServer3D.map_get_iteration_id(map_rid)) > 0
	return true

func _project_point_to_navmesh(point: Vector3) -> Vector3:
	var map_rid := _get_navigation_map_rid()
	if not _navigation_map_ready(map_rid):
		return point
	if NavigationServer3D.has_method("map_get_closest_point"):
		var cp := NavigationServer3D.map_get_closest_point(map_rid, point)
		if typeof(cp) == TYPE_VECTOR3:
			return cp
	return point

func _update_seen_freeze() -> bool:
	_seen_last_dot = 0.0
	_seen_last_los = false
	if not freeze_when_seen:
		return false

	var player: Player = null
	if GameManager != null:
		player = GameManager.player
	if player == null:
		return false

	var camera: Camera3D = player.get_node_or_null(^"CameraRig/Camera3D") as Camera3D
	if camera == null:
		var found: Node = player.find_child("Camera3D", true, false)
		camera = found as Camera3D

	var origin := camera.global_position if camera != null else player.global_position
	var forward := (-camera.global_transform.basis.z).normalized() if camera != null else (-player.global_transform.basis.z).normalized()
	var to_me := global_position - origin
	var distance := to_me.length()
	if distance <= 0.001:
		_seen_last_dot = 1.0
		_seen_last_los = true
		return true
	if distance > maxf(seen_max_distance, 0.0):
		return false

	var dir := to_me / distance
	var dot := clampf(forward.dot(dir), -1.0, 1.0)
	_seen_last_dot = dot

	var cone_deg := seen_release_angle_deg if _frozen_by_seen else seen_angle_deg
	var threshold := cos(deg_to_rad(clampf(cone_deg, 1.0, 179.0)))
	if dot < threshold:
		return false

	if not seen_require_line_of_sight:
		_seen_last_los = true
		return true

	var world: World3D = get_world_3d()
	if world == null:
		_seen_last_los = true
		return true

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var head := global_position + Vector3.UP * 1.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, head, seen_los_collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player]

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider: Object = hit.get("collider") as Object
	_seen_last_los = (collider == self)
	return _seen_last_los

func _set_seen_frozen(value: bool) -> void:
	if _frozen_by_seen == value:
		return
	_frozen_by_seen = value

	if _anim_player == null:
		return
	if _frozen_by_seen:
		_anim_speed_scale_before_freeze = _anim_player.speed_scale
		_anim_player.speed_scale = 0.0
	else:
		_anim_player.speed_scale = _anim_speed_scale_before_freeze

func _debug_seen_state() -> void:
	if not (debug_seen_logs or (_debug_manager != null and _debug_manager.show_monsters)):
		return
	var now := Time.get_ticks_msec()
	if now < _next_seen_debug_time_ms:
		return
	_next_seen_debug_time_ms = now + int(debug_seen_log_interval_sec * 1000.0)

	print("[Monster:%s] seen freeze=%s dot=%.3f los=%s anim=%s vel=%.2f" % [
		str(get_instance_id()),
		"Y" if _frozen_by_seen else "N",
		_seen_last_dot,
		"Y" if _seen_last_los else "N",
		_anim_name(),
		Vector2(velocity.x, velocity.z).length()
	])

func _update_visibility() -> void:
	var mask_on := false
	if _mask_manager != null:
		mask_on = _mask_manager.mask_on
	var debug_show := false
	if _debug_manager != null:
		debug_show = _debug_manager.show_monsters

	visible = mask_on or debug_show

	# Update eyes visibility (only show when mask is on)
	if _eyes == null:
		_eyes = _find_eyes_node()
	if _eyes != null:
		_eyes.visible = mask_on

	if not visible:
		return
	if mask_on:
		_set_geometry_transparency(0.0)
	else:
		_set_geometry_transparency(0.55 if debug_show else 0.0)

func _set_geometry_transparency(amount: float) -> void:
	var stack: Array[Node] = [self]
	while stack.size() > 0:
		var node: Node = stack.pop_back() as Node
		if node == null:
			continue
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).transparency = clampf(amount, 0.0, 1.0)
		for child: Node in node.get_children():
			stack.append(child)

func _stop_footsteps() -> void:
	_footstep_time_left = 0.0
	if _footsteps == null:
		return
	if _footsteps.playing:
		_footsteps.stop()

func _load_footstep_streams() -> void:
	_footstep_streams.clear()
	for i in range(1, footstep_count + 1):
		var path := "%s/%d.mp3" % [footstep_dir, i]
		var stream := load(path)
		if stream is AudioStream:
			_footstep_streams.append(stream)
	if _footstep_streams.is_empty() and footstep_stream != null:
		_footstep_streams.append(footstep_stream)
	if _footstep_streams.is_empty():
		push_warning("Monster: no footstep streams found in '%s' (1-%d)" % [footstep_dir, footstep_count])

func _try_play_footsteps(prev_pos: Vector3, delta: float) -> void:
	if _footsteps == null:
		return
	var volume_db := footstep_volume_db
	if GameManager != null and GameManager.player != null:
		var dist := global_position.distance_to(GameManager.player.global_position)
		var far_dist := maxf(footstep_volume_far_distance, 0.1)
		var t := clampf(dist / far_dist, 0.0, 1.0)
		volume_db = lerpf(footstep_volume_db, footstep_volume_far_db, t)
	_footsteps.volume_db = volume_db

	var moved := (global_position - prev_pos).length() > 0.0005
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var moving := moved and horiz_speed > footstep_min_speed
	if not moving:
		_stop_footsteps()
		return

	_footstep_time_left -= delta
	if _footstep_time_left > 0.0:
		return

	if _footstep_streams.is_empty():
		return

	var min_interval := minf(footstep_interval_min_sec, footstep_interval_max_sec)
	var max_interval := maxf(footstep_interval_min_sec, footstep_interval_max_sec)
	_footstep_time_left = _rng.randf_range(maxf(min_interval, 0.05), maxf(max_interval, 0.05))
	var idx := _rng.randi_range(0, _footstep_streams.size() - 1)
	_footsteps.stream = _footstep_streams[idx]
	_footsteps.play()

func _setup_animations() -> void:
	if _visual == null and idle_source_scene != null:
		_visual = idle_source_scene.instantiate()
		if _visual != null:
			_visual.name = "Visual"
			add_child(_visual)

	var visual_root: Node = _visual if _visual != null else self
	_anim_player = _find_animation_player(visual_root)
	if _anim_player == null:
		push_warning("Monster: no AnimationPlayer found under %s" % visual_root.name)
		_debug_log_force("setup: no AnimationPlayer under %s" % visual_root.name)
		return
	var base_anim_root := _get_anim_root(_anim_player)

	var available := _get_animation_full_names(_anim_player)
	if available.is_empty():
		push_warning("Monster: no animations found on AnimationPlayer")
		_debug_log_force("setup: AnimationPlayer has no animations")
		return

	_idle_anim = idle_animation_name if idle_animation_name != &"" else _pick_animation_name(_anim_player, "idle")
	if _idle_anim == &"":
		push_warning("Monster: couldn't pick an idle animation")
		_debug_log_force("setup: couldn't pick idle; available=%s" % [_format_names(available)])
		return
	if not _anim_player.has_animation(_idle_anim):
		var available_strings: Array[String] = []
		available_strings.resize(available.size())
		for i in range(available.size()):
			available_strings[i] = String(available[i])
		var available_text := ", ".join(available_strings)
		push_warning("Monster: idle animation '%s' not found; available: %s" % [String(_idle_anim), available_text])
		_idle_anim = _pick_animation_name(_anim_player, "idle")
		if _idle_anim == &"":
			return

	if _anim_player.has_method("set_active"):
		_anim_player.active = true
	_anim_player.play(_idle_anim)
	var base_skeleton_initial := _find_skeleton(base_anim_root)
	_debug_setup_summary = "setup: player=%s root=%s skeleton=%s idle='%s' current='%s' available=%s" % [
		String(_anim_player.get_path()),
		"<null>" if base_anim_root == null else String(base_anim_root.get_path()),
		"<none>" if base_skeleton_initial == null else String(base_anim_root.get_path_to(base_skeleton_initial)),
		String(_idle_anim),
		_anim_name(),
		_format_names(available)
	]
	_debug_log_force(_debug_setup_summary)

	if walk_source_scene == null:
		_walk_anim = walk_animation_name if walk_animation_name != &"" else _pick_animation_name(_anim_player, "walk")
		_debug_setup_summary += " | walk_src=none walk='%s'" % [String(_walk_anim)]
		_debug_log_force("setup: no walk_source_scene; walk='%s'" % [String(_walk_anim)])
		return

	var walk_scene_root := walk_source_scene.instantiate()
	if walk_scene_root == null:
		_walk_anim = _pick_animation_name(_anim_player, "walk")
		_debug_setup_summary += " | walk_src=instantiate_failed walk='%s'" % [String(_walk_anim)]
		_debug_log_force("setup: failed to instantiate walk_source_scene; fallback walk='%s'" % [String(_walk_anim)])
		return

	var walk_player := _find_animation_player(walk_scene_root)
	if walk_player == null:
		_walk_anim = _pick_animation_name(_anim_player, "walk")
		_debug_setup_summary += " | walk_src=no_player walk='%s'" % [String(_walk_anim)]
		_debug_log_force("setup: no AnimationPlayer in walk scene; fallback walk='%s'" % [String(_walk_anim)])
		walk_scene_root.free()
		return
	var walk_anim_root := _get_anim_root(walk_player)
	var base_skeleton := base_skeleton_initial
	var walk_skeleton := _find_skeleton(walk_anim_root)

	var walk_source_full_name := _pick_animation_name(walk_player, "walk")
	if walk_source_full_name == &"":
		_walk_anim = _pick_animation_name(_anim_player, "walk")
		_debug_setup_summary += " | walk_src=no_walk_clip walk='%s'" % [String(_walk_anim)]
		_debug_log_force("setup: couldn't pick walk from walk scene; fallback walk='%s'" % [String(_walk_anim)])
		walk_scene_root.free()
		return

	var walk_animation: Animation = walk_player.get_animation(walk_source_full_name)
	if walk_animation == null:
		_walk_anim = _pick_animation_name(_anim_player, "walk")
		_debug_setup_summary += " | walk_src=clip_null walk='%s'" % [String(_walk_anim)]
		_debug_log_force("setup: walk animation resource null; fallback walk='%s'" % [String(_walk_anim)])
		walk_scene_root.free()
		return

	var target_name: StringName = &"Walk"
	if _anim_player.has_animation(target_name):
		_walk_anim = target_name
		_debug_setup_summary += " | walk_src=already_present walk='%s'" % [String(_walk_anim)]
		_debug_log_force("setup: already has Walk; walk='%s'" % [String(_walk_anim)])
		walk_scene_root.free()
		return

	var remapped_walk := _remap_animation_tracks(walk_animation, walk_anim_root, base_anim_root, walk_skeleton, base_skeleton)
	_add_animation_to_player(_anim_player, target_name, remapped_walk)
	_walk_anim = target_name if _anim_player.has_animation(target_name) else _pick_animation_name(_anim_player, "walk")
	walk_scene_root.free()

	if _walk_anim == &"" or not _anim_player.has_animation(_walk_anim):
		push_warning("Monster: walk animation not available; movement will use idle")
		_debug_log_force("setup: walk missing after add; walk='%s' available=%s" % [String(_walk_anim), _format_names(_get_animation_full_names(_anim_player))])
		_debug_setup_summary += " | walk=missing"
	else:
		var track_count := _anim_player.get_animation(_walk_anim).get_track_count() if _anim_player.get_animation(_walk_anim) != null else -1
		var invalid := _count_invalid_tracks(_anim_player.get_animation(_walk_anim), base_anim_root)
		var invalid_examples := _invalid_track_examples(_anim_player.get_animation(_walk_anim), base_anim_root, 5)
		_debug_log_force("setup: walk='%s' track_count=%d invalid_tracks=%d" % [String(_walk_anim), track_count, invalid])
		_debug_setup_summary += " | walk='%s' tracks=%d invalid=%d %s" % [String(_walk_anim), track_count, invalid, invalid_examples]

func _setup_eyes_attachment() -> void:
	_eyes = _find_eyes_node()
	if _eyes == null:
		return

	var skeleton := _find_eyes_skeleton()
	if skeleton == null:
		return

	var resolved_bone := _resolve_eyes_bone(skeleton)
	if resolved_bone == &"":
		_debug_log("eyes: no head bone found, leaving attachment unchanged")
		return

	var attachment := skeleton.get_node_or_null("EyesAttachment") as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = "EyesAttachment"
		skeleton.add_child(attachment)
	_eyes_attachment = attachment
	attachment.bone_name = resolved_bone

	if _eyes.get_parent() != attachment:
		_reparent_keep_global(_eyes, attachment)

func _find_eyes_node() -> Node3D:
	var eyes := get_node_or_null("mixamo_slender/Armature/Skeleton3D/EyesAttachment/Eyes") as Node3D
	if eyes == null and _visual != null:
		eyes = _visual.find_child("Eyes", true, false) as Node3D
	if eyes == null:
		eyes = find_child("Eyes", true, false) as Node3D
	return eyes

func _find_eyes_skeleton() -> Skeleton3D:
	var skeleton: Skeleton3D = null
	if _visual != null:
		skeleton = _find_skeleton(_visual)
	if skeleton == null:
		var base_visual := get_node_or_null("mixamo_slender")
		skeleton = _find_skeleton(base_visual)
	if skeleton == null:
		skeleton = _find_skeleton(self)
	return skeleton

func _resolve_eyes_bone(skeleton: Skeleton3D) -> StringName:
	if skeleton == null:
		return &""

	if eyes_bone_name != &"":
		var idx := skeleton.find_bone(String(eyes_bone_name))
		if idx != -1:
			return skeleton.get_bone_name(idx)

	var hint := eyes_bone_hint.strip_edges()
	if hint == "":
		hint = "head"
	var hint_lower := hint.to_lower()

	for i in range(skeleton.get_bone_count()):
		var name := String(skeleton.get_bone_name(i))
		if name.to_lower() == hint_lower:
			return skeleton.get_bone_name(i)

	for i in range(skeleton.get_bone_count()):
		var name := String(skeleton.get_bone_name(i))
		if name.to_lower().contains(hint_lower):
			return skeleton.get_bone_name(i)

	for i in range(skeleton.get_bone_count()):
		var name := String(skeleton.get_bone_name(i))
		if name.to_lower().contains("head"):
			return skeleton.get_bone_name(i)

	return &""

func _reparent_keep_global(node: Node3D, new_parent: Node) -> void:
	if node == null or new_parent == null:
		return
	var prev_global := node.global_transform
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = prev_global

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var matches := root.find_children("*", "AnimationPlayer", true, false)
	if matches.is_empty():
		return null
	return matches[0] as AnimationPlayer

func _pick_animation_name(player: AnimationPlayer, preferred_substring: String) -> StringName:
	if player == null:
		return &""
	var candidates := _get_animation_full_names(player)
	if candidates.is_empty():
		return &""
	var needle := preferred_substring.to_lower()
	for name in candidates:
		if String(name).to_lower().contains(needle):
			return name
	return candidates[0]

func _get_animation_full_names(player: AnimationPlayer) -> Array[StringName]:
	var result: Array[StringName] = []
	if player == null:
		return result

	if player.has_method("get_animation_library_list") and player.has_method("get_animation_library"):
		var libs := player.get_animation_library_list()
		for lib_name in libs:
			var lib: AnimationLibrary = player.get_animation_library(lib_name) as AnimationLibrary
			if lib == null:
				continue
			var anims := lib.get_animation_list()
			for anim_name in anims:
				if lib_name == &"":
					result.append(anim_name)
				else:
					result.append(StringName("%s/%s" % [String(lib_name), String(anim_name)]))
		return result

	if player.has_method("get_animation_list"):
		var names := player.get_animation_list()
		for name in names:
			result.append(name)
	return result

func _add_animation_to_player(player: AnimationPlayer, name: StringName, animation: Animation) -> void:
	if player == null or animation == null:
		return
	if player.has_animation(name):
		return

	if player.has_method("get_animation_library") and player.has_method("add_animation_library"):
		var lib: AnimationLibrary = player.get_animation_library(&"") as AnimationLibrary
		if lib == null:
			lib = AnimationLibrary.new()
			player.add_animation_library(&"", lib)
		lib.add_animation(name, animation)
		return

	if player.has_method("add_animation"):
		player.add_animation(name, animation)

func _get_anim_root(player: AnimationPlayer) -> Node:
	if player == null:
		return null
	var path: NodePath = player.root_node
	if path == NodePath("") or String(path) == "":
		path = NodePath(".")
	var node := player.get_node_or_null(path)
	if node != null:
		return node
	return player.get_parent()

func _find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var matches := root.find_children("*", "Skeleton3D", true, false)
	if matches.is_empty():
		return null
	return matches[0] as Skeleton3D

func _count_invalid_tracks(anim: Animation, anim_root: Node) -> int:
	if anim == null or anim_root == null:
		return -1
	var invalid := 0
	for i in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(i)
		var node_part := NodePath(path.get_concatenated_names())
		if anim_root.get_node_or_null(node_part) == null:
			invalid += 1
	return invalid

func _invalid_track_examples(anim: Animation, anim_root: Node, max_examples: int) -> String:
	if anim == null or anim_root == null:
		return ""
	var examples: Array[String] = []
	for i in range(anim.get_track_count()):
		if examples.size() >= max_examples:
			break
		var path: NodePath = anim.track_get_path(i)
		var node_part := NodePath(path.get_concatenated_names())
		if anim_root.get_node_or_null(node_part) == null:
			examples.append(String(path))
	if examples.is_empty():
		return ""
	return "invalid_examples=%s" % ["[" + ", ".join(examples) + "]"]

func _remap_animation_tracks(source: Animation, source_root: Node, target_root: Node, source_skeleton: Skeleton3D, target_skeleton: Skeleton3D) -> Animation:
	if source == null:
		return null
	if source_root == null or target_root == null:
		return source.duplicate(true) as Animation

	var out := source.duplicate(true) as Animation
	var target_skeleton_rel := ""
	if target_skeleton != null:
		target_skeleton_rel = String(target_root.get_path_to(target_skeleton))

	for i in range(out.get_track_count()):
		var path: NodePath = out.track_get_path(i)
		var node_part := NodePath(path.get_concatenated_names())
		if target_root.get_node_or_null(node_part) != null:
			continue

		var replacement_node_rel := ""
		var source_node := source_root.get_node_or_null(node_part)
		if source_node != null:
			if source_node is Skeleton3D and target_skeleton_rel != "":
				replacement_node_rel = target_skeleton_rel
			else:
				var candidate := _find_node_by_name_and_class(target_root, source_node.name, source_node.get_class())
				if candidate != null:
					replacement_node_rel = String(target_root.get_path_to(candidate))
				else:
					var by_name := target_root.find_child(source_node.name, true, false)
					if by_name != null:
						replacement_node_rel = String(target_root.get_path_to(by_name))

		if replacement_node_rel == "" and target_skeleton_rel != "":
			replacement_node_rel = target_skeleton_rel

		if replacement_node_rel == "":
			continue

		var sub := path.get_concatenated_subnames()
		var new_path := NodePath(replacement_node_rel) if sub == "" else NodePath("%s:%s" % [replacement_node_rel, sub])
		out.track_set_path(i, new_path)

	return out

func _find_node_by_name_and_class(root: Node, node_name: StringName, node_class: StringName) -> Node:
	if root == null:
		return null
	var matches := root.find_children("*", String(node_class), true, false)
	for node in matches:
		if node != null and node.name == node_name:
			return node
	return null

func _sync_animation(moving: bool) -> void:
	if _anim_player == null:
		return
	if _frozen_by_seen:
		return

	var target := _desired_anim_name(moving)

	if target == &"":
		return
	if _anim_player.current_animation == target and _anim_player.is_playing():
		return
	_debug_log_force("anim_switch: %s -> %s (vel=%.2f)" % [_anim_name(), String(target), Vector2(velocity.x, velocity.z).length()])
	_anim_player.play(target)

func _desired_anim_name(moving: bool) -> StringName:
	var target := _idle_anim
	if moving:
		var horiz_speed_sq := Vector2(velocity.x, velocity.z).length_squared()
		if horiz_speed_sq > 0.01 and _walk_anim != &"":
			target = _walk_anim
	return target

func _reduce_material_shininess() -> void:
	# Recursively find all MeshInstance3D nodes and reduce material shininess
	_reduce_shininess_recursive(self)

func _reduce_shininess_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for i in range(mesh_instance.get_surface_override_material_count()):
			var material = mesh_instance.get_surface_override_material(i)
			if material == null:
				# Get the material from the mesh itself
				var mesh = mesh_instance.mesh
				if mesh != null and mesh.get_surface_count() > i:
					material = mesh.surface_get_material(i)
			
			if material is StandardMaterial3D:
				material = material.duplicate()
				material.metallic = 0.0
				material.roughness = 0.8
				mesh_instance.set_surface_override_material(i, material)
	
	# Recurse to children
	for child in node.get_children():
		_reduce_shininess_recursive(child)

func _anim_name() -> String:
	if _anim_player == null:
		return "<no AnimationPlayer>"
	return String(_anim_player.current_animation)

func _format_names(names: Array[StringName]) -> String:
	var out: Array[String] = []
	out.resize(names.size())
	for i in range(names.size()):
		out[i] = String(names[i])
	return "[" + ", ".join(out) + "]"

func _debug_log(message: String) -> void:
	if not _debug_enabled():
		return
	var now := Time.get_ticks_msec()
	if now < _next_debug_log_time_ms:
		return
	_next_debug_log_time_ms = now + int(debug_log_interval_sec * 1000.0)
	print("[Monster:%s] %s" % [str(get_instance_id()), message])

func _debug_log_force(message: String) -> void:
	if not _debug_enabled():
		return
	print("[Monster:%s] %s" % [str(get_instance_id()), message])

func _debug_enabled() -> bool:
	if debug_animation_logs:
		return true
	return _debug_manager != null and _debug_manager.show_monsters
