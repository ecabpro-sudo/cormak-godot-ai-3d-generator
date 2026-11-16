@tool
extends ScrollContainer

const Client = preload("res://addons/cormak/client.gd")
const Loopback = preload("res://addons/cormak/loopback.gd")
const Assets = preload("res://addons/cormak/assets.gd")
const Preview = preload("res://addons/cormak/preview.gd")

var editor: EditorPlugin
var _client := Client.new()
var _loop := Loopback.new()
var _poll_timer := Timer.new()
var _layout := VBoxContainer.new()
var _account: Label
var _login: Button
var _logout: Button
var _refresh: Button
var _signup: Button
var _status: Label
var _mode := OptionButton.new()
var _prompt := TextEdit.new()
var _photo_row: HBoxContainer
var _photo_label: Label
var _photo: Dictionary = {}
var _material := OptionButton.new()
var _quality := OptionButton.new()
var _quote: Dictionary = {}
var _cost: Label
var _generate: Button
var _approval: Button
var _pause: Button
var _discard: Button
var _progress := ProgressBar.new()
var _history := ItemList.new()
var _library: Array = []
var _folder := "res://cormak_assets/"
var _folder_button: Button
var _import: Button
var _insert: Button
var _scale := SpinBox.new()
var _preview := Preview.new()
var _packed: PackedScene
var _current_result: Dictionary = {}
var _job: Dictionary = {}
var _job_recovery_id := ""
var _approval_url := ""
var _paused := false
var _busy := false
var _waiting_login := false
var _poll_errors := 0
var _start_failures := 0
var _imports_active := 0


func _ready() -> void:
	add_child(_client)
	add_child(_loop)
	_loop.finished.connect(_finish_login)
	add_child(_poll_timer)
	_poll_timer.one_shot = true
	_poll_timer.timeout.connect(_poll)
	var files := editor.get_editor_interface().get_resource_filesystem()
	files.resources_reimporting.connect(func(_paths: PackedStringArray): _imports_active += 1)
	files.resources_reimported.connect(func(_paths: PackedStringArray):
		_imports_active = maxi(0, _imports_active - 1)
	)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size.x = 295
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(margin)
	margin.add_child(_layout)
	_layout.add_theme_constant_override("separation", 8)

	var brand := _row(_layout)
	var mark := TextureRect.new()
	var logo := Image.new()
	if logo.load_svg_from_string(FileAccess.get_file_as_string("res://addons/cormak/icon.svg")) == OK:
		mark.texture = ImageTexture.create_from_image(logo)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(28, 28)
	brand.add_child(mark)
	var heading := _label(brand, "Cormak AI 3D Generator")
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("#e8ca7b"))

	_account = _label(_layout, "Sign in with your existing Cormak account.")
	_login = _button(_layout, "Login with Cormak", _begin_login)
	var session := _row(_layout)
	_logout = _button(session, "Sign out", _logout_pressed)
	_refresh = _button(session, "Refresh", _refresh_panel)
	_signup = _button(_layout, "Create Free Account", _begin_login)
	_button(_layout, "Upgrade / Buy Credits", func(): OS.shell_open(Client.APP + "/billing"))

	_layout.add_child(HSeparator.new())
	_mode.add_item("Text to 3D")
	_mode.add_item("Image to 3D")
	_mode.item_selected.connect(_mode_changed)
	_layout.add_child(_mode)
	_prompt.placeholder_text = "Describe one object, its shape and materials…"
	_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt.custom_minimum_size.y = 86
	_layout.add_child(_prompt)

	_photo_row = _row(_layout)
	_button(_photo_row, "Choose photo…", _choose_photo)
	_photo_label = _label(_photo_row, "No photo")
	_photo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material.add_item("Keep photo materials")
	_material.add_item("Translucent")
	_material.add_item("Clear")
	_layout.add_child(_material)

	_quality.item_selected.connect(func(_index: int): _quote_changed())
	_layout.add_child(_quality)
	_cost = _label(_layout, "Connect to view available settings and price.")
	_generate = _button(_layout, "Generate…", _confirm_generation)
	_approval = _button(_layout, "Approve in Cormak", _open_approval)
	_pause = _button(_layout, "Pause tracking", _toggle_poll)
	_discard = _button(_layout, "Stop tracking…", _confirm_stop_tracking)
	_progress.custom_minimum_size.y = 22
	_layout.add_child(_progress)
	_status = _label(_layout, "")
	_status.text = "Generate from text or a photo, then import a textured GLB into your project."

	_layout.add_child(HSeparator.new())
	_label(_layout, "Recent models · select a result")
	_history.custom_minimum_size.y = 115
	_history.item_selected.connect(_select_history)
	_layout.add_child(_history)
	_preview.custom_minimum_size = Vector2(0, 140)
	_preview.hide()
	_layout.add_child(_preview)
	_folder_button = _button(_layout, _folder, _choose_folder)
	_import = _button(_layout, "Download & Import GLB", _import_model)
	_scale.min_value = 0.01
	_scale.max_value = 100.0
	_scale.step = 0.01
	_scale.value = 1.0
	_scale.prefix = "Scene scale:"
	_layout.add_child(_scale)
	_insert = _button(_layout, "Add to Scene", _add_to_scene)
	_button(_layout, "Open in Cormak", func(): OS.shell_open(Client.APP + "/3d"))
	_button(_layout, "Open Cormak.app", func(): OS.shell_open("https://cormak.app"))
	_button(_layout, "3D Studio guide", func(): OS.shell_open("https://cormak.app/blog/create-3d-model-with-ai"))
	_mode_changed(0)
	_update()


