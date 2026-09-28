import 'package:flutter/material.dart';

import 'core/store.dart';
import 'screens/login.dart';
import 'screens/dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClubApp());
}

const clubGreen = Color(0xff173f35);

class ClubApp extends StatefulWidget {
  const ClubApp({super.key});
  @override
  State<ClubApp> createState() => _ClubAppState();
}

class _ClubAppState extends State<ClubApp> {
  late final ClubStore store;
  @override
  void initState() {
    super.initState();
    store = ClubStore();
    store.init();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Zairza · Club attendance',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: clubGreen,
        primary: clubGreen,
        surface: const Color(0xfff6f7f3),
      ),
      scaffoldBackgroundColor: const Color(0xfff6f7f3),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff6f7f3),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) => store.booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : store.session == null
          ? LoginScreen(store: store)
          : Dashboard(store: store),
    ),
  );
}
