// lib/services/pending_save_service.dart
//
// Gère la demande "Enregistrer sous" reçue d'une app tierce (ex. PulseIt)
// via ACTION_SAVE_TO — voir MainActivity.kt. Distinct du flux "pick-folder/
// pick-file" (android_picker.dart) : ici on reçoit un FICHIER LOCAL déjà
// présent sur l'appareil, et on doit l'enregistrer dans la destination
// choisie (locale, FTP, ou HTTP), pas juste renvoyer un chemin.
//
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const _saveChannel = MethodChannel('com.pulsefile/share');

class PendingSaveRequest {
  final String localPath;
  final String fileName;
  const PendingSaveRequest({required this.localPath, required this.fileName});
}

/// Vérifie si une app tierce a demandé à PulseFile d'enregistrer un fichier.
/// Retourne null si aucune demande n'est en attente (démarrage normal).
Future<PendingSaveRequest?> checkPendingSave() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _saveChannel.invokeMethod('getPendingSave');
    if (result == null) return null;
    final map = Map<String, dynamic>.from(result as Map);
    final path = map['path'] as String?;
    if (path == null) return null;
    return PendingSaveRequest(localPath: path, fileName: map['name'] as String? ?? path);
  } catch (_) {
    return null;
  }
}

/// Vérifie si un ou plusieurs fichiers ont été partagés vers PulseFile
/// depuis une autre app Android (menu "Partager" système — ACTION_SEND /
/// ACTION_SEND_MULTIPLE). Retourne null si rien n'est en attente.
Future<List<PendingSaveRequest>?> checkPendingShare() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _saveChannel.invokeMethod('getPendingShare');
    if (result == null) return null;
    final paths = List<String>.from(result as List);
    if (paths.isEmpty) return null;
    return paths.map((path) =>
        PendingSaveRequest(localPath: path, fileName: p.basename(path))).toList();
  } catch (_) {
    return null;
  }
}

/// Signale à l'app appelante que l'enregistrement est terminé (succès ou
/// annulation) — ferme PulseFile et rend la main à cette app.
Future<void> returnSaveResult({required bool ok, String? savedPath}) async {
  if (!Platform.isAndroid) return;
  try {
    await _saveChannel.invokeMethod('returnSaveResult', {
      'ok': ok,
      'savedPath': savedPath,
    });
  } catch (_) {}
}