func _label(parent: Container, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row


func _button(parent: Container, value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _mode_changed(index: int) -> void:
	_photo_row.visible = index == 1
	_material.visible = index == 1
	_prompt.placeholder_text = (
		"Optional texture notes…" if index == 1 else "Describe one object, its shape and materials…"
	)


func _update() -> void:
	var connected := _client.connected()
	_login.visible = not connected
	_login.text = "Cancel login" if _waiting_login else "Login with Cormak"
	_login.disabled = _busy
	_signup.visible = not connected and not _waiting_login
	_signup.disabled = _busy
	_logout.visible = connected
	_logout.disabled = _busy
	_refresh.visible = connected
	_refresh.disabled = _busy
	_generate.disabled = not connected or _busy or _quote.is_empty() or not _job.is_empty() or not _job_recovery_id.is_empty()
	_mode.disabled = _busy
	_quality.disabled = _busy
	_approval.visible = not _approval_url.is_empty()
	_pause.visible = not _job.is_empty() or not _job_recovery_id.is_empty()
	_pause.disabled = _busy
	_discard.visible = _pause.visible and _paused
	_discard.disabled = _busy
	_pause.text = "Resume tracking" if _paused else "Pause tracking"
	_progress.visible = _pause.visible
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE if _busy else Control.MOUSE_FILTER_STOP
	_folder_button.disabled = _busy
	_import.disabled = _busy or not connected or _current_result.get("status") != "succeeded"
	_insert.disabled = _busy or _packed == null


func _set_busy(value: bool) -> void:
	_busy = value
	_update()


func _begin_login() -> void:
	if _waiting_login:
		_loop.stop()
		_waiting_login = false
		_status.text = "Sign-in cancelled."
		_update()
		return
	if not _loop.start():
		_status.text = "Cannot open a local browser callback port."
		return
	_set_busy(true)
	var outcome := await _client.register_client(_loop.redirect)
	if outcome.has("error"):
		_loop.stop()
		_error(outcome)
	elif OS.shell_open(_client.authorization_url(_loop.redirect, _loop.challenge(), _loop.state)) != OK:
		_loop.stop()
		_status.text = "Could not open your browser."
	else:
		_waiting_login = true
		_status.text = "Sign in and grant all three permissions in your browser."
	_set_busy(false)


func _finish_login(code: String, error: String) -> void:
	if not _waiting_login:
		return
	_waiting_login = false
	if not error.is_empty():
		_loop.stop()
		_error({"error": error})
		_update()
		return
	_set_busy(true)
	var verifier := _loop.verifier
	var redirect := _loop.redirect
	_loop.stop()
	var outcome := await _client.exchange(code, verifier, redirect)
	if outcome.has("error"):
		_error(outcome)
	else:
		_status.text = "Connected. Choose a generation mode and quality."
		await _load_panel()
	_set_busy(false)


func _logout_pressed() -> void:
	_set_busy(true)
	var outcome := await _client.sign_out()
	_reset_panel()
	if outcome.has("error"):
		_status.text = "Signed out locally. Disconnect the connection from Cormak → MCP to confirm revocation."
	else:
		_status.text = "Signed out."
	_set_busy(false)


func _reset_panel() -> void:
	_poll_timer.stop()
	_job.clear()
	_job_recovery_id = ""
	_approval_url = ""
	_paused = false
	_poll_errors = 0
	_library.clear()
	_history.clear()
	_current_result.clear()
	_clear_preview()
	_prompt.clear()
	_photo = {}
	_photo_label.text = "No photo"
	_quote = {}
	_quality.clear()
	_cost.text = "Connect to view available settings and price."
	_account.text = "Sign in with your existing Cormak account."


func _refresh_panel() -> void:
	if _busy:
		return
	_set_busy(true)
	await _load_panel()
	_set_busy(false)


func _load_panel() -> void:
	var account := await _client.call_tool("get_account")
	if account.has("error"):
		_error(account)
		return
	_account.text = "Cormak · %s plan · %d AI credits" % [
		str(account.get("plan", "")).capitalize(), int(account.get("available_ai_credits", 0)),
	]
	await _fetch_quote()
	if _client.connected():
		await _load_history()


func _fetch_quote() -> void:
	_quote = {}
	var tier := str(_quality.get_selected_metadata()) if _quality.selected >= 0 else "basic"
	var data := await _client.call_tool("quote_3d", {"quality": tier})
	if data.has("error"):
		_cost.text = "Price unavailable. Use Refresh to try again."
		_error(data)
		return
	var info: Dictionary = data.get("quote", {})
	if str(info.get("quality", "")) != tier or not info.has("maximum"):
		_cost.text = "Price unavailable."
		return
	_quote = info
	if _quality.item_count == 0:
		for option: Dictionary in data.get("qualities", []):
			var id := str(option.get("quality", ""))
			var title := "%s · %s%s" % [
				id.capitalize(), str(option.get("texture", "")).to_upper(),
				" PBR" if option.get("pbr", false) else "",
			]
			_quality.add_item(title)
			_quality.set_item_metadata(_quality.item_count - 1, id)
		for index in range(_quality.item_count):
			if _quality.get_item_metadata(index) == tier:
				_quality.select(index)
	_cost.text = "Meshy 7.1 · up to %d AI credits per model" % int(_quote.maximum)
	var spending: Dictionary = data.get("spending", {})
	if not spending.get("starts_without_approval", false):
		_cost.text += "\nBrowser approval is required."


func _quote_changed() -> void:
	if _busy:
		return
	_set_busy(true)
	await _fetch_quote()
	_set_busy(false)


func _choose_photo() -> void:
	var dialog := FileDialog.new()
	add_child(dialog)
	dialog.title = "Choose an object photo (up to 2.25 MB)"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; PNG, JPEG, WebP"])
	dialog.file_selected.connect(func(path: String):
		_photo = Assets.image_payload(path)
		_photo_label.text = "No photo" if _photo.is_empty() else path.get_file().left(40)
		if _photo.is_empty():
			_status.text = "Choose a PNG, JPEG or WebP file up to 2.25 MB."
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.65)


func _confirm_generation() -> void:
	if _generate.disabled:
		return
	var prompt := _prompt.text.strip_edges()
	var is_photo := _mode.selected == 1
	if prompt.length() > 600 or (not is_photo and prompt.length() < 10) \
			or (is_photo and not prompt.is_empty() and prompt.length() < 3):
		_status.text = "Use 10–600 characters for text, or 3–600 for optional photo notes."
		return
	if is_photo and _photo.is_empty():
		_status.text = "Choose a reference photo first."
		return
	var args := {
		"request_id": Client.uuid(), "confirm_spend": true,
		"expected_max_credits": int(_quote.maximum), "quality": _quote.quality,
		"input_mode": "photo" if is_photo else "prompt",
	}
	if not prompt.is_empty():
		args["prompt"] = prompt
	if is_photo:
		args["images"] = [_photo]
		if _material.selected > 0:
			args["frame_material"] = "translucent" if _material.selected == 1 else "clear"

	var dialog := ConfirmationDialog.new()
	add_child(dialog)
	dialog.title = "Generate with Cormak"
	dialog.dialog_text = "Create one GLB for up to %d AI credits? Failed builds are refunded by Cormak." % int(_quote.maximum)
	_set_busy(true)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		_job = args
		_start_failures = 0
		_paused = false
		_progress.value = 0
		_clear_preview()
		_current_result = {}
		await _start_job()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		_set_busy(false)
	)
	dialog.popup_centered()


func _start_job() -> void:
	_set_busy(true)
	_status.text = "Contacting Cormak…"
	var data := await _client.call_tool("generate_3d", _job)
	if data.has("error"):
		if data.error in ["quote_changed", "insufficient_credits", "invalid_request",
				"invalid_prompt", "invalid_quality", "images_required", "generation_limit_reached"]:
			_clear_job()
			_error(data)
			if data.error == "quote_changed":
				await _fetch_quote()
		else:
			_error(data)
			_start_failures += 1
			if _start_failures >= 4 and not _job.is_empty():
				_paused = true
				_status.text += " Tracking paused. Resume to check the same request."
		_schedule_poll(60.0 if data.get("error") == "rate_limit_reached" else 10.0)
	else:
		_apply_job_status(data)
		_schedule_poll(float(data.get("poll_after_seconds", 10)))
	_set_busy(false)


func _poll() -> void:
	if _paused or (_job.is_empty() and _job_recovery_id.is_empty()):
		return
	if _busy:
		_schedule_poll(2.0)
		return
	_set_busy(true)
	var id := str(_job.get("request_id", _job_recovery_id))
	var data := await _client.call_tool("get_3d_status", {"request_id": id})
	var job_status := str(data.get("status", ""))
	if job_status == "approved" or (data.get("error") == "studio_3d_not_found" and not _job.is_empty()):
		# The same immutable arguments recover a lost start response or consume approval.
		await _start_job()
		return
	if job_status in ["succeeded", "failed", "denied", "expired", "unknown"]:
		_apply_job_status(data)
		_clear_job()
		await _load_panel()
	elif data.has("error"):
		_error(data)
		_poll_errors += 1
		if _poll_errors >= 5:
			_paused = true
			_status.text += " Tracking paused. Use Resume tracking to try again."
	else:
		_poll_errors = 0
		_apply_job_status(data)
	var delay: float = maxf(float(data.get("poll_after_seconds", 10)), 10.0)
	if data.get("error") == "rate_limit_reached":
		delay = 60.0
	elif _poll_errors > 0:
		delay = minf(delay * pow(2.0, _poll_errors), 90.0)
	_schedule_poll(delay)
	_set_busy(false)


func _apply_job_status(data: Dictionary) -> void:
	var job_status := str(data.get("status", ""))
	var url := str(data.get("approval_url", ""))
	_approval_url = url if _safe_approval_url(url) else ""
	_progress.value = clampf(float(data.get("progress", 0)), 0.0, 100.0)
	match job_status:
		"awaiting_confirmation":
			_status.text = "Approve this request in Cormak. Godot will continue when approved."
		"succeeded":
			_clear_preview()
			_current_result = data
			_status.text = "Model ready. Download and import the GLB."
			if data.has("credits_charged"):
				_status.text += " Cormak charged %d AI credits." % int(data.credits_charged)
		"failed":
			_error(data)
			if data.get("refunded") == true:
				_status.text += " Cormak refunded the charge."
		"denied", "expired":
			_status.text = "Approval %s. No generation started." % job_status
		"unknown":
			_status.text = "Outcome unknown. Check 3D Studio before starting another generation."
		_:
			_status.text = "Cormak generation · %s%s" % [
				"working" if job_status.is_empty() else job_status.replace("_", " "),
				" · %d%%" % int(_progress.value) if _progress.value > 0 else "",
			]


func _clear_job() -> void:
	_job = {}
	_job_recovery_id = ""
	_approval_url = ""
	_paused = false
	_poll_errors = 0
	_poll_timer.stop()


func _schedule_poll(seconds: float) -> void:
	if not _paused and (not _job.is_empty() or not _job_recovery_id.is_empty()):
		_poll_timer.start(seconds)


func _toggle_poll() -> void:
	_paused = not _paused
	if _paused:
		_poll_timer.stop()
		_status.text = "Tracking paused. An accepted job can still finish and use credits."
	else:
		_poll_errors = 0
		_start_failures = 0
		_schedule_poll(0.1)
	_update()


func _confirm_stop_tracking() -> void:
	if _busy or not _paused:
		return
	var dialog := ConfirmationDialog.new()
	add_child(dialog)
	dialog.title = "Stop tracking this request?"
	dialog.dialog_text = ("An accepted job can still finish and use credits. "
		+ "Check 3D Studio or Recent models before starting over.")
	_set_busy(true)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		_clear_job()
		_status.text = "Tracking stopped. Check Recent models or open 3D Studio for the result."
		_set_busy(false)
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		_set_busy(false)
	)
	dialog.popup_centered()


