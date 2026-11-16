@tool
extends Node

signal finished(code: String, error: String)

const Client = preload("res://addons/cormak/client.gd")
const CALLBACK = "/cormak/callback"

var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _buffer := PackedByteArray()
var _deadline := 0
var _peer_deadline := 0
var _port := 0
var state := ""
var verifier := ""
var redirect := ""


func start() -> bool:
	var crypto := Crypto.new()
	for attempt in range(24):
		var entropy := crypto.generate_random_bytes(2)
		_port = 49152 + (entropy.decode_u16(0) % 16384)
		if _server.listen(_port, "127.0.0.1") == OK:
			break
	if not _server.is_listening():
		return false
	state = _base64url(crypto.generate_random_bytes(32))
	verifier = _base64url(crypto.generate_random_bytes(32))
	redirect = "http://127.0.0.1:%d%s" % [_port, CALLBACK]
	_deadline = Time.get_ticks_msec() + 300_000
	return true


func challenge() -> String:
	return _base64url(verifier.sha256_buffer())


func stop() -> void:
	_reset_peer()
	_server.stop()
	state = ""
	verifier = ""
	redirect = ""


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	var now := Time.get_ticks_msec()
	if now >= _deadline:
		stop()
		finished.emit("", "login_timed_out")
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_peer_deadline = now + 2000
	if _peer == null:
		return
	_peer.poll()
	if now >= _peer_deadline or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_reset_peer()
		return
	var available := _peer.get_available_bytes()
	if available == 0:
		return
	if available + _buffer.size() > 8192:
		_respond(false)
		return
	var packet := _peer.get_data(available)
	if packet[0] != OK:
		_reset_peer()
		return
	_buffer.append_array(packet[1])
	var request := _buffer.get_string_from_ascii()
	if not request.contains("\r\n\r\n"):
		return
	var lines := request.split("\r\n")
	var first := lines[0].split(" ")
	var host := ""
	for line in lines:
		if line.to_lower().begins_with("host:"):
			host = line.substr(5).strip_edges()
	if first.size() != 3 or first[0] != "GET" or host != "127.0.0.1:%d" % _port:
		_respond(false)
		return
	var path := first[1].split("?", true, 1)
	if path.size() != 2 or path[0] != CALLBACK:
		_respond(false)
		return
	var query := {}
	for item in path[1].split("&"):
		var fields := item.split("=", true, 1)
		if fields.size() != 2 or query.has(fields[0].uri_decode()):
			_respond(false)
			return
		query[fields[0].uri_decode()] = fields[1].uri_decode()
	if query.get("state") != state:
		_respond(false)
		return
	var code := str(query.get("code", ""))
	var denied: bool = query.get("error") == "access_denied" and code.is_empty()
	if not denied and not Client._matches(code, "^cmcp_c_[A-Za-z0-9_-]{43}$"):
		_respond(false)
		return
	_respond(true)
	_server.stop()
	finished.emit(code, "login_denied" if denied else "")


func _reset_peer() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	_buffer.clear()


func _respond(accepted: bool) -> void:
	var message := ("You can close this tab and return to the Godot editor."
		if accepted else "This is not a valid Cormak sign-in callback.")
	var status := "200 OK" if accepted else "400 Bad Request"
	var response := ("HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\n"
		+ "Content-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n"
		+ "Referrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\n\r\n%s")
	_peer.put_partial_data((response % [status, message.length(), message]).to_utf8_buffer())
	_reset_peer()


static func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")
