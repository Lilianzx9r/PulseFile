// lib/screens/home_screen.dart
//
// Écran principal de PulseFile : 3 onglets
//   - Local  : explorateur de fichiers système (Android + Windows)
//   - FTP    : gestionnaire de connexions FTP + explorateur
//   - HTTP   : gestionnaire de connexions PHP/HTTP + explorateur
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/pf_colors.dart';
import 'file_manager_screen.dart';

// Canal pour recevoir des fichiers partagés depuis d'autres apps
const _kShareChannel = MethodChannel('com.pulsefile/share');

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // FileManagerScreen contient déjà ses propres onglets :
    // Stockages / Récents / FTP / HTTP (adaptés à la plateforme).
    return const FileManagerScreen();
  }
}
