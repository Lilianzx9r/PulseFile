// lib/widgets/properties_dialog.dart
import 'package:flutter/material.dart';
import '../theme/pf_colors.dart';

/// Boîte de dialogue "Propriétés" générique — utilisée pour les fichiers et
/// dossiers locaux, FTP, et HTTP.
class PropertiesRow {
  final String label;
  final String value;
  const PropertiesRow(this.label, this.value);
}

Future<void> showPropertiesDialog(
  BuildContext context, {
  required String name,
  required bool isDir,
  required List<PropertiesRow> rows,
}) {
  final isDark  = Theme.of(context).brightness == Brightness.dark;
  final accent  = PfColors.accent;
  final textCol = PfColors.text(isDark);
  final subCol  = PfColors.subtext;

  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Row(children: [
        Icon(isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            color: accent, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1)),
      ]),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 100, child: Text(r.label,
                    style: TextStyle(fontSize: 12, color: subCol))),
                Expanded(child: Text(r.value,
                    style: TextStyle(fontSize: 12, color: textCol),
                    softWrap: true)),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
      ],
    ),
  );
}
