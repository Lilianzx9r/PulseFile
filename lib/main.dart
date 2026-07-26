// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/home_screen.dart';
import 'services/settings_service.dart';
import 'services/ftp_service.dart';
import 'services/http_service.dart';
import 'android_picker.dart';
import 'services/pending_save_service.dart';
import 'screens/save_destination_screen.dart';
import 'cli.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Pilotage en ligne de commande (Windows cmd/PowerShell) : si le premier
  // argument correspond à une commande CLI reconnue, on exécute l'action
  // demandée puis on quitte (ou on affiche une fenêtre de sélection pour
  // pick-folder/pick-file, qui se ferme d'elle-même une fois le choix fait).
  if (Platform.isWindows && args.isNotEmpty) {
    final outcome = await runCli(args);
    if (outcome.guiAction != null) {
      runApp(CliPickerApp(outcome: outcome));
      return;
    }
    if (outcome.handled) exit(exitCode);
  }

  await SettingsService.load();
  if (Platform.isAndroid) {
    // Regénère les miroirs en clair (FTP/HTTP) utilisés par le sélecteur
    // système Android — utile notamment pour les connexions déjà créées
    // avant l'introduction de ce mécanisme. Best-effort, ne bloque pas
    // le démarrage en cas d'échec.
    unawaited(FtpService.refreshSafMirror());
    unawaited(HttpService.refreshSafMirror());

    // Une app tierce (ex. PulseIt) a-t-elle demandé à PulseFile d'enregistrer
    // un fichier quelque part (ACTION_SAVE_TO) ? Si oui, on affiche l'écran
    // de choix de destination au lieu de l'app normale.
    final saveRequest = await checkPendingSave();
    if (saveRequest != null) {
      runApp(SaveDestinationApp(requests: [saveRequest]));
      return;
    }

    // Un ou plusieurs fichiers ont-ils été partagés vers PulseFile depuis une
    // autre app Android (menu "Partager" système) ? Même écran de choix de
    // destination, pour un ou plusieurs fichiers à la fois.
    final shareRequests = await checkPendingShare();
    if (shareRequests != null) {
      runApp(SaveDestinationApp(requests: shareRequests));
      return;
    }

    // Une app tierce a-t-elle lancé PulseFile via ACTION_PICK_FOLDER/
    // ACTION_PICK_FILE pour lui demander de choisir un chemin ? Si oui, on
    // affiche directement le sélecteur concerné au lieu de l'app normale.
    final pickerRequest = await checkPendingPicker();
    if (pickerRequest != null) {
      runApp(AndroidPickerApp(request: pickerRequest));
      return;
    }
  }
  runApp(const PulseFileApp());
}

class PulseFileApp extends StatelessWidget {
  const PulseFileApp({super.key});

  ThemeData _buildTheme(Brightness brightness, String fontFamily) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D7CF4), brightness: brightness),
      useMaterial3: true,
    );
    if (fontFamily == 'Système') return base;
    try {
      return base.copyWith(textTheme: GoogleFonts.getTextTheme(fontFamily, base.textTheme));
    } catch (_) {
      // Police introuvable (ex: renommée côté Google) : on retombe sur la police système
      // plutôt que de faire planter l'application.
      return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.notifier,
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'PulseFile',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light, settings.fontFamily),
          darkTheme: _buildTheme(Brightness.dark, settings.fontFamily),
          themeMode: settings.flutterThemeMode,
          home: const HomeScreen(),
        );
      },
    );
  }
}
