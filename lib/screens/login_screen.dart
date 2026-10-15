import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  Future<void> _continue() async {
    final name = _name.text.trim();
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسمك أولًا'))); return; }
    setState(() => _busy = true);
    final p = await SharedPreferences.getInstance();
    await p.setString('profileName', name);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const CircleAvatar(radius: 48, child: Icon(Icons.bluetooth_connected, size: 48)),
    const SizedBox(height: 20), const Text('مرحبًا بك في بلوساب', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('محادثات قريبة عبر البلوتوث', textAlign: TextAlign.center), const SizedBox(height: 28),
    TextField(controller: _name, textInputAction: TextInputAction.done, onSubmitted: (_) => _continue(), decoration: const InputDecoration(labelText: 'اسمك', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
    const SizedBox(height: 18), SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _continue, child: Text(_busy ? 'يرجى الانتظار...' : 'متابعة'))),
    const SizedBox(height: 12), const Text('الملف الشخصي محلي على هذا الهاتف.', style: TextStyle(fontSize: 12)),
  ])))));
}
