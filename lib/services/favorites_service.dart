// lib/services/favorites_service.dart
//
// Mémorise des raccourcis vers des dossiers fréquents — locaux, ou distants
// (rattachés à une connexion FTP/HTTP précise).
//
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum FavoriteKind { local, ftp, http }

class FavoriteEntry {
  final FavoriteKind kind;
  final int? connectionId; // null pour "local"
  final String path;
  final String label;

  const FavoriteEntry({
    required this.kind,
    required this.path,
    required this.label,
    this.connectionId,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'connectionId': connectionId,
        'path': path,
        'label': label,
      };

  factory FavoriteEntry.fromJson(Map<String, dynamic> j) => FavoriteEntry(
        kind: FavoriteKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => FavoriteKind.local),
        connectionId: j['connectionId'] as int?,
        path: j['path'] as String,
        label: j['label'] as String,
      );
}

class FavoritesService {
  static const _storage = FlutterSecureStorage();
  static const _kKey = 'favorites_v1';

  static Future<List<FavoriteEntry>> list() async {
    final raw = await _storage.read(key: _kKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => FavoriteEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<FavoriteEntry> items) async {
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await _storage.write(key: _kKey, value: raw);
  }

  static bool _matches(FavoriteEntry a, FavoriteKind kind, int? connId, String path) =>
      a.kind == kind && a.connectionId == connId && a.path == path;

  static Future<bool> isFavorite(FavoriteKind kind, int? connectionId, String path) async {
    final items = await list();
    return items.any((e) => _matches(e, kind, connectionId, path));
  }

  static Future<void> add(FavoriteEntry entry) async {
    final items = await list();
    if (items.any((e) => _matches(e, entry.kind, entry.connectionId, entry.path))) return;
    items.add(entry);
    await _save(items);
  }

  static Future<void> remove(FavoriteKind kind, int? connectionId, String path) async {
    final items = await list();
    items.removeWhere((e) => _matches(e, kind, connectionId, path));
    await _save(items);
  }

  static Future<void> toggle(FavoriteEntry entry) async {
    final fav = await isFavorite(entry.kind, entry.connectionId, entry.path);
    if (fav) {
      await remove(entry.kind, entry.connectionId, entry.path);
    } else {
      await add(entry);
    }
  }
}
