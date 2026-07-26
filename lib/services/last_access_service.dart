// lib/services/last_access_service.dart
//
// Mémorise la dernière connexion (FTP ou HTTP) ouverte par l'utilisateur,
// pour la rouvrir automatiquement au lancement de l'application.
//
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum LastAccessType { ftp, http }

class LastAccessService {
  static const _storage = FlutterSecureStorage();
  static const _kType = 'last_access_type';
  static const _kId   = 'last_access_id';

  /// Enregistre la connexion comme étant la dernière utilisée.
  static Future<void> save(LastAccessType type, int id) async {
    await _storage.write(key: _kType, value: type.name);
    await _storage.write(key: _kId, value: id.toString());
  }

  /// Récupère la dernière connexion enregistrée, si elle existe.
  static Future<(LastAccessType, int)?> load() async {
    final t = await _storage.read(key: _kType);
    final i = await _storage.read(key: _kId);
    if (t == null || i == null) return null;
    final id = int.tryParse(i);
    if (id == null) return null;
    final LastAccessType? type = switch (t) {
      'ftp'  => LastAccessType.ftp,
      'http' => LastAccessType.http,
      _      => null,
    };
    if (type == null) return null;
    return (type, id);
  }

  /// Efface la mémorisation (par ex. si la connexion a été supprimée).
  static Future<void> clear() async {
    await _storage.delete(key: _kType);
    await _storage.delete(key: _kId);
  }
}
