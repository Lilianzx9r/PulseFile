// lib/widgets/remote_folder_picker.dart
//
// Navigateur de dossiers générique (in-app) pour choisir une destination
// au sein d'une connexion FTP ou HTTP — utilisé notamment par "Déplacer".
// L'appelant fournit simplement une fonction de listage (listFolder) et
// la logique de navigation (parentOf/canGoUp), propres à chaque protocole.
//
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../theme/pf_colors.dart';

class RemoteFolderEntry {
  final String name;
  final String path;
  const RemoteFolderEntry({required this.name, required this.path});
}

class RemoteFolderPickerScreen extends StatefulWidget {
  final String title;
  final String initialPath;
  final Future<List<RemoteFolderEntry>> Function(String path) listFolder;
  final String Function(String path) parentOf;
  final bool Function(String path) canGoUp;

  const RemoteFolderPickerScreen({
    super.key,
    required this.title,
    required this.initialPath,
    required this.listFolder,
    required this.parentOf,
    required this.canGoUp,
  });

  @override
  State<RemoteFolderPickerScreen> createState() => _RemoteFolderPickerScreenState();
}

class _RemoteFolderPickerScreenState extends State<RemoteFolderPickerScreen> {
  late String _path;
  List<RemoteFolderEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _load(_path);
  }

  Future<void> _load(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await widget.listFolder(path);
      entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() { _path = path; _entries = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _path = path; _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final accent  = PfColors.accent;
    final bg      = PfColors.bg(isDark);
    final cardBg  = PfColors.card(isDark);
    final border  = PfColors.border(isDark);
    final textCol = PfColors.text(isDark);
    final subCol  = PfColors.subtext;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        leading: widget.canGoUp(_path)
            ? IconButton(icon: const Icon(Icons.arrow_upward),
                onPressed: () => _load(widget.parentOf(_path)))
            : IconButton(icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text(_path, style: TextStyle(fontSize: 10, color: subCol),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: TextStyle(color: subCol), textAlign: TextAlign.center)))
              : _entries.isEmpty
                ? Center(child: Text('Aucun sous-dossier', style: TextStyle(color: subCol)))
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: border),
                    itemBuilder: (c, i) {
                      final e = _entries[i];
                      return Material(color: cardBg, child: InkWell(
                        onTap: () => _load(e.path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(children: [
                            Icon(Icons.folder_outlined, size: 20, color: accent),
                            const Gap(8),
                            Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textCol))),
                            Icon(Icons.chevron_right, size: 18, color: subCol),
                          ]),
                        ),
                      ));
                    },
                  ),
        ),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            )),
            const Gap(12),
            Expanded(flex: 2, child: FilledButton(
              onPressed: () => Navigator.pop(context, _path),
              child: Text('Choisir « $_path »', overflow: TextOverflow.ellipsis, maxLines: 1),
            )),
          ]),
        )),
      ]),
    );
  }
}
