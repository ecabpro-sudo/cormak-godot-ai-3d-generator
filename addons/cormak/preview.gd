@tool
extends SubViewportContainer

var _stage: SubViewport


func show_model(packed: PackedScene) -> void:
	clear_model()
	if DisplayServer.get_name() == "headless":
		return
	var model := packed.instantiate()
	if not model is Node3D:
		model.free()
		return
	_stage = SubViewport.new()
	_stage.world_3d = World3D.new()
	_stage.transparent_bg = true
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage)
	_stage.add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.push_front(model)
	if meshes.is_empty():
		clear_model()
		return
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		var world_bounds: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = world_bounds if first else bounds.merge(world_bounds)
		first = false

	var center := bounds.get_center()
	var diameter := bounds.size.length()
	if not center.is_finite() or not is_finite(diameter):
		clear_model()
		return
	# Center and normalize only the independent preview instance.
	var reference := maxf(0.00001, diameter)
	model.position = (model.position - center) / reference
	model.scale /= reference

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.89, 1)
	environment.environment.ambient_light_energy = 0.6
	_stage.add_child(environment)
	var key := DirectionalLight3D.new()
	_stage.add_child(key)
	key.rotation_degrees = Vector3(-35, -45, 0)
	key.light_energy = 1.4
	var camera := Camera3D.new()
	_stage.add_child(camera)
	camera.position = Vector3(1.0, 0.75, 1.45)
	camera.fov = 42.0
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	show()
	_render.call_deferred()


func _ready() -> void:
	resized.connect(_render)
	visibility_changed.connect(_render)


func _render() -> void:
	if _stage != null and is_visible_in_tree():
		_stage.render_target_update_mode = SubViewport.UPDATE_ONCE


func clear_model() -> void:
	hide()
	if _stage != null:
		_stage.free()
		_stage = null
