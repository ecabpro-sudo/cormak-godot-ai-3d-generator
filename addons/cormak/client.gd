@tool
extends Node

const RESOURCE = "https://mcp.cormak.app/mcp"
const APP = "https://app.cormak.app"
const SCOPES = "account:read studio3d:use studio3d:read"

var _resource: String
var _client_id := ""
var _access := ""
var _refresh := ""
var _expires_at := 0
var _rpc_id := 0


func _init(resource: String = RESOURCE) -> void:
	_resource = resource


func connected() -> bool:
	return not _refresh.is_empty()


func register_client(redirect: String) -> Dictionary:
	var reply := await _send(_resource + "/register", JSON.stringify({
		"client_name": "Cormak AI 3D Generator for Godot",
		"redirect_uris": [redirect],
		"token_endpoint_auth_method": "none",
	}), PackedStringArray(["Content-Type: application/json"]))
	var data := _json(reply)
	var id := str(data.get("client_id", ""))
	if not uuid_valid(id):
		return {"error": data.get("error", "invalid_registration")}
	_client_id = id
	return {}


func authorization_url(redirect: String, challenge: String, state: String) -> String:
	return _resource + "/authorize?" + _form({
		"client_id": _client_id, "redirect_uri": redirect,
		"response_type": "code", "resource": _resource, "scope": SCOPES,
		"state": state, "code_challenge": challenge, "code_challenge_method": "S256",
	})


func exchange(code: String, verifier: String, redirect: String) -> Dictionary:
	return await _token({
		"grant_type": "authorization_code", "code": code,
		"code_verifier": verifier, "redirect_uri": redirect,
	})


func _token(fields: Dictionary) -> Dictionary:
	fields.merge({"client_id": _client_id, "resource": _resource})
	var reply := await _send(_resource + "/token", _form(fields), _form_headers())
	var data := _json(reply)
	var access := str(data.get("access_token", ""))
	var refresh := str(data.get("refresh_token", ""))
	if not _matches(access, "^cmcp_a_[A-Za-z0-9_-]{43}$") \
			or not _matches(refresh, "^cmcp_r_[A-Za-z0-9_-]{43}$"):
		return {"error": data.get("error", "invalid_token_response")}
	_access = access
	_refresh = refresh
	_expires_at = Time.get_ticks_msec() + int(data.get("expires_in", 0)) * 1000
	var granted := str(data.get("scope", "")).split(" ", false)
	for scope in SCOPES.split(" "):
		if not granted.has(scope):
			await sign_out()
			return {"error": "missing_permissions"}
	return {}


func sign_out() -> Dictionary:
	if not connected():
		return {}
	var fields := _form({"token": _refresh, "client_id": _client_id, "resource": _resource})
	_forget()
	var reply := await _send(_resource + "/revoke", fields, _form_headers())
	return {} if reply.get("status") == 200 else {"error": "revocation_unconfirmed"}


func _forget() -> void:
	_access = ""
	_refresh = ""
	_client_id = ""
	_expires_at = 0


func call_tool(tool: String, arguments: Dictionary = {}) -> Dictionary:
	if not connected():
		return {"error": "session_expired"}
	if _expires_at < Time.get_ticks_msec() + 60_000:
		if not await _rotate():
			return {"error": "session_expired"}
	var data := await _rpc(tool, arguments)
	if data.get("error") == "access_unauthorized":
		if not await _rotate():
			return {"error": "session_expired"}
		data = await _rpc(tool, arguments)
		if data.get("error") == "access_unauthorized":
			_forget()
			return {"error": "session_expired"}
	return data


func _rotate() -> bool:
	# A lost refresh response is ambiguous because tokens rotate. Never replay it.
	var result := await _token({"grant_type": "refresh_token", "refresh_token": _refresh})
	if result.has("error"):
		_forget()
		return false
	return true


func _rpc(tool: String, arguments: Dictionary) -> Dictionary:
	_rpc_id += 1
	var id := _rpc_id
	var reply := await _send(_resource, JSON.stringify({
		"jsonrpc": "2.0", "id": id, "method": "tools/call",
		"params": {"name": tool, "arguments": arguments},
	}), PackedStringArray([
		"Content-Type: application/json", "Accept: application/json, text/event-stream",
		"MCP-Protocol-Version: 2025-11-25", "Authorization: Bearer " + _access,
	]))
	if reply.get("status") == 401:
		return {"error": "access_unauthorized"}
	if reply.get("status") == 429:
		return {"error": "rate_limit_reached"}
	if reply.has("error") or int(reply.get("status", 0)) >= 500:
		return {"error": "network_unavailable"}

	var envelope := _json(reply)
	if not envelope.has("id"):
		# The stateless MCP transport may return a single SSE message.
		var body: PackedByteArray = reply.get("body", PackedByteArray())
		for line in body.get_string_from_utf8().split("\n", false):
			if line.begins_with("data:"):
				var candidate: Variant = _parse_json(line.substr(5).strip_edges())
				if candidate is Dictionary and candidate.get("id") == id:
					envelope = candidate
					break
	if envelope.get("id") != id:
		return {"error": "invalid_service_response"}
	var result: Variant = envelope.get("result")
	if not result is Dictionary:
		return {"error": "tool_unavailable"}
	var content: Variant = result.get("structuredContent")
	return content if content is Dictionary else {"error": "invalid_service_response"}


func download(url: String) -> Dictionary:
	# Only the private Cormak Storage bucket; never attach the MCP bearer.
	if not _matches(url, "^https://csjjypcilykmdfiznjoc\\.supabase\\.co/storage/v1/object/sign/studio-models/[^?#]+\\?token=[A-Za-z0-9_.%-]+$"):
		return {"error": "invalid_download_url"}
	return await _send(url, "", PackedStringArray(), HTTPClient.METHOD_GET, 100_000_000, 120.0)


func _send(url: String, body: String, headers: PackedStringArray,
		method: HTTPClient.Method = HTTPClient.METHOD_POST, limit: int = 2_000_000,
		timeout_seconds: float = 30.0) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.max_redirects = 0
	request.body_size_limit = limit
	request.timeout = timeout_seconds
	add_child(request)
	if request.request(url, headers, method, body) != OK:
		request.queue_free()
		return {"error": "network_unavailable"}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "network_unavailable"}
	return {"status": response[1], "body": response[3]}


static func _json(reply: Dictionary) -> Dictionary:
	if reply.has("error"):
		return reply
	var body: PackedByteArray = reply.get("body", PackedByteArray())
	var parsed: Variant = _parse_json(body.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


static func _parse_json(value: String) -> Variant:
	var parser := JSON.new()
	return parser.data if not value.is_empty() and parser.parse(value) == OK else null


static func _form(fields: Dictionary) -> String:
	var pairs := PackedStringArray()
	for key: String in fields:
		pairs.append(key.uri_encode() + "=" + str(fields[key]).uri_encode())
	return "&".join(pairs)


static func _form_headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])


static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.create_from_string(pattern)
	return regex.search(value) != null


static func uuid_valid(value: String) -> bool:
	return _matches(value, "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")


static func uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var value := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		value.substr(0, 8), value.substr(8, 4), value.substr(12, 4),
		value.substr(16, 4), value.substr(20),
	]
