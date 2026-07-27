// lib/services/universal_clipboard.dart
//
// Presse-papiers unique pour copier/couper/coller des fichiers et dossiers
// entre toutes les connexions : Local, FTP et HTTP.
//
// Les transferts inter-connexions passent par un fichier temporaire local.
// Les dossiers sont transférés récursivement, quel que soit le type de
// stockage source et destination.

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
  final String path;
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

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    onProgress(items.isEmpty ? null : i / items.length,
        '${item.name} (${i + 1}/${items.length})');

    try {
      await _transferItem(
        item: item,
        destKind: destKind,
        destPath: _joinDest(destKind, destPath, item.name),
        destFtpConn: destFtpConn,
        destHttpConn: destHttpConn,
        cut: cut,
        onProgress: (fraction, label) => onProgress(fraction, label),
      );
      ok++;
    } catch (_) {
      errors++;
    }
  }

  // Ne pas vider le presse-papiers si un déplacement/collage a échoué.
  if (cut && errors == 0 && skipped == 0) {
    UniversalClipboard.clear();
  }

  return PasteResult(ok, errors, skipped);
}

String _joinDest(ClipKind kind, String dir, String name) {
  if (kind == ClipKind.local) return p.join(dir, name);
  if (dir == '.' || dir.isEmpty) return name;
  return '${dir.replaceAll(RegExp(r'/+$'), '')}/$name';
}

Future<void> _transferItem({
  required ClipItem item,
  required ClipKind destKind,
  required String destPath,
  required FtpConnection? destFtpConn,
  required HttpConnection? destHttpConn,
  required bool cut,
  required void Function(double? fraction, String label) onProgress,
}) async {
  if (item.isDir) {
    await _transferDirectory(
      item: item,
      destKind: destKind,
      destPath: destPath,
      destFtpConn: destFtpConn,
      destHttpConn: destHttpConn,
      onProgress: onProgress,
    );
    if (cut) await _deleteSource(item);
    return;
  }

  final tmpDir = await getTemporaryDirectory();
  final tmp = File(p.join(
    tmpDir.path,
    'pulsefile_clip',
    '${DateTime.now().microsecondsSinceEpoch}_${p.basename(item.name)}',
  ));
  await tmp.parent.create(recursive: true);

  try {
    final source = await _materializeFile(item, tmp, onProgress);
    await _writeFile(source, destKind, destPath, destFtpConn, destHttpConn,
        onProgress);
    if (cut) await _deleteSource(item);
  } finally {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
}

Future<void> _transferDirectory({
  required ClipItem item,
  required ClipKind destKind,
  required String destPath,
  required FtpConnection? destFtpConn,
  required HttpConnection? destHttpConn,
  required void Function(double? fraction, String label) onProgress,
}) async {
  if (destKind == ClipKind.local) {
    await Directory(destPath).create(recursive: true);
  } else if (destKind == ClipKind.ftp) {
    await FtpService.mkdir(destFtpConn!, destPath);
  } else {
    await HttpService.mkdir(destHttpConn!, destPath);
  }

  if (item.kind == ClipKind.local) {
    final root = Directory(item.path);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: item.path);
      final target = _joinDest(destKind, destPath, rel);
      if (entity is Directory) {
        if (destKind == ClipKind.local) {
          await Directory(target).create(recursive: true);
        } else if (destKind == ClipKind.ftp) {
          await FtpService.mkdir(destFtpConn!, target);
        } else {
          await HttpService.mkdir(destHttpConn!, target);
        }
      } else if (entity is File) {
        await _writeFile(entity, destKind, target, destFtpConn, destHttpConn,
            onProgress);
      }
    }
    return;
  }

  if (item.kind == ClipKind.ftp) {
    final entries = await FtpService.list(item.ftpConn!, item.path);
    for (final entry in entries) {
      final target = _joinDest(destKind, destPath, entry.name);
      final child = ClipItem(
        kind: ClipKind.ftp,
        name: entry.name,
        isDir: entry.isDir,
        path: entry.path,
        ftpConn: item.ftpConn,
      );
      await _transferItem(
        item: child,
        destKind: destKind,
        destPath: target,
        destFtpConn: destFtpConn,
        destHttpConn: destHttpConn,
        cut: false,
        onProgress: onProgress,
      );
    }
    return;
  }

  final entries = await HttpService.list(item.httpConn!, subdir: item.path);
  for (final entry in entries) {
    final target = _joinDest(destKind, destPath, entry.name);
    final child = ClipItem(
      kind: ClipKind.http,
      name: entry.name,
      isDir: entry.isDir,
      path: entry.remotePath,
      httpConn: item.httpConn,
    );
    await _transferItem(
      item: child,
      destKind: destKind,
      destPath: target,
      destFtpConn: destFtpConn,
      destHttpConn: destHttpConn,
      cut: false,
      onProgress: onProgress,
    );
  }
}

Future<File> _materializeFile(
  ClipItem item,
  File tmp,
  void Function(double? fraction, String label) onProgress,
) async {
  if (item.kind == ClipKind.local) return File(item.path);

  if (item.kind == ClipKind.ftp) {
    await FtpService.download(item.ftpConn!, item.path,
        localPath: tmp.path,
        onProgress: (percent, received, total) {
          onProgress(total > 0 ? received / total : null, item.name);
        });
  } else {
    await HttpService.download(item.httpConn!, item.path,
        localPath: tmp.path,
        onProgress: (received, total) {
          onProgress(total > 0 ? received / total : null, item.name);
        });
  }
  return tmp;
}

Future<void> _writeFile(
  File source,
  ClipKind destKind,
  String destPath,
  FtpConnection? destFtpConn,
  HttpConnection? destHttpConn,
  void Function(double? fraction, String label) onProgress,
) async {
  if (destKind == ClipKind.local) {
    await source.copy(destPath);
  } else if (destKind == ClipKind.ftp) {
    await FtpService.upload(destFtpConn!, source.path, destPath,
        onProgress: (percent, sent, total) {
      onProgress(total > 0 ? sent / total : null, p.basename(destPath));
    });
  } else {
    await HttpService.upload(destHttpConn!, source.path, destPath,
        onProgress: (sent, total) {
      onProgress(total > 0 ? sent / total : null, p.basename(destPath));
    });
  }
}

Future<void> _deleteSource(ClipItem item) async {
  if (item.kind == ClipKind.local) {
    final entity = item.isDir ? Directory(item.path) : File(item.path);
    await entity.delete(recursive: item.isDir);
  } else if (item.kind == ClipKind.ftp) {
    await FtpService.delete(item.ftpConn!, item.path, isDir: item.isDir);
  } else {
    if (item.isDir) {
      await HttpService.removeDirectory(item.httpConn!, item.path,
          recursive: true);
    } else {
      await HttpService.delete(item.httpConn!, item.path);
    }
  }
}
