// lib/widgets/local_file_picker.dart
//
// Sélecteur de fichiers local (stockage de l'appareil), dans le style
// PulseFile — remplace le sélecteur natif du système pour les imports
// (envoi de fichiers vers une connexion FTP/HTTP).
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../theme/pf_colors.dart';
import '../utils/quick_paths.dart';

class LocalFilePickerScreen extends StatefulWidget {
  final String? initialPath;
  final bool allowMultiple;
  const LocalFilePickerScreen({super.key, this.initialPath, this.allowMultiple = true});

  @override
  State<LocalFilePickerScreen> createState() => _LocalFilePickerScreenState();
}

class _LocalFilePickerScreenState extends State<LocalFilePickerScreen> {
  Directory? _dir;
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};
  List<QuickPath> _quickPaths = [];

  @override
  void initState() {
    super.initState();
    _init();
    resolveAllShortcuts().then((q) { if (mounted) setState(() => _quickPaths = q); });
  }

  Future<void> _init() async {
    Directory? start;
    if (widget.initialPath != null) {
      start = Directory(widget.initialPath!);
    } else if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          Directory root = ext;
          for (var i = 0; i < 6; i++) {
            if (root.path.endsWith('/0') || !root.path.contains('/Android/')) break;
            final parent = root.parent;
            if (parent.path == root.path) break;
            root = parent;
          }
          start = root;
        }
      } catch (_) {}
    } else {
      try { start = await getDownloadsDirectory(); } catch (_) {}
    }
    start ??= Directory.current;
    await _load(start);
  }

  Future<void> _load(Directory dir) async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = <FileSystemEntity>[];
      await for (final e in dir.list(followLinks: false)) {
        entries.add(e);
      }
      entries.sort((a, b) {
        final aDir = a is Directory, bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      if (mounted) setState(() { _dir = dir; _entries = entries; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _dir = dir; _entries = []; _error = 'Accès refusé à ce dossier'; _loading = false; });
    }
  }

  bool get _canGoUp => _dir != null && _dir!.parent.path != _dir!.path;

  IconData _quickIcon(IconDataLike icon) => switch (icon) {
        IconDataLike.desktop   => Icons.desktop_windows_outlined,
        IconDataLike.download  => Icons.download_outlined,
        IconDataLike.documents => Icons.description_outlined,
        IconDataLike.home      => Icons.home_outlined,
        IconDataLike.volume    => Icons.storage_outlined,
      };

  void _toggle(File f) {
    setState(() {
      if (!widget.allowMultiple) {
        Navigator.pop(context, [f.path]);
        return;
      }
      if (_selected.contains(f.path)) _selected.remove(f.path);
      else _selected.add(f.path);
    });
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
        leading: _canGoUp
            ? IconButton(icon: const Icon(Icons.arrow_upward),
                onPressed: () => _load(_dir!.parent))
            : IconButton(icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_selected.isEmpty ? 'Choisir un fichier' : '${_selected.length} sélectionné(s)',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text(_dir?.path ?? '', style: TextStyle(fontSize: 10, color: subCol),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: Column(children: [
        if (_quickPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickPaths.length,
                separatorBuilder: (_, __) => const Gap(8),
                itemBuilder: (c, i) {
                  final q = _quickPaths[i];
                  return ActionChip(
                    avatar: Icon(_quickIcon(q.icon), size: 16, color: accent),
                    label: Text(q.label, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _load(Directory(q.path)),
                  );
                },
              ),
            ),
          ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: TextStyle(color: subCol), textAlign: TextAlign.center)))
              : _entries.isEmpty
                ? Center(child: Text('Dossier vide', style: TextStyle(color: subCol)))
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: border),
                    itemBuilder: (c, i) {
                      final e = _entries[i];
                      final isDir = e is Directory;
                      final isSel = _selected.contains(e.path);
                      return Material(color: isSel ? accent.withOpacity(0.10) : cardBg, child: InkWell(
                        onTap: () => isDir ? _load(e as Directory) : _toggle(e as File),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(children: [
                            if (!isDir && widget.allowMultiple)
                              Icon(isSel ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 20, color: isSel ? accent : subCol),
                            if (!isDir && widget.allowMultiple) const Gap(8),
                            Icon(isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                                size: 20, color: isDir ? accent : subCol),
                            const Gap(8),
                            Expanded(child: Text(p.basename(e.path), maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textCol))),
                            if (isDir) Icon(Icons.chevron_right, size: 18, color: subCol),
                          ]),
                        ),
                      ));
                    },
                  ),
        ),
        if (widget.allowMultiple)
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              )),
              const Gap(12),
              Expanded(flex: 2, child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected.toList()),
                child: Text(_selected.isEmpty
                    ? 'Sélectionner des fichiers'
                    : 'Choisir (${_selected.length})'),
              )),
            ]),
          )),
      ]),
    );
  }
}
