// lib/theme/pf_colors.dart
import 'package:flutter/material.dart';

class PfColors {
  static const accent  = Color(0xFF3D7CF4);
  static const red     = Color(0xFFE24B4A);
  static const green   = Color(0xFF0F6E56);
  static const subtext = Color(0xFF888780);
  static Color bg(bool dark)      => dark ? const Color(0xFF111110) : const Color(0xFFF6F5F0);
  static Color card(bool dark)    => dark ? const Color(0xFF1C1C1A) : Colors.white;
  static Color border(bool dark)  => dark ? const Color(0xFF2C2C2A) : const Color(0xFFE8E6DC);
  static Color text(bool dark)    => dark ? Colors.white : const Color(0xFF1A1A18);
}