func _safe_approval_url(url: String) -> bool:
	var prefix := Client.APP + "/mcp?approval_id="
	return url.begins_with(prefix) and Client.uuid_valid(url.trim_prefix(prefix))


func _open_approval() -> void:
	if _safe_approval_url(_approval_url):
		OS.shell_open(_approval_url)


func _load_history() -> bool:
	var data := await _client.call_tool("list_3d_models", {"limit": 12})
	if data.has("error"):
		_error(data)
		return false
	_library = data.get("items", [])
	_history.clear()
	for item: Dictionary in _library:
		var caption := str(item.get("prompt", "")) if item.get("prompt") != null else ""
		caption = caption.replace("\n", " ").strip_edges().left(70)
		if caption.is_empty():
			caption = "Photo model" if item.get("input_mode") == "photo" else "3D model"
		_history.add_item("%s · %s" % [caption, str(item.get("status", ""))])
	return true


func _select_history(index: int) -> void:
	if _busy or index < 0 or index >= _library.size():
		return
	_clear_preview()
	_current_result = _library[index]
	var selected_status := str(_current_result.get("status", ""))
	var request_id := str(_current_result.get("request_id", ""))
	if selected_status == "succeeded":
		_status.text = "Model selected. Download and import the GLB."
	elif selected_status == "failed":
		_status.text = "This generation failed. Review it in 3D Studio."
	elif _job.is_empty() and _job_recovery_id.is_empty() and Client.uuid_valid(request_id):
		_job_recovery_id = request_id
		_paused = false
		_schedule_poll(0.1)
	else:
		_status.text = "Finish tracking the current request first."
	_update()


