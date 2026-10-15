import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  String _name = 'مستخدم';
  String? _profileImagePath;
  String? _wallpaperPath;
  bool _dark = false;
  int _color = 0xFF075E54;
  final _nameController = TextEditingController();
  final List<Color> _colors = const [Color(0xFF075E54), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFAD1457), Color(0xFFEF6C00), Color(0xFF37474F)];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final p = await SharedPreferences.getInstance(); if (!mounted) return; setState(() { _name = p.getString('profileName') ?? 'مستخدم'; _nameController.text = _name; _dark = p.getBool('darkMode') ?? false; _color = p.getInt('themeColor') ?? 0xFF075E54; _profileImagePath = p.getString('profileImagePath'); _wallpaperPath = p.getString('chatWallpaperPath'); }); }
  Future<void> _saveName() async { final n = _nameController.text.trim(); if (n.isEmpty) return; final p = await SharedPreferences.getInstance(); await p.setString('profileName', n); if (mounted) setState(() => _name = n); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الاسم'))); }
  Future<void> _setDark(bool value) async { final p = await SharedPreferences.getInstance(); await p.setBool('darkMode', value); BlousabApp.themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light; if (mounted) setState(() => _dark = value); }
  Future<void> _setColor(Color color) async { final p = await SharedPreferences.getInstance(); await p.setInt('themeColor', color.value); BlousabApp.seedNotifier.value = color; if (mounted) setState(() => _color = color.value); }

  Future<String> _copyImageToApp(String sourcePath, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.jpg';
    final target = File('${dir.path}/$prefix-${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(sourcePath).copy(target.path);
    return target.path;
  }
  Future<void> _chooseProfileImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image == null) return;
      final path = await _copyImageToApp(image.path, 'profile');
      final p = await SharedPreferences.getInstance(); await p.setString('profileImagePath', path);
      if (mounted) setState(() => _profileImagePath = path);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الصورة: $e'))); }
  }
  Future<void> _chooseWallpaper() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (image == null) return;
      final path = await _copyImageToApp(image.path, 'wallpaper');
      final p = await SharedPreferences.getInstance(); await p.setString('chatWallpaperPath', path);
      if (mounted) { setState(() => _wallpaperPath = path); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ خلفية المحادثة'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الخلفية: $e'))); }
  }
  Future<void> _removeWallpaper() async {
    final p = await SharedPreferences.getInstance(); await p.remove('chatWallpaperPath');
    if (mounted) { setState(() => _wallpaperPath = null); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إزالة الخلفية'))); }
  }
  Future<void> _contactDeveloper() async { final uri = Uri.parse('https://wsend.co/967737414884'); if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح رابط واتساب'))); } }
  @override
  void dispose() { _nameController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: ListView(padding: const EdgeInsets.all(16), children: [
    ListTile(leading: CircleAvatar(radius: 28, backgroundImage: _profileImagePath != null && File(_profileImagePath!).existsSync() ? FileImage(File(_profileImagePath!)) : null, child: _profileImagePath == null || !File(_profileImagePath!).existsSync() ? const Icon(Icons.person) : null), title: const Text('الملف الشخصي'), subtitle: const Text('اسمك وصورتك على هذا الجهاز'), trailing: IconButton(tooltip: 'تغيير الصورة', onPressed: _chooseProfileImage, icon: const Icon(Icons.add_a_photo))),
    TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()), textInputAction: TextInputAction.done, onSubmitted: (_) => _saveName()),
    const SizedBox(height: 8), Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton(onPressed: _saveName, child: const Text('حفظ الاسم'))),
    const Divider(height: 32), SwitchListTile(value: _dark, onChanged: _setDark, secondary: const Icon(Icons.dark_mode), title: const Text('الوضع الداكن')),
    const ListTile(leading: Icon(Icons.palette), title: Text('لون التطبيق')),
    Wrap(spacing: 12, children: _colors.map((c) => InkWell(onTap: () => _setColor(c), child: CircleAvatar(backgroundColor: c, child: _color == c.value ? const Icon(Icons.check, color: Colors.white) : null))).toList()),
    const SizedBox(height: 16), ListTile(leading: const Icon(Icons.wallpaper), title: const Text('خلفية المحادثة'), subtitle: Text(_wallpaperPath == null ? 'اختر صورة لتظهر خلف رسائل المحادثة' : 'تم اختيار خلفية'), trailing: Wrap(children: [IconButton(tooltip: 'اختيار خلفية', onPressed: _chooseWallpaper, icon: const Icon(Icons.image)), if (_wallpaperPath != null) IconButton(tooltip: 'إزالة الخلفية', onPressed: _removeWallpaper, icon: const Icon(Icons.delete_outline))]), onTap: _chooseWallpaper),
    const Divider(height: 32), ListTile(leading: const Icon(Icons.chat, color: Color(0xFF25D366)), title: const Text('التواصل مع المطوّر'), subtitle: const Text('فتح واتساب'), trailing: const Icon(Icons.open_in_new), onTap: _contactDeveloper),
    const SizedBox(height: 20), Center(child: Text('بلوساب • إصدار 1.0.0', style: Theme.of(context).textTheme.bodySmall)),
  ]));
}
