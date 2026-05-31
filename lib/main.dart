// lib/main.dart
//
// Entry point for the BT Distance Meter Flutter application.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/bluetooth_service.dart';
import 'services/tts_service.dart';
import 'utils/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode — gauge is designed for portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Use dark system UI overlays to match the dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppConstants.colorBackground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    // ChangeNotifierProvider makes BluetoothService available to the
    // entire widget tree without needing to pass it down manually.
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothService()),
        ChangeNotifierProvider(create: (_) => TtsService()),
      ],
      child: const BtDistanceMeterApp(),
    ),
  );
}

class BtDistanceMeterApp extends StatelessWidget {
  const BtDistanceMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT Distance Meter',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      colorScheme: ColorScheme.dark(
        background: AppConstants.colorBackground,
        surface: AppConstants.colorSurface,
        primary: AppConstants.colorAccent,
      ),
      scaffoldBackgroundColor: AppConstants.colorBackground,
      fontFamily: 'sans-serif',
      useMaterial3: true,
    );
  }
}