func _choose_folder() -> void:
	var dialog := EditorFileDialog.new()
	add_child(dialog)
	dialog.title = "Choose a folder inside this Godot project"
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.dir_selected.connect(func(path: String):
		_folder = path
		_folder_button.text = path
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.65)


func _import_model() -> void:
	if _import.disabled:
		return
	_set_busy(true)
	_clear_preview()
	var id := str(_current_result.get("id", ""))
	var direct_url := str(_current_result.get("model_url", ""))
	var url := ""
	_status.text = "Getting a fresh private GLB link…"
	if not direct_url.is_empty() and _current_result.has("request_id"):
		var data := await _client.call_tool("get_3d_status", {"request_id": _current_result.request_id})
		if data.has("error"):
			_error(data)
			_set_busy(false)
			return
		url = str(data.get("model_url", ""))
	else:
		# Saved models may originate in another editor session or in the web studio.
		# Refresh the list to avoid downloading with an expired signed link.
		if not await _load_history():
			_set_busy(false)
			return
		for item: Dictionary in _library:
			if item.get("id") == id:
				var urls: Array = item.get("glb_urls", [])
				if not urls.is_empty():
					url = str(urls[0])
				break
	if url.is_empty():
		_status.text = "No GLB link is available. Refresh or open the model in Cormak."
		_set_busy(false)
		return
	_status.text = "Downloading GLB…"
	var reply := await _client.download(url)
	if reply.get("status") != 200:
		_status.text = "Could not download GLB. Try Download & Import again for a fresh link."
		_set_busy(false)
		return
	var path := Assets.save_model(reply.body, _folder, id)
	if path.is_empty():
		_status.text = "Could not save a self-contained GLB in this project folder."
		_set_busy(false)
		return
	_status.text = "Importing %s…" % path.get_file()
	var files := editor.get_editor_interface().get_resource_filesystem()
	var deadline := Time.get_ticks_msec() + 45_000
	var scan_requested := false
	while Time.get_ticks_msec() < deadline:
		if _filesystem_idle(files):
			if _has_imported_scene(path):
				# Textures may trigger follow-up imports on the next editor frame.
				await get_tree().create_timer(0.4).timeout
				if _filesystem_idle(files):
					_packed = ResourceLoader.load(path, "PackedScene") as PackedScene
					break
			elif not scan_requested:
				scan_requested = true
				files.scan()
		await get_tree().create_timer(0.3).timeout
	if _packed != null:
		_status.text = "Imported %s. Open a 3D scene to add it." % path
		_preview.show_model(_packed)
	else:
		_status.text = "GLB saved to %s. Godot did not finish importing it; check the FileSystem dock." % path
	_set_busy(false)


