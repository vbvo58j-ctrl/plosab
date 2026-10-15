import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';

class ReceivedAttachment {
  final String name;
  final String path;
  final int size;
  final DateTime receivedAt;
  final String mimeType;
  final bool isOutgoing;
  const ReceivedAttachment({required this.name, required this.path, required this.size, required this.receivedAt, this.mimeType = 'application/octet-stream', this.isOutgoing = false});
  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'size': size, 'receivedAt': receivedAt.toIso8601String(), 'mimeType': mimeType, 'isOutgoing': isOutgoing};
  factory ReceivedAttachment.fromJson(Map<String, dynamic> json) => ReceivedAttachment(name: json['name'] as String? ?? 'file', path: json['path'] as String? ?? '', size: (json['size'] as num?)?.toInt() ?? 0, receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ?? DateTime.now(), mimeType: json['mimeType'] as String? ?? 'application/octet-stream', isOutgoing: json['isOutgoing'] as bool? ?? false);
}

class _Peer {
  final dynamic connection;
  StreamSubscription<dynamic>? subscription;
  _Peer(this.connection);
}

class _IncomingFile {
  final String id;
  final String name;
  final int size;
  final String mimeType;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  _IncomingFile(this.id, this.name, this.size, this.mimeType);
}

class BluetoothChatService {
  BluetoothChatService() : _bluetooth = FlutterClassicBluetooth();
  final FlutterClassicBluetooth _bluetooth;
  final _messages = StreamController<ChatMessage>.broadcast();
  final _status = StreamController<String>.broadcast();
  final _devices = StreamController<List<dynamic>>.broadcast();
  final _attachments = StreamController<ReceivedAttachment>.broadcast();
  final Set<String> _seenIds = <String>{};
  final Map<String, _IncomingFile> _incomingFiles = <String, _IncomingFile>{};
  final List<_Peer> _serverPeers = <_Peer>[];
  dynamic _connection;
  dynamic _server;
  StreamSubscription<dynamic>? _clientSub;
  StreamSubscription<dynamic>? _serverSub;
  StreamSubscription<dynamic>? _stateSub;
  bool _scanning = false;
  bool _connecting = false;
  bool _disposed = false;

  Stream<ChatMessage> get onMessageReceived => _messages.stream;
  Stream<String> get onStatusChanged => _status.stream;
  Stream<List<dynamic>> get onDevicesChanged => _devices.stream;
  Stream<ReceivedAttachment> get onAttachmentReceived => _attachments.stream;
  bool get isConnected {
    try { if (_connection != null && _connection.isConnected == true) return true; } catch (_) {}
    return _serverPeers.any((p) { try { return p.connection.isConnected == true; } catch (_) { return true; } });
  }

  Future<void> scanDevices() async {
    if (_disposed || _scanning) return;
    _scanning = true;
    _status.add('جارٍ البحث عن الأجهزة...');
    try {
      final permission = await _bluetooth.checkPermissions();
      if (permission != BtcPermissionStatus.granted && permission != BtcPermissionStatus.notRequired) {
        final result = await _bluetooth.requestPermissions();
        if (result != BtcPermissionStatus.granted && result != BtcPermissionStatus.notRequired) throw Exception('يجب السماح بأذونات البلوتوث.');
      }
      if (!await _bluetooth.isEnabled()) throw Exception('شغّل البلوتوث من إعدادات الهاتف.');
      final found = await _bluetooth.scan(timeout: const Duration(seconds: 12));
      if (_disposed) return;
      _devices.add(found);
      _status.add('اكتمل البحث: ${found.length} جهاز');
    } catch (e) {
      if (!_disposed) _status.add('تعذر البحث عن الأجهزة: $e');
      rethrow;
    } finally { _scanning = false; }
  }

  Future<void> connectToDevice(String address) async {
    if (_disposed || _connecting) return;
    if (isConnected) throw StateError('يوجد اتصال نشط بالفعل.');
    _connecting = true;
    _status.add('جارٍ الاتصال...');
    try {
      final conn = await _bluetooth.connect(address: address, secure: true, timeout: const Duration(seconds: 20));
      if (_disposed) { await conn.close(); conn.dispose(); return; }
      _connection = conn;
      _clientSub = conn.input.lines().listen((line) => _handleLine(line), onError: (_) { if (!_disposed) _status.add('حدث خطأ في استقبال البيانات.'); }, onDone: () { if (!_disposed) _status.add('انقطع الاتصال.'); });
      _stateSub = conn.stateStream.listen((state) { if (!_disposed) _status.add(state.name == 'connected' ? 'متصل' : 'حالة الاتصال: ${state.name}'); });
      _status.add('متصل بنجاح');
    } catch (e) { _status.add('فشل الاتصال: $e'); rethrow; }
    finally { _connecting = false; }
  }

  Future<void> startListening() async {
    if (_disposed || _server != null) return;
    _status.add('جارٍ تشغيل استقبال الاتصالات...');
    try {
      final server = await _bluetooth.startServer(serviceName: 'BlousabChat', secure: true);
      if (_disposed) { await server.close(); return; }
      _server = server;
      _serverSub = server.connections.listen((conn) {
        if (_disposed) return;
        final peer = _Peer(conn);
        _serverPeers.add(peer);
        peer.subscription = conn.input.lines().listen((line) => _handleLine(line), onError: (_) {}, onDone: () { _serverPeers.remove(peer); if (!_disposed) _status.add('انقطع اتصال الجهاز.'); });
        _status.add('اتصل جهاز: ${conn.address}');
      }, onError: (e) { if (!_disposed) _status.add('خطأ في خدمة الاستقبال: $e'); });
      _status.add('جاهز لاستقبال الاتصالات');
    } catch (e) { _status.add('تعذر تشغيل الاستقبال: $e'); rethrow; }
  }

