import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Durum çubuğu ve navigasyon çubuğu renkleri
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF161D26),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const TekerApp());
}

class TekerApp extends StatelessWidget {
  const TekerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F141C),
        primaryColor: const Color(0xFF00E676),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00BCD4),
          surface: Color(0xFF161D26),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161D26),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      home: const HomeNavigationScreen(),
    );
  }
}
