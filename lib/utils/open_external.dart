// lib/utils/open_external.dart
//
// Ouvre un fichier (ou un dossier) avec l'application par défaut du système
// — équivalent d'un double-clic dans l'explorateur natif. Utilisé par les
// explorateurs FTP/HTTP après téléchargement, pour permettre une vraie
// "ouverture" plutôt qu'un simple enregistrement sur disque.
//
import 'dart:io';
import 'package:flutter/services.dart';

const _fileChannel = MethodChannel('com.pulsefile/files');

/// Ouvre [path] (fichier local déjà présent sur le disque) avec l'app par
/// défaut associée à son type. Ne lève pas d'exception en cas d'échec —
/// l'appelant doit informer l'utilisateur lui-même si besoin.
Future<bool> openFileExternally(String path) async {
  try {
    if (Platform.isAndroid) {
      await _fileChannel.invokeMethod('openFile', {'path': path});
      return true;
    } else if (Platform.isWindows) {
      // 'start' traite le premier argument entre guillemets comme un titre
      // de fenêtre — d'où le "" vide avant le chemin réel.
      final res = await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
      return res.exitCode == 0;
    } else if (Platform.isMacOS) {
      final res = await Process.run('open', [path]);
      return res.exitCode == 0;
    } else if (Platform.isLinux) {
      final res = await Process.run('xdg-open', [path]);
      return res.exitCode == 0;
    }
  } catch (_) {}
  return false;
}

/// Ouvre le dossier [path] dans l'explorateur natif du système (Windows/
/// macOS/Linux). Pas d'équivalent direct sous Android (pas de gestionnaire
/// de fichiers universel à cibler) — no-op silencieux dans ce cas.
Future<bool> openFolderExternally(String path) async {
  try {
    if (Platform.isWindows) {
      final res = await Process.run('explorer', [path], runInShell: true);
      // explorer.exe renvoie parfois un code non nul même en cas de succès —
      // on considère l'appel réussi s'il ne lève pas d'exception.
      return res.pid > 0;
    } else if (Platform.isMacOS) {
      final res = await Process.run('open', [path]);
      return res.exitCode == 0;
    } else if (Platform.isLinux) {
      final res = await Process.run('xdg-open', [path]);
      return res.exitCode == 0;
    }
  } catch (_) {}
  return false;
}
