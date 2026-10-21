// lib/services/lan_socket_manager.dart — PLAN §6.
// Length-prefixed framing: [4B big-endian length][1B type][payload].
// Packet types: 0x01 lobby, 0x02 manifest, 0x03 bytes, 0x04 turn-start,
// 0x05 score, 0x06 timeout. Bonsoir v7 API (initialize/start/stop).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

class PacketType {
  static const int lobby = 0x01;
  static const int manifest = 0x02;
  static const int soundBytes = 0x03;
  static const int turnStart = 0x04;
  static const int score = 0x05;
  static const int timeout = 0x06;
  static const int libraryOffer = 0x07;
  static const int pick = 0x08;
  static const int phase = 0x09;
  static const int matchOver = 0x0A;
  static const int reaction = 0x0B;

  /// Power-up use: client → host request (kind double/volt/shield), and
  /// host → all event line (kind 'event'). JSON payload.
  static const int power = 0x0C;
}

class ReceivedPacket {
  final int type;
  final Uint8List payload;

  /// Which socket it arrived on (host side: identifies the phone).
  final Socket? sender;
  ReceivedPacket(this.type, this.payload, [this.sender]);
}

class DiscoveredRoom {
  final String name;
  final String ip;
  final int port;
  DiscoveredRoom({required this.name, required this.ip, required this.port});
}

class LanSocketManager {
  static const String serviceType = '_mimicparty._tcp';
  static const int defaultPort = 8080;

  ServerSocket? _server;
  Socket? _client;
  final List<Socket> _hostClients = [];
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  Timer? _turnTimeoutTimer;

  bool isRoomLocked = false;

  final _packetController =
      StreamController<ReceivedPacket>.broadcast(sync: true);
  Stream<ReceivedPacket> get packets => _packetController.stream;

  final _roomsController =
      StreamController<List<DiscoveredRoom>>.broadcast(sync: true);
  final List<DiscoveredRoom> _rooms = [];
  Stream<List<DiscoveredRoom>> get rooms => _roomsController.stream;
  List<DiscoveredRoom> get foundRooms => List.unmodifiable(_rooms);

  bool get isHosting => _server != null;
  bool get isConnected => _client != null || _hostClients.isNotEmpty;

  /// Sockets of joined phones (host side). Empty on a client.
  List<Socket> get hostPeers => List.unmodifiable(_hostClients);

  bool get isClient => _client != null;

  /// Close one peer connection (e.g. room full).
  void dropPeer(Socket socket) => _removeSocket(socket);

  /// Client → host JSON.
  void sendToHostJson(Map<String, dynamic> json, int type) {
    final c = _client;
    if (c == null) throw StateError('not connected');
    sendJson(c, type, json);
  }

  /// Client → host raw bytes.
  void sendToHostBytes(Uint8List bytes, int type) {
    final c = _client;
    if (c == null) throw StateError('not connected');
    sendBytes(c, type, bytes);
  }

  // ---------- Host ----------

  Future<void> startHostRoom(String roomName, {int port = defaultPort}) async {
    await stopAll();
    isRoomLocked = false;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    final service =
        BonsoirService(name: roomName, type: serviceType, port: port);
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();

    _server!.listen((Socket client) {
      if (isRoomLocked) {
        client.destroy(); // PLAN §1B: reject late joiners.
        return;
      }
      _hostClients.add(client);
      _attachSocket(client);
    });
  }

  // ---------- Client ----------

