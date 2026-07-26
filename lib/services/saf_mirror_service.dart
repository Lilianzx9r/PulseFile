// lib/services/saf_mirror_service.dart
//
// Envoie une copie des connexions HTTP (et, via ftp_service.dart, des mots
// de passe FTP) au code natif Android, qui les chiffre avec une clé Android
// Keystore liée à l'état "appareil déverrouillé" (voir SecureMirror.kt côté
// Kotlin) avant de les écrire sur disque. Lu ensuite par
// PulseFileDocumentsProvider.kt pour l'intégration Storage Access Framework
// ("Ouvrir avec"/"Enregistrer sous" d'autres apps).
//
// Pourquoi ne pas juste réutiliser flutter_secure_storage direct depuis
// Kotlin : la librairie chiffre les valeurs avec un format interne propre
// (non documenté et sujet à changement entre versions), impossible à
// reproduire fiablement côté natif. On passe donc par un miroir dédié,
// chiffré avec une clé qu'on maîtrise et dont le contrat (liée au
// déverrouillage de l'appareil) est explicite et stable.
//
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class SafMirrorService {
  static const _ch = MethodChannel('com.pulsefile/files');

  static Future<void> _write(String filename, Object data) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('writeSecureMirror', {
        'filename': filename,
        'content': jsonEncode(data),
      });
    } catch (_) {
      // Best-effort — voir commentaire ci-dessus.
    }
  }

  /// Régénère le miroir des connexions HTTP (voir doc en tête de fichier).
  static Future<void> syncHttp(List<Map<String, dynamic>> connections) =>
      _write('pulsefile_http_mirror.json', connections);

  /// Régénère le miroir des mots de passe FTP — même raison : le mot de
  /// passe FTP est stocké via flutter_secure_storage (chiffré), donc le
  /// code natif Kotlin ne peut pas le relire directement sans reproduire
  /// (et maintenir) le format de chiffrement interne de la librairie.
  static Future<void> syncFtpPasswords(Map<int, String> passwordsById) =>
      _write('pulsefile_ftp_mirror.json',
          passwordsById.map((id, pw) => MapEntry(id.toString(), pw)));
}
