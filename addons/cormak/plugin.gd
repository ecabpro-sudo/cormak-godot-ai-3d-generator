@tool
extends EditorPlugin

const Dock = preload("res://addons/cormak/dock.gd")

var _dock: Control
var _editor_dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Cormak"
	_dock.editor = self
	# EditorDock was added in 4.6. Keep 4.3–4.5 able to parse this script.
	if has_method("add_dock") and ClassDB.can_instantiate("EditorDock"):
		_editor_dock = ClassDB.instantiate("EditorDock") as Control
		_editor_dock.name = "CormakEditorDock"
		_editor_dock.set("title", "Cormak")
		_editor_dock.set("layout_key", "cormak_ai_3d_generator")
		_editor_dock.set("default_slot", ClassDB.class_get_integer_constant(
			"EditorDock", "DOCK_SLOT_RIGHT_BL"
		))
		_editor_dock.add_child(_dock)
		_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		call("add_dock", _editor_dock)
	else:
		add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if is_instance_valid(_editor_dock):
		call("remove_dock", _editor_dock)
		_editor_dock.free()
	elif is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.free()
