import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../services/bluetooth_chat_service.dart';

class ChatScreen extends StatefulWidget {
  final BluetoothChatService chatService;
  final String myUserId;
  final String deviceName;
  const ChatScreen({super.key, required this.chatService, required this.myUserId, required this.deviceName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<ReceivedAttachment> _files = [];
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<ReceivedAttachment>? _fileSub;
  String _status = 'غير متصل';
  bool _sending = false;
  String? _wallpaperPath;
  String get _keySuffix => base64Url.encode(utf8.encode(widget.deviceName)).replaceAll('=', '');
  String get _historyKey => 'chat_history_$_keySuffix';
  String get _filesKey => 'chat_files_$_keySuffix';

  @override
  void initState() {
    super.initState();
    _status = widget.chatService.isConnected ? 'متصل' : 'غير متصل';
    _loadSavedData();
    _messageSub = widget.chatService.onMessageReceived.listen((m) {
      if (!mounted) return;
      if (_messages.any((x) => x.id == m.id)) return;
      setState(() => _messages.add(m));
      _saveHistory();
      _scrollBottom();
    });
    _statusSub = widget.chatService.onStatusChanged.listen((s) { if (mounted) setState(() => _status = s); });
    _fileSub = widget.chatService.onAttachmentReceived.listen((f) {
      if (!mounted) return;
      setState(() => _files.add(f));
      _saveFiles();
      _notice('تم استلام الملف وحفظه: ${f.name}');
    });
  }

  Future<void> _loadSavedData() async {
    try {
      final p = await SharedPreferences.getInstance();
      final messages = <ChatMessage>[];
      for (final raw in p.getStringList(_historyKey) ?? <String>[]) {
        try { messages.add(ChatMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>)); } catch (_) {}
      }
      final files = <ReceivedAttachment>[];
      for (final raw in p.getStringList(_filesKey) ?? <String>[]) {
        try {
          final item = ReceivedAttachment.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (item.path.isNotEmpty && await File(item.path).exists()) files.add(item);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _messages..clear()..addAll(messages);
        _files..clear()..addAll(files);
        _wallpaperPath = p.getString('chatWallpaperPath');
      });
      _scrollBottom();
    } catch (_) { if (mounted) _notice('تعذر تحميل بعض عناصر السجل المحفوظ.'); }
  }

  Future<void> _saveHistory() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_historyKey, _messages.map((m) => jsonEncode(m.toJson())).toList());
    } catch (_) { if (mounted) _notice('تعذر حفظ سجل الرسائل.'); }
  }

  Future<void> _saveFiles() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_filesKey, _files.map((f) => jsonEncode(f.toJson())).toList());
    } catch (_) { if (mounted) _notice('تعذر حفظ سجل الملفات.'); }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (!widget.chatService.isConnected) { _notice('لا يوجد جهاز متصل.'); return; }
    setState(() => _sending = true);
    try {
      await widget.chatService.sendMessage(widget.myUserId, text);
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(id: 'local-${DateTime.now().microsecondsSinceEpoch}', senderId: widget.myUserId, text: text, timestamp: DateTime.now())));
      await _saveHistory();
      _controller.clear();
      _scrollBottom();
    } catch (e) { if (mounted) _notice('تعذر الإرسال: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _pickImage({required bool video}) async {
    try {
      final picker = ImagePicker();
      final file = video ? await picker.pickVideo(source: ImageSource.gallery) : await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (file != null) await _sendFile(file.path, file.name, video ? 'video/${_extension(file.name)}' : 'image/${_extension(file.name)}');
    } catch (e) { if (mounted) _notice('تعذر اختيار الوسائط: $e'); }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      if (f.path == null) { _notice('تعذر الوصول إلى مسار الملف.'); return; }
      await _sendFile(f.path!, f.name, 'application/octet-stream');
    } catch (e) { if (mounted) _notice('تعذر اختيار الملف: $e'); }
  }

  String _extension(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : 'octet-stream';

  Future<void> _sendFile(String path, String name, String mime) async {
    if (!widget.chatService.isConnected) { _notice('اتصل بالجهاز الآخر أولًا.'); return; }
    try {
      final original = File(path);
      if (!await original.exists()) { _notice('الملف غير موجود.'); return; }
      final size = await original.length();
      if (size > 25 * 1024 * 1024) { _notice('الحد الأقصى لحجم الملف 25 ميجابايت.'); return; }
      setState(() => _sending = true);
      // Copy to app storage so the local file-history entry remains available after the source is moved.
      final dir = await getApplicationDocumentsDirectory();
      final ext = name.contains('.') ? '.${name.split('.').last}' : '';
      final stored = File('${dir.path}/sent_${DateTime.now().millisecondsSinceEpoch}$ext');
      await original.copy(stored.path);
      await widget.chatService.sendFile(path: stored.path, fileName: name, senderId: widget.myUserId, mimeType: mime);
      if (!mounted) return;
      setState(() => _files.add(ReceivedAttachment(name: name, path: stored.path, size: size, receivedAt: DateTime.now(), mimeType: mime, isOutgoing: true)));
      await _saveFiles();
      _notice('أُرسل الملف: $name');
    } catch (e) { if (mounted) _notice('فشل إرسال الملف: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _attachments() async {
    await showModalBottomSheet<void>(context: context, builder: (ctx) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo), title: const Text('صورة'), onTap: () { Navigator.pop(ctx); _pickImage(video: false); }),
      ListTile(leading: const Icon(Icons.videocam), title: const Text('فيديو'), onTap: () { Navigator.pop(ctx); _pickImage(video: true); }),
      ListTile(leading: const Icon(Icons.insert_drive_file), title: const Text('ملف أو مستند'), onTap: () { Navigator.pop(ctx); _pickDocument(); }),
    ])));
  }

  Future<void> _openAttachment(ReceivedAttachment f) async {
    final file = File(f.path);
    if (!await file.exists()) { if (mounted) _notice('الملف لم يعد موجودًا على الجهاز.'); return; }
    if (f.mimeType.startsWith('image/')) {
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [
        AppBar(title: Text(f.name), automaticallyImplyLeading: false, actions: [IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        Flexible(child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('تعذر عرض الصورة'))))),
        Padding(padding: const EdgeInsets.all(8), child: Text('${(f.size / 1024).toStringAsFixed(1)} KB')),
      ])));
    } else {
      final result = await OpenFilex.open(f.path);
      if (mounted && result.type != ResultType.done) _notice('تعذر فتح الملف: ${result.message}');
    }
  }

  void _scrollBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }); }
  void _notice(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  @override
  void dispose() { _messageSub?.cancel(); _statusSub?.cancel(); _fileSub?.cancel(); _controller.dispose(); _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.deviceName, style: const TextStyle(fontSize: 17)), Text(_status, style: const TextStyle(fontSize: 12))]), actions: [IconButton(tooltip: 'إرفاق صورة أو ملف', onPressed: _attachments, icon: const Icon(Icons.attach_file))]),
    body: Column(children: [
      Expanded(child: Container(
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, image: _wallpaperPath != null && File(_wallpaperPath!).existsSync() ? DecorationImage(image: FileImage(File(_wallpaperPath!)), fit: BoxFit.cover, opacity: .22) : null),
        child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
          if (_messages.isEmpty && _files.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('ابدأ المحادثة بإرسال رسالة أو ملف'))),
          ..._messages.map((m) {
            final mine = m.senderId == widget.myUserId;
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78), margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: mine ? const Color(0xFFDCF8C6) : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Align(alignment: Alignment.centerLeft, child: Text(m.text)), const SizedBox(height: 4), Text('${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, color: Colors.grey))])));
          }),
          ..._files.map((f) => Card(child: ListTile(
            leading: Icon(f.mimeType.startsWith('image/') ? Icons.image : f.mimeType.startsWith('video/') ? Icons.video_file : Icons.insert_drive_file),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${f.isOutgoing ? 'أُرسل' : 'تم الاستلام'} • ${(f.size / 1024).toStringAsFixed(1)} KB • ${f.receivedAt.hour.toString().padLeft(2, '0')}:${f.receivedAt.minute.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.open_in_new), onTap: () => _openAttachment(f),
          ))),
        ]),
      )),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        IconButton(onPressed: _sending ? null : _attachments, icon: const Icon(Icons.add)),
        Expanded(child: TextField(controller: _controller, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: 'اكتب رسالة...', filled: true, fillColor: Theme.of(context).colorScheme.surface, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
        const SizedBox(width: 8), IconButton(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
      ]))),
    ]),
  );
}
