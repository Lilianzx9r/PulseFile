// lib/widgets/text_editor_screen.dart
//
// Éditeur de texte simple partagé par les explorateurs FTP et HTTP —
// affiche le contenu, permet de le modifier, et renvoie le texte modifié via
// Navigator.pop() (c'est à l'appelant de faire l'upload). Avertit avant de
// quitter si des modifications n'ont pas été enregistrées.
//
import 'package:flutter/material.dart';
import '../theme/pf_colors.dart';

class TextEditorScreen extends StatefulWidget {
  final String filename;
  final String content;
  const TextEditorScreen({super.key, required this.filename, required this.content});

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late final TextEditingController _ctrl;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.content);
    _ctrl.addListener(() { if (!_dirty) setState(() => _dirty = true); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _ctrl.text);

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Quitter sans enregistrer ? Les modifications seront perdues.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('Quitter sans enregistrer', style: TextStyle(color: Color(0xFFE24B4A)))),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final accent  = PfColors.accent;
    final bg      = PfColors.bg(isDark);
    final textCol = PfColors.text(isDark);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(widget.filename,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          actions: [
            if (_dirty)
              TextButton.icon(
                onPressed: _save,
                icon: Icon(Icons.save_outlined, color: accent, size: 18),
                label: Text('Enregistrer', style: TextStyle(color: accent)),
              ),
          ],
        ),
        body: TextField(
          controller: _ctrl,
          maxLines: null, expands: true,
          style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: textCol),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.all(16),
            border: InputBorder.none,
          ),
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
        ),
      ),
    );
  }
}