  dynamic _activeConnection() {
    try { if (_connection != null && _connection.isConnected == true) return _connection; } catch (_) {}
    for (final p in _serverPeers.reversed) {
      try { if (p.connection.isConnected == true) return p.connection; } catch (_) { return p.connection; }
    }
    if (_serverPeers.isNotEmpty) return _serverPeers.last.connection;
    return null;
  }

  Future<void> _write(Map<String, dynamic> payload) async {
    final conn = _activeConnection();
    if (conn == null) throw StateError('لا يوجد جهاز متصل.');
    await conn.output.writeLine(jsonEncode(payload));
  }

  Future<void> sendMessage(String senderId, String text) async {
    if (_disposed) throw StateError('الخدمة مغلقة.');
    final msg = ChatMessage(id: '${DateTime.now().microsecondsSinceEpoch}-$senderId', senderId: senderId, text: text, timestamp: DateTime.now());
    await _write(<String, dynamic>{'type': 'text', ...msg.toJson()});
  }

  /// Sends files as base64 chunks over the Bluetooth Classic text stream.
  /// This is a simple protocol; very large files consume memory on both phones.
  Future<void> sendFile({required String path, required String fileName, required String senderId, String mimeType = 'application/octet-stream'}) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('الملف غير موجود.');
    final bytes = await file.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) throw Exception('الحد الأقصى للملف في هذه النسخة 25 ميجابايت.');
    final id = '${DateTime.now().microsecondsSinceEpoch}-$senderId';
    const chunkSize = 18 * 1024;
    final total = (bytes.length / chunkSize).ceil();
    await _write({'type': 'file_start', 'id': id, 'name': fileName, 'size': bytes.length, 'mime': mimeType, 'total': total});
    for (var i = 0; i < total; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize < bytes.length) ? start + chunkSize : bytes.length;
      await _write({'type': 'file_chunk', 'id': id, 'index': i, 'data': base64Encode(bytes.sublist(start, end))});
    }
    await _write({'type': 'file_end', 'id': id});
    _status.add('تم إرسال الملف: $fileName');
  }

  void _handleLine(String line) {
    if (_disposed || line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'];
      if (type == 'file_start') {
        final id = decoded['id']?.toString() ?? '';
        final name = decoded['name']?.toString() ?? 'received_file';
        final size = decoded['size'] is int ? decoded['size'] as int : -1;
        if (id.isEmpty || size < 0 || size > 25 * 1024 * 1024) return;
        final mime = decoded['mime']?.toString() ?? 'application/octet-stream';
        _incomingFiles[id] = _IncomingFile(id, name.replaceAll(RegExp(r'[/\\]'), '_'), size, mime);
        return;
      }
      if (type == 'file_chunk') {
        final id = decoded['id']?.toString() ?? '';
        final item = _incomingFiles[id];
        if (item == null) return;
        final data = decoded['data']?.toString() ?? '';
        final chunk = base64Decode(data);
        if (item.bytes.length + chunk.length > item.size) { _incomingFiles.remove(id); return; }
        item.bytes.add(chunk);
        return;
      }
      if (type == 'file_end') {
        final id = decoded['id']?.toString() ?? '';
        final item = _incomingFiles.remove(id);
        if (item == null) return;
        unawaited(_saveIncoming(item));
        return;
      }
      final message = ChatMessage.fromJson(decoded);
      if (message.id.isEmpty || message.senderId.isEmpty || message.text.length > 10000 || !_seenIds.add(message.id)) return;
      _messages.add(message);
    } catch (_) { if (!_disposed) _status.add('تعذر تفسير بيانات مستلمة.'); }
  }

  Future<void> _saveIncoming(_IncomingFile item) async {
    try {
      final bytes = item.bytes.takeBytes();
      if (bytes.length != item.size) throw Exception('حجم الملف غير مكتمل');
      final dir = await getApplicationDocumentsDirectory();
      final safeName = '${DateTime.now().millisecondsSinceEpoch}_${item.name}';
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      if (!_disposed) {
        _attachments.add(ReceivedAttachment(name: item.name, path: file.path, size: bytes.length, receivedAt: DateTime.now(), mimeType: item.mimeType));
        _status.add('تم استلام الملف: ${item.name}');
      }
    } catch (e) { if (!_disposed) _status.add('فشل حفظ الملف المستلم: $e'); }
  }

  Future<void> disconnect() async {
    final conn = _connection; _connection = null;
    await _clientSub?.cancel(); _clientSub = null;
    await _stateSub?.cancel(); _stateSub = null;
    if (conn != null) { try { await conn.close(); } finally { conn.dispose(); } }
    if (!_disposed) _status.add('غير متصل');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _clientSub?.cancel(); await _stateSub?.cancel(); await _serverSub?.cancel();
    for (final peer in _serverPeers) {
      await peer.subscription?.cancel();
      try { await peer.connection.close(); } catch (_) {}
      try { peer.connection.dispose(); } catch (_) {}
    }
    _serverPeers.clear();
    final conn = _connection; _connection = null;
    if (conn != null) { try { await conn.close(); } catch (_) {} try { conn.dispose(); } catch (_) {} }
    final server = _server; _server = null;
    if (server != null) { try { await server.close(); } catch (_) {} }
    await _messages.close(); await _status.close(); await _devices.close(); await _attachments.close();
  }
}
