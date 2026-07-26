// lib/widgets/local_folder_picker.dart
//
// Navigateur de dossiers local (stockage de l'appareil), dans le style
// PulseFile — utilisé pour choisir une destination de téléchargement.
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/recent_folders_service.dart';
import '../theme/pf_colors.dart';
import '../utils/quick_paths.dart';

class LocalFolderPickerScreen extends StatefulWidget {
  final String? initialPath;
  const LocalFolderPickerScreen({super.key, this.initialPath});

  @override
  State<LocalFolderPickerScreen> createState() => _LocalFolderPickerScreenState();
}

class _LocalFolderPickerScreenState extends State<LocalFolderPickerScreen> {
  Directory? _dir;
  List<Directory> _subdirs = [];
  bool _loading = true;
  String? _error;
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
          // Remonte de Android/data/<package>/files vers la racine du stockage
          // (ex: /storage/emulated/0) pour proposer un point de départ utile.
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
      final subs = <Directory>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is Directory) subs.add(e);
      }
      subs.sort((a, b) =>
          p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      if (mounted) setState(() { _dir = dir; _subdirs = subs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _dir = dir; _subdirs = []; _error = 'Accès refusé à ce dossier'; _loading = false; });
    }
  }

  Future<void> _newFolder() async {
    if (_dir == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouveau dossier'),
        content: TextField(controller: ctrl,
            decoration: const InputDecoration(labelText: 'Nom du dossier')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true || ctrl.text.isEmpty) return;
    try {
      final newDir = Directory(p.join(_dir!.path, ctrl.text));
      await newDir.create();
      _load(_dir!);
    } catch (_) {}
  }

  bool get _canGoUp => _dir != null && _dir!.parent.path != _dir!.path;

  IconData _quickIcon(IconDataLike icon) => switch (icon) {
        IconDataLike.desktop   => Icons.desktop_windows_outlined,
        IconDataLike.download  => Icons.download_outlined,
        IconDataLike.documents => Icons.description_outlined,
        IconDataLike.home      => Icons.home_outlined,
        IconDataLike.volume    => Icons.storage_outlined,
      };

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
          const Text('Choisir un dossier', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text(_dir?.path ?? '', style: TextStyle(fontSize: 10, color: subCol),
              overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Nouveau dossier', onPressed: _dir == null ? null : _newFolder),
        ],
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
              : _subdirs.isEmpty
                ? Center(child: Text('Aucun sous-dossier', style: TextStyle(color: subCol)))
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _subdirs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: border),
                    itemBuilder: (c, i) {
                      final d = _subdirs[i];
                      return Material(color: cardBg, child: InkWell(
                        onTap: () => _load(d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(children: [
                            Icon(Icons.folder_outlined, size: 20, color: accent),
                            const Gap(8),
                            Expanded(child: Text(p.basename(d.path), maxLines: 1, overflow: TextOverflow.ellipsis,
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
              onPressed: _dir == null ? null : () {
                RecentFoldersService.touch(RecentFolderKind.local, _dir!.path,
                    p.basename(_dir!.path).isEmpty ? _dir!.path : p.basename(_dir!.path));
                Navigator.pop(context, _dir!.path);
              },
              child: const Text('Choisir ce dossier'),
            )),
          ]),
        )),
      ]),
    );
  }
}
