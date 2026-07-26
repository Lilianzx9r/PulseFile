// lib/services/recent_folders_service.dart
//
// Mémorise les 20 derniers dossiers utilisés, tous modes confondus (local,
// FTP, HTTP) et tous usages confondus (navigation, import/upload,
// export/download, édition...). Accessible par swipe vertical sur l'AppBar
// (voir swipe_recents_appbar.dart).
//
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum RecentFolderKind { local, ftp, http }

class RecentFolder {
  final RecentFolderKind kind;
  final String path;
  final String label;
  final int? connectionId; // null pour local
  final DateTime accessedAt;

  const RecentFolder({
    required this.kind,
    required this.path,
    required this.label,
    required this.accessedAt,
    this.connectionId,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'path': path,
        'label': label,
        'connectionId': connectionId,
        'accessedAt': accessedAt.toIso8601String(),
      };

  factory RecentFolder.fromJson(Map<String, dynamic> j) => RecentFolder(
        kind: RecentFolderKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => RecentFolderKind.local),
        path: j['path'] as String,
        label: j['label'] as String,
        connectionId: j['connectionId'] as int?,
        accessedAt: DateTime.tryParse(j['accessedAt'] as String? ?? '') ?? DateTime.now(),
      );

  bool sameLocation(RecentFolderKind k, String p, int? connId) =>
      kind == k && path == p && connectionId == connId;
}

class RecentFoldersService {
  static const _storage = FlutterSecureStorage();
  static const _kKey = 'recent_folders_v1';
  static const _maxEntries = 20;

  static Future<List<RecentFolder>> list() async {
    final raw = await _storage.read(key: _kKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      final items = decoded
          .map((e) => RecentFolder.fromJson(e as Map<String, dynamic>))
          .toList();
      items.sort((a, b) => b.accessedAt.compareTo(a.accessedAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Enregistre (ou remonte en tête) un dossier utilisé — à appeler à chaque
  /// navigation, sélection de destination/source, ou édition dans ce dossier.
  static Future<void> touch(RecentFolderKind kind, String path, String label,
      {int? connectionId}) async {
    final items = await list();
    items.removeWhere((e) => e.sameLocation(kind, path, connectionId));
    items.insert(0, RecentFolder(
        kind: kind, path: path, label: label,
        connectionId: connectionId, accessedAt: DateTime.now()));
    final trimmed = items.take(_maxEntries).toList();
    await _storage.write(key: _kKey,
        value: jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() => _storage.delete(key: _kKey);
}
