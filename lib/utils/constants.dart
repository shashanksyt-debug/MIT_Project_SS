// lib/utils/constants.dart

import 'package:flutter/material.dart';

class AppConstants {
  AppConstants._();

  // ── Warning threshold ─────────────────────────────────────────
  /// Default distance (cm) below which a proximity warning is shown.
  /// Users can adjust this at runtime via the settings bottom sheet.
  static const double defaultWarningThresholdCm = 50.0;

  // ── UI colours ────────────────────────────────────────────────
  static const Color colorBackground = Color(0xFF0D1117);
  static const Color colorSurface = Color(0xFF161B22);
  static const Color colorCard = Color(0xFF21262D);
  static const Color colorAccent = Color(0xFF58A6FF);
  static const Color colorSafe = Color(0xFF3FB950);
  static const Color colorWarning = Color(0xFFD29922);
  static const Color colorDanger = Color(0xFFF85149);
  static const Color colorTextPrimary = Color(0xFFE6EDF3);
  static const Color colorTextSecond = Color(0xFF8B949E);
  static const Color colorBorder = Color(0xFF30363D);

  // ── Typography ────────────────────────────────────────────────
  static const String fontMono = 'monospace';
}
