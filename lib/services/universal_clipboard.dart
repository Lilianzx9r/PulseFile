// lib/services/universal_clipboard.dart
//
// Presse-papiers unique pour copier/couper/coller un fichier ou dossier
// quelle que soit la source ET la destination (local, FTP, HTTP) — avec
// relais automatique (téléchargement puis envoi) quand elles sont
// différentes.
//
// Limite assumée : la copie/déplacement récursif d'un DOSSIER n'est géré
// que quand source et destination sont le même type de stockage (et, pour
// FTP/HTTP, la même connexion). Un dossier ne peut pas être copié/déplacé
// d'une connexion vers une autre, ni entre local et distant — seuls les
// fichiers individuels le peuvent (via téléchargement + envoi). Un dossier
// hors de ce cas est ignoré (compté à part dans le résultat), pas une
// erreur silencieuse.
//
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'ftp_service.dart';
import 'http_service.dart';

enum ClipKind { local, ftp, http }

class ClipItem {
  final ClipKind kind;
  final String name;
  final bool isDir;
  final String path; // chemin local, ou chemin distant
  final FtpConnection? ftpConn;
  final HttpConnection? httpConn;

  const ClipItem({
    required this.kind,
    required this.name,
    required this.isDir,
    required this.path,
    this.ftpConn,
    this.httpConn,
  });
}

class UniversalClipboard {
  static List<ClipItem> items = [];
  static bool isCut = false;

  static bool get isEmpty => items.isEmpty;

  static void set(List<ClipItem> newItems, {required bool cut}) {
    items = newItems;
    isCut = cut;
  }

  static void clear() {
    items = [];
    isCut = false;
  }
}

class PasteResult {
  final int ok;
  final int errors;
  final int skipped;
  const PasteResult(this.ok, this.errors, this.skipped);
}

/// Colle le contenu du presse-papiers dans la destination indiquée.
/// [onProgress] : fraction 0..1 (ou null si indéterminé) + libellé.
Future<PasteResult> pasteClipboardInto({
  required ClipKind destKind,
  required String destPath,
  FtpConnection? destFtpConn,
  HttpConnection? destHttpConn,
  required void Function(double? fraction, String label) onProgress,
}) async {
  final items = List<ClipItem>.from(UniversalClipboard.items);
  final cut = UniversalClipboard.isCut;
  var ok = 0, errors = 0, skipped = 0;
  final tmpDir = await getTemporaryDirectory();

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    onProgress(items.isEmpty ? null : i / items.length, '${item.name} (${i + 1}/${items.length})');

    if (item.isDir) {
      final sameLocal = item.kind == ClipKind.local && destKind == ClipKind.local;
      final sameFtp   = item.kind == ClipKind.ftp && destKind == ClipKind.ftp &&
          item.ftpConn?.id == destFtpConn?.id;
      final sameHttp  = item.kind == ClipKind.http && destKind == ClipKind.http &&
          item.httpConn?.id == destHttpConn?.id;

      if (sameLocal) {
        try {
          final destFull = p.join(destPath, item.name);
          await _copyDirGeneric(Directory(item.path), Directory(destFull));
          if (cut) await Directory(item.path).delete(recursive: true);
          ok++;
        } catch (_) { errors++; }
      } else if ((sameFtp || sameHttp) && cut) {
        // Un dossier distant ne peut être que déplacé (renommé), pas copié
        // récursivement — c'est la seule opération que FTP/HTTP permettent.
        try {
          if (sameFtp) {
            final remoteDest = '$destPath/${item.name}'.replaceAll('//', '/');
            await FtpService.move(destFtpConn!, item.path, remoteDest);
          } else {
            final remoteDest = (destPath == '.' ? item.name : '$destPath/${item.name}')
                .replaceAll('//', '/');
            await HttpService.move(destHttpConn!, item.path, remoteDest);
          }
          ok++;
        } catch (_) { errors++; }
      } else {
        skipped++;
      }
      continue;
    }

    // Fichier : téléchargement (si distant) puis dépôt dans la destination.
    try {
      String sourceLocalPath;
      if (item.kind == ClipKind.local) {
        sourceLocalPath = item.path;
      } else {
        final tmp = p.join(tmpDir.path, 'pulsefile_clip', item.name);
        await Directory(p.dirname(tmp)).create(recursive: true);
        if (item.kind == ClipKind.ftp) {
          await FtpService.download(item.ftpConn!, item.path, localPath: tmp);
        } else {
          await HttpService.download(item.httpConn!, item.path, localPath: tmp);
        }
        sourceLocalPath = tmp;
      }

      if (destKind == ClipKind.local) {
        await File(sourceLocalPath).copy(p.join(destPath, item.name));
      } else if (destKind == ClipKind.ftp) {
        final remoteDest = '$destPath/${item.name}'.replaceAll('//', '/');
        await FtpService.upload(destFtpConn!, sourceLocalPath, remoteDest);
      } else {
        final remoteDest = (destPath == '.' ? item.name : '$destPath/${item.name}')
            .replaceAll('//', '/');
        await HttpService.upload(destHttpConn!, sourceLocalPath, remoteDest);
      }

      if (cut) {
        if (item.kind == ClipKind.local) {
          await File(item.path).delete();
        } else if (item.kind == ClipKind.ftp) {
          await FtpService.delete(item.ftpConn!, item.path, isDir: false);
        } else if (item.kind == ClipKind.http) {
          await HttpService.delete(item.httpConn!, item.path);
        }
      }
      ok++;
    } catch (_) {
      errors++;
    }
  }

  if (cut) UniversalClipboard.clear();
  return PasteResult(ok, errors, skipped);
}

Future<void> _copyDirGeneric(Directory src, Directory dest) async {
  await dest.create(recursive: true);
  for (final e in src.listSync()) {
    if (e is Directory) {
      await _copyDirGeneric(e, Directory(p.join(dest.path, p.basename(e.path))));
    } else {
      await File(e.path).copy(p.join(dest.path, p.basename(e.path)));
    }
  }
}
