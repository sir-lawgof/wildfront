class_name NetSession
extends Node
## LAN multiplayer over ENet. The host runs the authoritative MatchServer; clients
## send intents and receive per-player snapshots (GDD 11 networking model).
## Lives at a fixed node path (/root/Main/Net) on every machine so RPCs line up.

signal lobby_changed(players: Array)
signal match_started(cfg: Dictionary, link: Node)
signal status(text: String)

const PORT := 24600

var is_host: bool = false
var lobby: Dictionary = {}          ## peer id -> {name, class_def, levels}
var server: MatchServer             ## host only
var link: RemoteLink                ## client only
var my_info: Dictionary = {}
var _summaries_sent: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Could not connect."); close())
	multiplayer.server_disconnected.connect(_on_server_gone)


func active() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func host(info: Dictionary) -> Error:
	close()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, 9)
	if err != OK:
		status.emit("Could not host on port %d (error %d)." % [PORT, err])
		return err
	multiplayer.multiplayer_peer = p
	is_host = true
	my_info = info
	lobby = {1: info}
	status.emit("Hosting on port %d. Other players join with your IP: %s" % [PORT, ", ".join(_local_ips())])
	_broadcast_lobby()
	return OK


func join(ip: String, info: Dictionary) -> Error:
	close()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, PORT)
	if err != OK:
		status.emit("Could not start client (error %d)." % err)
		return err
	multiplayer.multiplayer_peer = p
	is_host = false
	my_info = info
	status.emit("Connecting to %s:%d ..." % [ip, PORT])
	return OK


func close() -> void:
	if server != null:
		server.queue_free()
		server = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	lobby.clear()


func _local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


# ---------------------------------------------------------------- lobby

func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if is_host:
		lobby.erase(id)
		_broadcast_lobby()


func _on_connected() -> void:
	status.emit("Connected. Waiting for the host to start.")
	register.rpc_id(1, my_info)


func _on_server_gone() -> void:
	status.emit("Host disconnected.")
	if link != null:
		link.host_lost()
		link = null
	close()


@rpc("any_peer", "reliable")
func register(info: Dictionary) -> void:
	if not is_host:
		return
	lobby[multiplayer.get_remote_sender_id()] = info
	_broadcast_lobby()


func _lobby_list() -> Array:
	var out: Array = []
	for pid in lobby:
		out.append({"peer": pid, "name": str(lobby[pid].get("name", "?")), "cl": Progression.combat_level(
			int(lobby[pid].get("levels", {}).get("melee", 1)), int(lobby[pid].get("levels", {}).get("ranged", 1)), int(lobby[pid].get("levels", {}).get("magic", 1)))})
	return out


func _broadcast_lobby() -> void:
	var l := _lobby_list()
	lobby_changed.emit(l)
	if active():
		lobby_update.rpc(l)


@rpc("authority", "reliable")
func lobby_update(list: Array) -> void:
	lobby_changed.emit(list)


# ---------------------------------------------------------------- match (host)

func start_match(cfg: Dictionary) -> void:
	if not is_host:
		return
	cfg = cfg.duplicate()
	var players: Array = []
	var order: Array = lobby.keys()
	order.sort()
	for pid in order:
		var p: Dictionary = (lobby[pid] as Dictionary).duplicate()
		p["peer"] = pid
		players.append(p)
	cfg["players"] = players
	cfg.erase("player")
	_summaries_sent = false
	server = MatchServer.new()
	server.cfg = cfg
	add_child(server)
	server.tick_completed.connect(_on_server_tick)
	match_started.emit(cfg, server)


func _on_server_tick() -> void:
	if server == null:
		return
	var core := server.core
	for peer in core.peer_to_fid:
		if int(peer) == 1:
			continue
		var fid: int = core.peer_to_fid[peer]
		var snap := core.sim.snapshot(fid)
		if core.sim.tick == 0:
			client_match_started.rpc_id(int(peer), server.cfg, snap)
		else:
			recv_snapshot.rpc_id(int(peer), snap)
	if core.sim.phase == "over" and not _summaries_sent:
		_summaries_sent = true
		for peer in core.peer_to_fid:
			if int(peer) != 1:
				recv_summary.rpc_id(int(peer), core.summary(false, int(core.peer_to_fid[peer])))


@rpc("any_peer", "reliable")
func host_intent(intent: Dictionary) -> void:
	if not is_host or server == null:
		return
	var fid := int(server.core.peer_to_fid.get(multiplayer.get_remote_sender_id(), -1))
	if fid != -1:
		server.core.submit(fid, intent)


@rpc("any_peer", "reliable")
func host_class(class_def: Dictionary, levels: Dictionary) -> void:
	if not is_host or server == null:
		return
	var fid := int(server.core.peer_to_fid.get(multiplayer.get_remote_sender_id(), -1))
	if fid != -1:
		server.core.change_class(fid, class_def, levels)


@rpc("any_peer", "reliable")
func host_leave() -> void:
	if not is_host or server == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var fid := int(server.core.peer_to_fid.get(sender, -1))
	if fid != -1:
		recv_summary.rpc_id(sender, server.core.summary(true, fid))


# ---------------------------------------------------------------- match (client)

@rpc("authority", "reliable")
func client_match_started(cfg: Dictionary, first: Dictionary) -> void:
	link = RemoteLink.new()
	add_child(link)
	link.setup(self, first)
	match_started.emit(cfg, link)


@rpc("authority", "reliable")
func recv_snapshot(s: Dictionary) -> void:
	if link != null:
		link.on_snapshot(s)


@rpc("authority", "reliable")
func recv_summary(s: Dictionary) -> void:
	if link != null:
		link.on_summary(s)


func send_intent_to_host(intent: Dictionary) -> void:
	host_intent.rpc_id(1, intent)


func send_class_to_host(class_def: Dictionary, levels: Dictionary) -> void:
	host_class.rpc_id(1, class_def, levels)


func send_leave_to_host() -> void:
	host_leave.rpc_id(1)
