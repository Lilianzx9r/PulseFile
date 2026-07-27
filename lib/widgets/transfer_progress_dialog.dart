// lib/widgets/transfer_progress_dialog.dart
//
// Boîte de dialogue de progression pour les transferts (téléchargement,
// envoi, extraction) — affiche une barre + le pourcentage, mise à jour via
// un contrôleur découplé de la reconstruction du dialogue (ValueNotifier).
//
import 'package:flutter/material.dart';

class TransferProgressController {
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null); // null = indéterminé
  final ValueNotifier<String> label = ValueNotifier<String>('');
  bool _closed = false;
  bool _disposed = false;

  void update(double? percent, {String? label}) {
    if (_closed || _disposed) return;
    progress.value = percent == null ? null : percent.clamp(0, 1);
    if (label != null) this.label.value = label;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closed = true;
    progress.dispose();
    label.dispose();
  }
}

/// Affiche le dialogue et retourne son contrôleur. Appeler
/// [closeTransferProgressDialog] une fois le transfert terminé (succès ou
/// erreur) — sinon le dialogue reste bloqué à l'écran.
TransferProgressController showTransferProgressDialog(
    BuildContext context, {required String title}) {
  final controller = TransferProgressController();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ValueListenableBuilder<double?>(
            valueListenable: controller.progress,
            builder: (_, value, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: value, minHeight: 6),
              ),
              const SizedBox(height: 6),
              Text(value == null ? '…' : '${(value * 100).toStringAsFixed(0)} %',
                  style: const TextStyle(fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<String>(
            valueListenable: controller.label,
            builder: (_, value, __) => Text(value,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    ),
  );
  return controller;
}

Future<void> await closeTransferProgressDialog(
    BuildContext context, TransferProgressController controller) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
    // Let the dialog route unmount before disposing the ValueNotifiers that
    // its ValueListenableBuilders are listening to.
    await Future<void>.delayed(Duration.zero);
  }
  controller.dispose();
}

/// Convertit un couple (transféré, total) en pourcentage 0..1, ou null si la
/// taille totale est inconnue (barre indéterminée).
double? progressFraction(int transferred, int total) =>
    total <= 0 ? null : transferred / total;
