@tool
extends RefCounted

const Client = preload("res://addons/cormak/client.gd")


static func image_payload(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0 or file.get_length() > 2_250_000:
		return {}
	var bytes := file.get_buffer(file.get_length())
	var header := bytes.slice(0, 12).hex_encode()
	var mime := ""
	if header.begins_with("89504e470d0a1a0a"):
		mime = "image/png"
	elif header.begins_with("ffd8ff"):
		mime = "image/jpeg"
	elif header.begins_with("52494646") and header.ends_with("57454250"):
		mime = "image/webp"
	if mime.is_empty():
		return {}
	return {"data": Marshalls.raw_to_base64(bytes), "mime_type": mime}


static func embedded_glb(bytes: PackedByteArray) -> bool:
	if bytes.size() < 28 or bytes.size() > 100_000_000:
		return false
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 \
			or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return false
	var json_size := bytes.decode_u32(12)
	if json_size <= 0 or json_size > 16_000_000 or json_size % 4 != 0 or 20 + json_size > bytes.size():
		return false
	var manifest: Variant = JSON.parse_string(bytes.slice(20, 20 + json_size).get_string_from_utf8())
	if not manifest is Dictionary:
		return false
	# Only a single, self-contained file may enter the project. No adjacent reads.
	for key in ["images", "buffers"]:
		var entries: Variant = manifest.get(key, [])
		if not entries is Array:
			return false
		for entry in entries:
			if not entry is Dictionary or entry.has("uri"):
				return false
	return true


static func save_model(bytes: PackedByteArray, folder: String, id: String) -> String:
	if not embedded_glb(bytes) or not folder.begins_with("res://") or not Client.uuid_valid(id):
		return ""
	var relative := folder.trim_prefix("res://").trim_suffix("/")
	var parent := "res://"
	if not relative.is_empty():
		for part in relative.split("/", true):
			if part.is_empty() or part.begins_with(".") or part.contains("\\") or part.contains(":"):
				return ""
			var current := DirAccess.open(parent)
			if current == null or current.is_link(part):
				return ""
			if not current.dir_exists(part) and current.make_dir(part) != OK:
				return ""
			parent = parent.path_join(part)
	var path := parent.path_join("cormak_%s_%s.glb" % [id.substr(0, 8), Client.uuid()])
	var sidecar := path + ".import"
	if FileAccess.file_exists(path) or FileAccess.file_exists(sidecar):
		return ""
	var temporary := path + ".part"
	if FileAccess.file_exists(temporary):
		return ""
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.flush()
	var written := file.get_error() == OK and file.get_length() == bytes.size()
	file.close()
	if written and not FileAccess.file_exists(path) and not FileAccess.file_exists(sidecar):
		# Seed only this asset's import options. Extracting PNGs can enqueue
		# nested texture imports; embedding also keeps the project directory tidy.
		var options := ConfigFile.new()
		options.set_value("remap", "importer", "scene")
		options.set_value("remap", "type", "PackedScene")
		options.set_value("params", "gltf/embedded_image_handling", 3) # Embed as Uncompressed.
		options.set_value("params", "gltf/texture_map_mode", 1) # StandardMaterial3D (4.7+).
		if options.save(sidecar) == OK:
			if not FileAccess.file_exists(path) and DirAccess.rename_absolute(temporary, path) == OK:
				return path
			DirAccess.remove_absolute(sidecar)
	DirAccess.remove_absolute(temporary)
	return ""


static func add_to_scene(editor: EditorPlugin, packed: PackedScene, model_scale: float) -> bool:
	var root := editor.get_editor_interface().get_edited_scene_root()
	if not root is Node3D:
		return false
	var instance := packed.instantiate()
	if not instance is Node3D:
		instance.free()
		return false
	instance.scale *= model_scale
	var undo := editor.get_undo_redo()
	undo.create_action("Add Cormak model", UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(root, "add_child", instance, true)
	undo.add_do_property(instance, "owner", root)
	undo.add_do_reference(instance)
	undo.add_undo_method(root, "remove_child", instance)
	undo.commit_action()
	return true