func _has_imported_scene(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		return false
	var imported_path := str(config.get_value("remap", "path", ""))
	return not imported_path.is_empty() and FileAccess.file_exists(imported_path)


func _filesystem_idle(files: EditorFileSystem) -> bool:
	return not files.is_scanning() and _imports_active == 0 \
		and (not files.has_method("is_importing") or not bool(files.call("is_importing")))


func _clear_preview() -> void:
	_packed = null
	_preview.clear_model()


func _add_to_scene() -> void:
	if _packed == null:
		return
	if Assets.add_to_scene(editor, _packed, float(_scale.value)):
		_status.text = "Added to the current scene. Use Undo to remove the instance."
	else:
		_status.text = "Open a scene with a Node3D root and try again."


func _error(data: Dictionary) -> void:
	var code := str(data.get("error", "unknown"))
	match code:
		"session_expired":
			_reset_panel()
			_status.text = "Session expired. Sign in again and check Recent models before generating."
		"missing_permissions":
			_status.text = "Allow all three requested permissions when connecting to Cormak."
		"insufficient_credits":
			_status.text = "Not enough AI credits. Use Upgrade / Buy Credits or choose a lower quality."
		"quote_changed":
			_status.text = "The price changed. Review the updated quote before generating."
		"login_denied", "login_timed_out":
			_status.text = "Sign-in was not completed. Start Login with Cormak again."
		"network_unavailable":
			_status.text = "Cormak could not be reached. Active requests keep their original ID."
		"rate_limit_reached":
			_status.text = "Request limit reached. Please wait a minute."
		_:
			if not Client._matches(code, "^[a-z0-9_]{1,64}$"):
				code = "unknown"
			_status.text = "Cormak could not complete this action (%s)." % code
