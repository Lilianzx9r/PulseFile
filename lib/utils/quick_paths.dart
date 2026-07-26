// lib/utils/quick_paths.dart
//
// Résout les chemins de raccourcis rapides (Bureau, Téléchargements,
// Documents) pour Windows/macOS/Linux, utilisés par les sélecteurs de
// fichiers/dossiers locaux dans le style PulseFile.
//
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class QuickPath {
  final String label;
  final String path;
  final IconDataLike icon;
  const QuickPath(this.label, this.path, this.icon);
}

/// Petit enum minimal pour éviter de dépendre de Flutter dans ce fichier utilitaire.
enum IconDataLike { desktop, download, documents, home, volume }

/// Enumère tous les disques/volumes disponibles (indépendamment du mode
/// local/FTP/HTTP qui utilise ce sélecteur) : lecteurs Windows, stockage
/// interne + carte SD sur Android, volumes montés sur macOS/Linux.
Future<List<QuickPath>> resolveVolumes() async {
  final result = <QuickPath>[];

  if (Platform.isWindows) {
    for (var code = 'A'.codeUnitAt(0); code <= 'Z'.codeUnitAt(0); code++) {
      final letter = String.fromCharCode(code);
      final path = '$letter:\\';
      try {
        if (Directory(path).existsSync()) {
          result.add(QuickPath('Disque ($letter:)', path, IconDataLike.volume));
        }
      } catch (_) {}
    }
  } else if (Platform.isAndroid) {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        Directory root = ext;
        for (var i = 0; i < 6; i++) {
          final parent = root.parent;
          if (parent.path == root.path) break;
          root = parent;
          if (root.path.endsWith('/0') || root.path == '/storage/emulated/0') break;
        }
        result.add(QuickPath('Stockage interne', root.path, IconDataLike.volume));
      }
    } catch (_) {}
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null) {
        for (final d in dirs) {
          Directory root = d;
          for (var i = 0; i < 5; i++) {
            final parent = root.parent;
            if (parent.path == root.path) break;
            final parentName = p.basename(parent.path);
            if (parentName == 'storage' || parent.path == '/storage') break;
            root = parent;
          }
          if (root.path != result.firstOrNullPath() &&
              !result.any((v) => v.path == root.path)) {
            result.add(QuickPath('Carte SD / Externe', root.path, IconDataLike.volume));
          }
        }
      }
    } catch (_) {}
  } else if (Platform.isMacOS) {
    result.add(const QuickPath('Macintosh HD', '/', IconDataLike.volume));
    try {
      final volDir = Directory('/Volumes');
      if (volDir.existsSync()) {
        for (final e in volDir.listSync()) {
          if (e is Directory) {
            result.add(QuickPath(p.basename(e.path), e.path, IconDataLike.volume));
          }
        }
      }
    } catch (_) {}
  } else if (Platform.isLinux) {
    result.add(const QuickPath('Système (/)', '/', IconDataLike.volume));
    try {
      final user = Platform.environment['USER'] ?? '';
      for (final base in ['/media/$user', '/mnt']) {
        final dir = Directory(base);
        if (dir.existsSync()) {
          for (final e in dir.listSync()) {
            if (e is Directory) {
              result.add(QuickPath(p.basename(e.path), e.path, IconDataLike.volume));
            }
          }
        }
      }
    } catch (_) {}
  }

  return result;
}

extension _FirstPath on List<QuickPath> {
  String firstOrNullPath() => isEmpty ? '' : first.path;
}

Future<List<QuickPath>> resolveQuickPaths() async {
  final result = <QuickPath>[];

  String? home;
  if (Platform.isWindows) {
    home = Platform.environment['USERPROFILE'];
  } else {
    home = Platform.environment['HOME'];
  }

  if (home != null) {
    final desktop = Directory(p.join(home, 'Desktop'));
    if (desktop.existsSync()) {
      result.add(QuickPath('Bureau', desktop.path, IconDataLike.desktop));
    }
  }

  try {
    final dl = await getDownloadsDirectory();
    if (dl != null && dl.existsSync()) {
      result.add(QuickPath('Téléchargements', dl.path, IconDataLike.download));
    }
  } catch (_) {}

  if (home != null) {
    final docs = Directory(p.join(home, 'Documents'));
    if (docs.existsSync()) {
      result.add(QuickPath('Documents', docs.path, IconDataLike.documents));
    }
    result.add(QuickPath('Dossier personnel', home, IconDataLike.home));
  }

  return result;
}

/// Combine volumes (disques) et raccourcis (Bureau/Téléchargements/...) en une
/// seule liste, volumes en premier — c'est celle-ci que les widgets appellent.
Future<List<QuickPath>> resolveAllShortcuts() async {
  final volumes = await resolveVolumes();
  final quick = await resolveQuickPaths();
  return [...volumes, ...quick];
}