  Future<void> startDiscovery() async {
    await _discoverySub?.cancel();
    await _discovery?.stop();
    _rooms.clear();
    _roomsController.add(const []);
    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();
    _discoverySub = _discovery!.eventStream?.listen((event) async {
      if (event is BonsoirDiscoveryServiceFoundEvent) {
        try {
          event.service.resolve(_discovery!.serviceResolver);
        } catch (_) {}
      } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
          event is BonsoirDiscoveryServiceUpdatedEvent) {
        final svc = event.service!;
        final ip = svc.hostAddress;
        if (ip == null) return;
        final idx = _rooms.indexWhere((r) => r.name == svc.name);
        final room = DiscoveredRoom(name: svc.name, ip: ip, port: svc.port);
        if (idx >= 0) {
          _rooms[idx] = room;
        } else {
          _rooms.add(room);
        }
        _roomsController.add(List.unmodifiable(_rooms));
      } else if (event is BonsoirDiscoveryServiceLostEvent) {
        _rooms.removeWhere((r) => r.name == event.service.name);
        _roomsController.add(List.unmodifiable(_rooms));
      }
    });
    await _discovery!.start();
  }

  Future<void> stopDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
  }

  Future<Socket> connectToHost(String hostIp, {int port = defaultPort}) async {
    final socket = await Socket.connect(hostIp, port,
        timeout: const Duration(seconds: 5));
    _client?.destroy();
    _client = socket;
    _attachSocket(socket);
    return socket;
  }

  // ---------- Framing ----------

  final Map<Socket, List<int>> _buffers = {};

  void _attachSocket(Socket socket) {
    _buffers[socket] = [];
    socket.listen(
      (data) => _onData(socket, data),
      onDone: () => _removeSocket(socket),
      onError: (_) => _removeSocket(socket),
      cancelOnError: true,
    );
  }

  void _removeSocket(Socket socket) {
    _buffers.remove(socket);
    _hostClients.remove(socket);
    if (_client == socket) _client = null;
    try {
      socket.destroy();
    } catch (_) {}
  }

  void _onData(Socket socket, List<int> data) {
    final buf = (_buffers[socket] ??= []);
    buf.addAll(data);
    while (buf.length >= 5) {
      final len = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
      if (len < 1 || len > 20 * 1024 * 1024) {
        buf.clear(); // corrupt frame — drop.
        return;
      }
      if (buf.length < 4 + len) return; // wait for full frame.
      final type = buf[4];
      final payload =
          Uint8List.fromList(buf.sublist(5, 4 + len));
      buf.removeRange(0, 4 + len);
      _packetController.add(ReceivedPacket(type, payload, socket));
    }
  }

  void _send(Socket socket, int type, List<int> payload) {
    final len = payload.length + 1;
    final frame = Uint8List(4 + len);
    frame[0] = (len >> 24) & 0xFF;
    frame[1] = (len >> 16) & 0xFF;
    frame[2] = (len >> 8) & 0xFF;
    frame[3] = len & 0xFF;
    frame[4] = type;
    frame.setRange(5, 5 + payload.length, payload);
    socket.add(frame);
  }

  void sendJson(Socket socket, int type, Map<String, dynamic> json) {
    _send(socket, type, utf8.encode(jsonEncode(json)));
  }

  void sendBytes(Socket socket, int type, Uint8List bytes) {
    _send(socket, type, bytes);
  }

  void broadcastJson(int type, Map<String, dynamic> json) {
    final payload = utf8.encode(jsonEncode(json));
    for (final c in List<Socket>.from(_hostClients)) {
      try {
        _send(c, type, payload);
      } catch (_) {}
    }
    if (_client != null) {
      try {
        _send(_client!, type, payload);
      } catch (_) {}
    }
  }

  void broadcastBytes(int type, Uint8List bytes) {
    for (final c in List<Socket>.from(_hostClients)) {
      try {
        _send(c, type, bytes);
      } catch (_) {}
    }
    if (_client != null) {
      try {
        _send(_client!, type, bytes);
      } catch (_) {}
    }
  }

  // ---------- Turn timeout (PLAN §1B: 15 s → skip + 0/100) ----------

  /// [budget] defaults to the plan's 15 s stall limit. A scripted local
  /// turn (listen + 5 s countdown + record) is longer than that, so the
  /// gameplay screen passes a budget that covers the whole turn.
  void startTurn15SecTimeout(
    void Function() onTimeout, {
    Duration budget = const Duration(seconds: 15),
  }) {
    _turnTimeoutTimer?.cancel();
    _turnTimeoutTimer = Timer(budget, onTimeout);
  }

  void cancelTurnTimeout() => _turnTimeoutTimer?.cancel();

  Future<void> stopAll() async {
    _turnTimeoutTimer?.cancel();
    await stopDiscovery();
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    for (final c in List<Socket>.from(_hostClients)) {
      try {
        c.destroy();
      } catch (_) {}
    }
    _hostClients.clear();
    try {
      _client?.destroy();
    } catch (_) {}
    _client = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _buffers.clear();
    isRoomLocked = false;
  }

  void dispose() {
    stopAll();
    _packetController.close();
    _roomsController.close();
  }
}
