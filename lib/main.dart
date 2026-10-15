import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString('profileName')?.trim() ?? '';
  runApp(BlousabApp(showLogin: name.isEmpty));
}

class BlousabApp extends StatefulWidget {
  final bool showLogin;
  const BlousabApp({super.key, required this.showLogin});
  static final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);
  static final seedNotifier = ValueNotifier<Color>(const Color(0xFF075E54));

  @override
  State<BlousabApp> createState() => _BlousabAppState();
}

class _BlousabAppState extends State<BlousabApp> {
  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    final p = await SharedPreferences.getInstance();
    BlousabApp.themeNotifier.value = p.getBool('darkMode') == true ? ThemeMode.dark : ThemeMode.light;
    final colorValue = p.getInt('themeColor');
    if (colorValue != null) BlousabApp.seedNotifier.value = Color(colorValue);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: BlousabApp.themeNotifier,
    builder: (_, mode, __) => ValueListenableBuilder<Color>(
      valueListenable: BlousabApp.seedNotifier,
      builder: (_, seed, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'بلوساب',
        themeMode: mode,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed), scaffoldBackgroundColor: const Color(0xFFF7F5F0)),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
        home: widget.showLogin ? const LoginScreen() : const HomeScreen(),
      ),
    ),
  );
}