import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pulse_core/pulse_core.dart';

import 'http_service.dart';

/// Adaptateur de transition entre le service HTTP historique de PulseFile
/// et le contrat commun PulseCore.
///
/// Cette première version privilégie la compatibilité :
/// - les opérations existantes sont déléguées à HttpService ;
/// - les téléchargements/écritures abstraits de PulseCore passent par des
///   fichiers temporaires lorsque le service historique est basé sur des
///   chemins locaux ;
/// - les opérations non encore exposées par le serveur HTTP actuel restent
///   explicitement non supportées.
class HttpShareAdapter implements PulseShare {
  final HttpConnection connection;

  HttpShareAdapter(this.connection);

  @override
  String get id => 'http:${connection.id ?? connection.url}';

  @override
  String get displayName => connection.name;

  @override
  PulseShareCapabilities get capabilities => const PulseShareCapabilities(
        native: {
          PulseShareCapability.list,
          PulseShareCapability.read,
          PulseShareCapability.write,
          PulseShareCapability.delete,
          PulseShareCapability.createDirectory,
          PulseShareCapability.rename,
          PulseShareCapability.move,
          PulseShareCapability.stat,
          PulseShareCapability.copy,
          PulseShareCapability.removeDirectory,
          PulseShareCapability.search,
          PulseShareCapability.checksum,
        },
        effective: {
          PulseShareCapability.list,
          PulseShareCapability.read,
          PulseShareCapability.write,
          PulseShareCapability.delete,
          PulseShareCapability.createDirectory,
          PulseShareCapability.rename,
          PulseShareCapability.move,
          PulseShareCapability.stat,
          PulseShareCapability.copy,
          PulseShareCapability.removeDirectory,
          PulseShareCapability.search,
          PulseShareCapability.checksum,
        },
      );

  @override
  Future<PulseEntry?> stat(String path) async {
    final entry = await HttpService.stat(connection, _normalizePath(path));
    return PulseEntry(
      name: entry.name,
      path: _normalizePath(entry.remotePath),
      type: entry.isDir ? PulseEntryType.directory : PulseEntryType.file,
      size: entry.size,
      modifiedAt: entry.modified,
    );
  }

  @override
  Future<List<PulseEntry>> list(String path) async {
    final entries = await HttpService.list(
      connection,
      subdir: _normalizePath(path),
    );
    return entries
        .map(
          (entry) => PulseEntry(
            name: entry.name,
            path: _normalizePath(entry.remotePath),
            type: entry.isDir
                ? PulseEntryType.directory
                : PulseEntryType.file,
            size: entry.size,
            modifiedAt: entry.modified,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Uint8List> read(String path) async {
    final localPath = await _temporaryPath(path);
    try {
      final downloaded = await HttpService.download(
        connection,
        _normalizePath(path),
        localPath: localPath,
      );
      return await File(downloaded).readAsBytes();
    } finally {
      await _deleteIfExists(localPath);
    }
  }

  @override
  Stream<List<int>> openRead(String path, {int? start, int? end}) async* {
    final localPath = await _temporaryPath(path);
    try {
      final downloaded = await HttpService.download(
        connection,
        _normalizePath(path),
        localPath: localPath,
      );
      yield* File(downloaded).openRead(start, end);
    } finally {
      await _deleteIfExists(localPath);
    }
  }

  @override
  Future<void> write(String path, Uint8List data) async {
    final localPath = await _temporaryPath(path);
    try {
      await File(localPath).writeAsBytes(data, flush: true);
      await HttpService.upload(
        connection,
        localPath,
        _normalizePath(path),
      );
    } finally {
      await _deleteIfExists(localPath);
    }
  }

  @override
  Future<void> writeStream(
    String path,
    Stream<List<int>> data, {
    int? length,
  }) async {
    final localPath = await _temporaryPath(path);
    try {
      final sink = File(localPath).openWrite();
      await data.pipe(sink);
      await HttpService.upload(
        connection,
        localPath,
        _normalizePath(path),
      );
    } finally {
      await _deleteIfExists(localPath);
    }
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    await HttpService.delete(connection, _normalizePath(path));
  }

  @override
  Future<void> createDirectory(String path) async {
    await HttpService.mkdir(connection, _normalizePath(path));
  }

  @override
  Future<void> removeDirectory(
    String path, {
    bool recursive = false,
  }) async {
    await HttpService.removeDirectory(
      connection,
      _normalizePath(path),
      recursive: recursive,
    );
  }

  @override
  Future<void> rename(String from, String to) async {
    final source = _normalizePath(from);
    final destination = _normalizePath(to);
    await HttpService.rename(
      connection,
      source,
      p.basename(destination),
    );
  }

  @override
  Future<void> move(String from, String to) async {
    await HttpService.move(
      connection,
      _normalizePath(from),
      _normalizePath(to),
    );
  }

  @override
  Future<void> copy(String from, String to) async {
    await HttpService.copy(
      connection,
      _normalizePath(from),
      _normalizePath(to),
    );
  }

  @override
  Future<List<PulseEntry>> search(String path, String query) async {
    final entries = await HttpService.search(
      connection,
      _normalizePath(path),
      query,
    );
    return entries.map((entry) => PulseEntry(
      name: entry.name,
      path: _normalizePath(entry.remotePath),
      type: entry.isDir ? PulseEntryType.directory : PulseEntryType.file,
      size: entry.size,
      modifiedAt: entry.modified,
    )).toList(growable: false);
  }

  @override
  Future<String> checksum(String path) async {
    return HttpService.checksum(connection, _normalizePath(path));
  }

  static String _normalizePath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty || normalized == '.') return '.';
    return normalized.replaceFirst(RegExp(r'^/+'), '');
  }

  static Future<String> _temporaryPath(String remotePath) async {
    final dir = await getTemporaryDirectory();
    final name = p.basename(_normalizePath(remotePath));
    return p.join(
      dir.path,
      'pulse_http_share_${DateTime.now().microsecondsSinceEpoch}_$name',
    );
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Le fichier temporaire ne doit jamais masquer l'erreur réseau.
    }
  }
}
