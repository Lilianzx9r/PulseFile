// lib/screens/file_manager_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import '../widgets/swipe_nav.dart';
import '../widgets/properties_dialog.dart';
import '../services/ftp_service.dart';
import '../services/http_service.dart';
import '../services/last_access_service.dart';
import '../services/favorites_service.dart';
import '../services/settings_service.dart';
import '../services/universal_clipboard.dart';
import 'ftp_screen.dart';
import 'http_screen.dart';
import 'http_explorer_screen.dart';
import 'settings_screen.dart';
import 'transfer_destination_screen.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../theme/pf_colors.dart';
import '../utils/file_type.dart';
import '../widgets/image_viewer_screen.dart';
import '../widgets/transfer_progress_dialog.dart';
import '../widgets/storage_switcher.dart';
import '../widgets/swipe_recents_appbar.dart';
import '../services/recent_folders_service.dart';

enum _SortField { name, date, size }

/// Ouvre [file] en tenant compte de son type : visualiseur intégré pour le
/// texte et les images, extraction sur place pour une archive .zip,
/// application système par défaut pour le reste (vidéo, audio, .apk à
/// installer, etc.). Utilisé par tous les écrans qui affichent des fichiers
/// locaux (onglets Récents et Stockages).
Future<void> smartOpenLocalFile(BuildContext context, File file, MethodChannel ch,
    {VoidCallback? onChanged}) async {
  final name = p.basename(file.path);
  switch (classifyFile(name)) {
    case FileKind.text:
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => _TextViewerScreen(file: file)));
    case FileKind.image:
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ImageViewerScreen(file: file)));
    case FileKind.archive:
      final destName = p.basenameWithoutExtension(file.path);
      final destDir = p.join(p.dirname(file.path), destName);
      try {
        await Directory(destDir).create(recursive: true);
        await extractFileToDisk(file.path, destDir);
        onChanged?.call();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Extrait dans $destName/')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur : $e')));
        }
      }
    case FileKind.apk:
    case FileKind.video:
    case FileKind.audio:
    case FileKind.other:
      await ch.invokeMethod('openFile', {'path': file.path})
          .catchError((_) => null);
  }
}

// ── Page d'accueil du gestionnaire ───────────────────────────


Future<List<Directory>> _localRoots() async {
  if (Platform.isWindows) {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root',
        ],
      );
      final paths = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && RegExp(r'^[A-Za-z]:\\?$').hasMatch(s))
          .map((s) => s.endsWith(r'\') ? s : '$s\\')
          .toSet();
      return [
        for (final path in paths)
          if (Directory(path).existsSync()) Directory(path),
      ];
    } catch (_) {
      return [Directory(r'C:\')];
    }
  }
  if (Platform.isMacOS || Platform.isLinux) return [Directory('/')];
  return [];
}

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});
  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen>
    with SingleTickerProviderStateMixin {
  static const _ch = MethodChannel('com.pulsefile/files');

  late final TabController _tab;
  List<_Volume> _volumes = [];
  bool _loading = true;
  String? _selectedVolumePath;

  bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    // Desktop : Disque local + FTP + HTTP
    // Android : Stockages + Récents + FTP + HTTP
    _tab = TabController(length: _isDesktop ? 3 : 4, vsync: this);
    _init();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _init() async {
    try { await _ch.invokeMethod('requestPermission'); } catch (_) {}
    setState(() { _loading = true; });

    final vols = <_Volume>[];

    // Desktop : chaque lecteur local est une racine distincte.
    if (_isDesktop) {
      try {
        final roots = await _localRoots();
        for (final root in roots) {
          if (root.existsSync()) {
            final label = Platform.isWindows
                ? root.path.replaceAll(Platform.pathSeparator, '')
                : root.path;
            vols.add(_Volume(
              name: label,
              path: root.path,
              icon: Icons.computer_outlined,
            ));
          }
        }
      } catch (_) {}
    } else {
      // Stockage interne principal
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          Directory root = ext;
          // Remonter jusqu'à /storage/emulated/0
          for (var i = 0; i < 6; i++) {
            final parent = root.parent;
            if (parent.path == root.path) break;
            root = parent;
            if (root.path.endsWith('/0') ||
                root.path.endsWith('/emulated/0') ||
                root.path == '/storage/emulated/0') break;
          }
          vols.add(_Volume(name: 'Stockage interne', path: root.path,
              icon: Icons.smartphone));
        }
      } catch (_) {}
    }

    // Stockages externes (SD cards etc.) via getExternalStorageDirectories
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null) {
        for (final d in dirs) {
          // Remonter au volume racine
          Directory root = d;
          for (var i = 0; i < 5; i++) {
            final parent = root.parent;
            if (parent.path == root.path) break;
            final parentName = p.basename(parent.path);
            if (parentName == 'storage' || parent.path == '/storage') break;
            root = parent;
          }
          final normalized = p.normalize(root.path);
          if (!vols.any((v) => p.normalize(v.path) == normalized)) {
            vols.add(_Volume(name: 'Carte SD / Externe', path: root.path,
                icon: Icons.sd_card));
          }
        }
      }
    } catch (_) {}

    // Dossiers rapides dans le stockage interne
    if (vols.isNotEmpty) {
      final basePath = vols.first.path;
      for (final name in ['Download', 'DCIM', 'Pictures', 'Documents', 'Music', 'Movies']) {
        final dir = Directory(p.join(basePath, name));
        if (dir.existsSync()) {
          vols.add(_Volume(name: name, path: dir.path, icon: _folderIcon(name)));
        }
      }
    }

    if (mounted) setState(() { _volumes = vols; _loading = false; });
    _openLastAccess();
  }

  /// Rouvre automatiquement la dernière connexion (FTP ou HTTP) utilisée,
  /// si elle existe encore.
  Future<void> _openLastAccess() async {
    final last = await LastAccessService.load();
    if (last == null || !mounted) return;
    final (type, id) = last;
    if (type == LastAccessType.ftp) {
      final list = await FtpService.listConnections();
      FtpConnection? conn;
      for (final c in list) { if (c.id == id) { conn = c; break; } }
      if (conn != null && mounted) {
        final found = conn;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => FtpExplorerScreen(connection: found)));
          }
        });
      }
    } else {
      final list = await HttpService.listConnections();
      HttpConnection? conn;
      for (final c in list) { if (c.id == id) { conn = c; break; } }
      if (conn != null && mounted) {
        final found = conn;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => HttpExplorerScreen(connection: found)));
          }
        });
      }
    }
  }

  static IconData _folderIcon(String name) {
    switch (name) {
      case 'Download':   return Icons.download_outlined;
      case 'DCIM':
      case 'Pictures':   return Icons.photo_library_outlined;
      case 'Documents':  return Icons.description_outlined;
      case 'Music':      return Icons.music_note_outlined;
      case 'Movies':     return Icons.movie_outlined;
      default:           return Icons.folder_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF111110) : const Color(0xFFF6F5F0);
    final accent = PfColors.accent;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('Fichiers', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Réglages',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const SettingsScreen()))),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: accent,
          labelColor: accent,
          unselectedLabelColor: const Color(0xFF888780),
          tabs: [
            if (_isDesktop)
              const Tab(icon: Icon(Icons.computer_outlined), text: 'Local'),
            if (!_isDesktop) ...[
              const Tab(icon: Icon(Icons.folder_outlined),  text: 'Stockages'),
              const Tab(icon: Icon(Icons.history),           text: 'Récents'),
            ],
            const Tab(icon: Icon(Icons.cloud_outlined),      text: 'FTP'),
            const Tab(icon: Icon(Icons.language_outlined),   text: 'HTTP'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              if (_isDesktop)
                _VolumesTab(volumes: _volumes, isDark: isDark, ch: _ch),
              if (!_isDesktop) ...[
                _VolumesTab(volumes: _volumes, isDark: isDark, ch: _ch),
                _RecentFilesTab(volumes: _volumes, isDark: isDark, ch: _ch),
              ],
              const FtpScreen(),
              const HttpScreen(),
            ]),
    );
  }
}

// ── Volume / disque ───────────────────────────────────────────

class _Volume {
  final String name, path;
  final IconData icon;
  const _Volume({required this.name, required this.path, required this.icon});
}

// ── Onglet Stockages ──────────────────────────────────────────

class _VolumesTab extends StatefulWidget {
  final List<_Volume> volumes;
  final bool isDark;
  final MethodChannel ch;
  const _VolumesTab({required this.volumes, required this.isDark, required this.ch});

  @override
  State<_VolumesTab> createState() => _VolumesTabState();
}

class _VolumesTabState extends State<_VolumesTab> {
  List<FavoriteEntry> _favorites = [];
  String? _selectedVolumePath;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final all = await FavoritesService.list();
    if (mounted) setState(() =>
        _favorites = all.where((f) => f.kind == FavoriteKind.local).toList());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final volumes = widget.volumes;
    final ch = widget.ch;
    final bg     = isDark ? const Color(0xFF1C1C1A) : const Color(0xFFEFEDE6);
    final border = isDark ? const Color(0xFF2E2B42) : const Color(0xFFD3D1C7);
    final txtPri = isDark ? const Color(0xFFE8E6DC) : const Color(0xFF1A1A1A);
    final txtSec = const Color(0xFF888780);
    final accent = PfColors.accent;

    if (volumes.isEmpty && _favorites.isEmpty) return Center(
        child: Text('Aucun stockage trouvé', style: TextStyle(color: txtSec)));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_favorites.isNotEmpty) ...[
          Text('Favoris', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: txtSec)),
          const SizedBox(height: 8),
          for (final fav in _favorites) ...[
            Material(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  final dir = Directory(fav.path);
                  if (!dir.existsSync()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ce dossier n\'existe plus')));
                    FavoritesService.remove(FavoriteKind.local, null, fav.path);
                    _loadFavorites();
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => FileBrowserScreen(root: dir, title: fav.label, ch: ch)));
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border)),
                  child: Row(children: [
                    Icon(Icons.star, color: Colors.amber, size: 22),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fav.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txtPri)),
                      Text(fav.path, style: TextStyle(fontSize: 11, color: txtSec),
                          overflow: TextOverflow.ellipsis),
                    ])),
                    Icon(Icons.chevron_right, color: txtSec),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Text('Stockages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: txtSec)),
          const SizedBox(height: 8),
        ],
        for (final vol in volumes) ...[
          Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _selectedVolumePath =
                    _selectedVolumePath == vol.path ? null : vol.path);
              },
              onDoubleTap: () async {
                await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FileBrowserScreen(
                        root: Directory(vol.path),
                        title: vol.name,
                        ch: ch)));
                _loadFavorites();
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _selectedVolumePath == vol.path ? accent : border, width: _selectedVolumePath == vol.path ? 1.5 : 1)),
                child: Row(children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                    child: Icon(vol.icon, color: accent, size: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vol.name, style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: txtPri)),
                      Text(vol.path, style: TextStyle(fontSize: 11, color: txtSec),
                          overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  if (_selectedVolumePath == vol.path)
                    Icon(Icons.check_circle, color: accent, size: 20),
                  Icon(Icons.chevron_right, color: txtSec),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ── Onglet Récents ────────────────────────────────────────────

class _RecentFilesTab extends StatefulWidget {
  final List<_Volume> volumes;
  final bool isDark;
  final MethodChannel ch;
  const _RecentFilesTab({required this.volumes, required this.isDark, required this.ch});
  @override
  State<_RecentFilesTab> createState() => _RecentFilesTabState();
}

class _RecentFilesTabState extends State<_RecentFilesTab> {
  List<File> _recent = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = <File>[];
    // Chercher dans les dossiers courants du volume principal
    final searchDirs = ['Download', 'DCIM', 'Pictures', 'Documents',
                        'Music', 'Movies', 'WhatsApp'];
    if (widget.volumes.isNotEmpty) {
      final base = widget.volumes.first.path;
      for (final name in searchDirs) {
        final dir = Directory(p.join(base, name));
        try {
          if (!dir.existsSync()) continue;
          dir.listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .forEach(files.add);
        } catch (_) {}
      }
    }
    // Trier par date de modification desc, garder les 50 plus récents
    files.sort((a, b) {
      try {
        return b.statSync().modified.compareTo(a.statSync().modified);
      } catch (_) { return 0; }
    });
    if (mounted) setState(() {
      _recent = files.take(50).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final txtSec = const Color(0xFF888780);
    final txtPri = widget.isDark ? const Color(0xFFE8E6DC) : const Color(0xFF1A1A1A);
    final bg     = widget.isDark ? const Color(0xFF1C1C1A) : const Color(0xFFEFEDE6);
    final border = widget.isDark ? const Color(0xFF2E2B42) : const Color(0xFFD3D1C7);
    final accent = PfColors.accent;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_recent.isEmpty) return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 48, color: txtSec),
          const SizedBox(height: 8),
          Text('Aucun fichier récent trouvé', style: TextStyle(color: txtSec)),
        ]));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _recent.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (ctx, i) {
          final file = _recent[i];
          DateTime? mod;
          int size = 0;
          try { final s = file.statSync(); mod = s.modified; size = s.size; } catch (_) {}
          return Material(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openFile(ctx, file),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border)),
                child: Row(children: [
                  _FileIcon(entity: file, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.basename(file.path),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                            color: txtPri),
                        overflow: TextOverflow.ellipsis),
                      Text('${_fmtSize(size)} · ${_fmtDate(mod)}',
                        style: TextStyle(fontSize: 11, color: txtSec)),
                    ])),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openFile(BuildContext ctx, File file) {
    smartOpenLocalFile(ctx, file, widget.ch);
  }

  static String _fmtSize(int b) {
    if (b < 1024) return '$b o';
    if (b < 1048576) return '${(b/1024).toStringAsFixed(1)} Ko';
    if (b < 1073741824) return '${(b/1048576).toStringAsFixed(1)} Mo';
    return '${(b/1073741824).toStringAsFixed(2)} Go';
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year)
      return 'Aujourd\'hui ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    final diff = now.difference(dt);
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7)  return 'Il y a ${diff.inDays} j';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }
}

// ── Navigateur de fichiers ────────────────────────────────────

class FileBrowserScreen extends StatefulWidget {
  final Directory root;
  final String title;
  final MethodChannel ch;
  const FileBrowserScreen({super.key, required this.root,
      required this.title, required this.ch});
  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  Directory? _current;
  List<FileSystemEntity> _entries = [];
  bool _loading  = true;
  bool _gridView = false;  // false = liste, true = miniatures
  String? _error;
  final Set<String> _selected = {};
  String _searchQuery = '';
  bool _searchActive = false;
  final TextEditingController _searchCtrl = TextEditingController();
  _SortField _sortField = _SortField.name;
  bool _sortAsc = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _gridView = SettingsService.notifier.value.defaultViewMode == DefaultViewMode.grid;
    _load(widget.root);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load(Directory dir) async {
    setState(() => _loading = true);
    try {
      final entries = dir.listSync(followLinks: false)
        ..sort((a, b) {
          if (a is Directory && b is! Directory) return -1;
          if (a is! Directory && b is Directory) return 1;
          return p.basename(a.path).toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
        });
      setState(() { _current = dir; _entries = entries;
          _selected.clear(); _loading = false; _error = null; });
      _checkFavorite();
      RecentFoldersService.touch(RecentFolderKind.local, dir.path,
          p.basename(dir.path).isEmpty ? dir.path : p.basename(dir.path));
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _checkFavorite() async {
    if (_current == null) return;
    final fav = await FavoritesService.isFavorite(FavoriteKind.local, null, _current!.path);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    if (_current == null) return;
    final label = p.basename(_current!.path);
    await FavoritesService.toggle(FavoriteEntry(
        kind: FavoriteKind.local, path: _current!.path,
        label: label.isEmpty ? _current!.path : label));
    _checkFavorite();
  }

  /// Entrées affichées après application de la recherche et du tri.
  List<FileSystemEntity> get _displayEntries {
    var list = _entries;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) => p.basename(e.path).toLowerCase().contains(q)).toList();
    }
    // Précalcule les FileStat une seule fois (évite les appels répétés pendant le tri).
    final withStats = list.map((e) {
      FileStat? st;
      try { st = FileStat.statSync(e.path); } catch (_) {}
      return (entity: e, stat: st);
    }).toList();
    withStats.sort((a, b) {
      final aDir = a.entity is Directory, bDir = b.entity is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      int cmp;
      switch (_sortField) {
        case _SortField.name:
          cmp = p.basename(a.entity.path).toLowerCase()
              .compareTo(p.basename(b.entity.path).toLowerCase());
        case _SortField.date:
          cmp = (a.stat?.modified ?? DateTime(1970))
              .compareTo(b.stat?.modified ?? DateTime(1970));
        case _SortField.size:
          cmp = (a.stat?.size ?? 0).compareTo(b.stat?.size ?? 0);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return withStats.map((r) => r.entity).toList();
  }

  bool get _canGoUp =>
      _current != null && _current!.path != widget.root.path;

  // Mémorise le dernier sous-dossier ouvert depuis le dossier courant,
  // pour permettre le swipe "avancer" (←) symétrique au swipe "retour" (→).
  Directory? _lastOpenedSubDir;

  String get _relPath {
    if (_current == null) return '/';
    final rel = _current!.path.replaceFirst(widget.root.path, '');
    return rel.isEmpty ? '/' : rel;
  }

  Future<void> _rename(FileSystemEntity entity) async {
    final ctrl = TextEditingController(text: p.basename(entity.path));
    final name = await showDialog<String>(context: context, builder: (_) =>
        AlertDialog(title: const Text('Renommer'),
          content: TextField(controller: ctrl, autofocus: true,
              onSubmitted: (v) => Navigator.pop(context, v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
          ]));
    if (name == null || name.trim().isEmpty) return;
    try { await entity.rename(p.join(p.dirname(entity.path), name.trim()));
          _load(_current!); } catch (e) { _snack('Erreur : $e'); }
  }

  Future<void> _delete(List<FileSystemEntity> targets) async {
    int totalFiles = 0, totalDirs = 0;
    for (final e in targets) {
      if (e is Directory) {
        totalDirs++;
        // list(recursive: true) inclut fichiers + dossiers de tous les niveaux
        try {
          await for (final sub in e.list(recursive: true, followLinks: false)) {
            if (sub is Directory) totalDirs++; else totalFiles++;
          }
        } catch (_) {}
      } else {
        totalFiles++;
      }
    }
    String message;
    if (targets.length == 1 && targets.first is Directory) {
      final name = p.basename(targets.first.path);
      final nestedDirs = totalDirs - 1; // exclut le dossier sélectionné lui-même
      final parts = <String>[];
      if (nestedDirs > 0) parts.add('$nestedDirs dossier${nestedDirs > 1 ? 's' : ''}');
      if (totalFiles  > 0) parts.add('$totalFiles fichier${totalFiles  > 1 ? 's' : ''}');
      message = parts.isEmpty
          ? 'Le dossier « $name » est vide.'
          : 'Le dossier « $name » contient ${parts.join(' et ')}, qui seront supprimés définitivement.';
    } else if (targets.length == 1) {
      message = 'Supprimer « ${p.basename(targets.first.path)} » ?';
    } else {
      final subParts = <String>[];
      if (totalDirs  > 0) subParts.add('$totalDirs dossier${totalDirs  > 1 ? 's' : ''}');
      if (totalFiles > 0) subParts.add('$totalFiles fichier${totalFiles > 1 ? 's' : ''}');
      message = subParts.isEmpty
          ? 'Supprimer ${targets.length} éléments ?'
          : 'Supprimer ${targets.length} éléments sélectionnés (au total ${subParts.join(' et ')}) ?';
    }
    final ok = await showDialog<bool>(context: context, builder: (_) =>
        AlertDialog(
          title: const Text('Supprimer ?'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
          ]));
    if (ok != true) return;

    // Suppression différée avec possibilité d'annuler (façon corbeille légère) :
    // les éléments disparaissent immédiatement de l'affichage, mais la
    // suppression réelle sur le disque n'a lieu qu'après quelques secondes,
    // sauf si l'utilisateur appuie sur "Annuler".
    final targetPaths = targets.map((e) => e.path).toSet();
    setState(() {
      _entries = _entries.where((e) => !targetPaths.contains(e.path)).toList();
      _selected.clear();
    });

    var cancelled = false;
    final timer = Timer(const Duration(seconds: 4), () async {
      if (cancelled) return;
      for (final e in targets) {
        try { if (e is Directory) await e.delete(recursive: true);
              else await e.delete(); } catch (_) {}
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(targets.length == 1
          ? '« ${p.basename(targets.first.path)} » supprimé'
          : '${targets.length} éléments supprimés'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'Annuler', onPressed: () {
        cancelled = true;
        timer.cancel();
        if (_current != null) _load(_current!);
      }),
    ));
  }

  Future<void> _copyTo(List<FileSystemEntity> targets) async {
    UniversalClipboard.set(targets.map((e) => ClipItem(
        kind: ClipKind.local,
        name: p.basename(e.path),
        isDir: e is Directory,
        path: e.path)).toList(), cut: false);
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferDestinationScreen(
          title: 'Copier vers…',
          initialLocalPath: _current?.path ?? widget.root.path,
        ),
      ),
    );
    if (changed == true && _current != null) _load(_current!);
  }

  Future<void> _moveTo(List<FileSystemEntity> targets) async {
    UniversalClipboard.set(targets.map((e) => ClipItem(
        kind: ClipKind.local,
        name: p.basename(e.path),
        isDir: e is Directory,
        path: e.path)).toList(), cut: true);
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferDestinationScreen(
          title: 'Déplacer vers…',
          initialLocalPath: _current?.path ?? widget.root.path,
        ),
      ),
    );
    if (changed == true && _current != null) _load(_current!);
  }

  void _copy(List<FileSystemEntity> t) {
    UniversalClipboard.set(t.map((e) => ClipItem(
        kind: ClipKind.local, name: p.basename(e.path),
        isDir: e is Directory, path: e.path)).toList(), cut: false);
    setState(() => _selected.clear());
    _snack('${t.length} élément(s) copié(s)');
  }

  void _cut(List<FileSystemEntity> t) {
    UniversalClipboard.set(t.map((e) => ClipItem(
        kind: ClipKind.local, name: p.basename(e.path),
        isDir: e is Directory, path: e.path)).toList(), cut: true);
    setState(() => _selected.clear());
    _snack('${t.length} élément(s) coupé(s)');
  }

  Future<void> _paste() async {
    if (UniversalClipboard.isEmpty || _current == null) return;
    final ctrl = showTransferProgressDialog(context, title: 'Collage en cours…');
    final result = await pasteClipboardInto(
      destKind: ClipKind.local,
      destPath: _current!.path,
      onProgress: (frac, label) => ctrl.update(frac, label: label),
    );
    if (mounted) await closeTransferProgressDialog(context, ctrl);
    final parts = <String>[];
    if (result.ok > 0) parts.add('${result.ok} collé(s)');
    if (result.errors > 0) parts.add('${result.errors} échec(s)');
    if (result.skipped > 0) parts.add('${result.skipped} ignoré(s) (dossier non transférable ici)');
    _snack(parts.isEmpty ? 'Rien à coller' : parts.join(', '));
    _load(_current!);
  }

  Future<void> _newFolder() async {
    final ctrl = TextEditingController(text: 'Nouveau dossier');
    final name = await showDialog<String>(context: context, builder: (_) =>
        AlertDialog(title: const Text('Nouveau dossier'),
          content: TextField(controller: ctrl, autofocus: true,
              onSubmitted: (v) => Navigator.pop(context, v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Créer')),
          ]));
    if (name == null || name.trim().isEmpty) return;
    try { await Directory(p.join(_current!.path, name.trim())).create(); _load(_current!); }
    catch (e) { _snack('Erreur : $e'); }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _compressTo(List<FileSystemEntity> targets) async {
    if (targets.isEmpty || _current == null) return;
    final defaultName = targets.length == 1
        ? '${p.basenameWithoutExtension(targets.first.path)}.zip'
        : 'archive.zip';
    final ctrl = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Compresser vers…'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nom de l’archive'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Suivant'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    final zipName = name.trim().toLowerCase().endsWith('.zip')
        ? name.trim()
        : '${name.trim()}.zip';

    final tmpDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(
      tmpDir.path,
      'pulsefile_archive',
      DateTime.now().microsecondsSinceEpoch.toString(),
    ));
    await workDir.create(recursive: true);
    final zipPath = p.join(workDir.path, zipName);

    try {
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      for (final t in targets) {
        if (t is Directory) {
          await encoder.addDirectory(t, includeDirName: true);
        } else if (t is File) {
          await encoder.addFile(t);
        }
      }
      encoder.close();

      UniversalClipboard.set([
        ClipItem(
          kind: ClipKind.local,
          name: zipName,
          isDir: false,
          path: zipPath,
        ),
      ], cut: false);

      if (!mounted) return;
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (destinationContext) => TransferDestinationScreen(
            title: 'Compresser vers…',
            initialLocalPath: _current!.path,
          ),
        ),
      );

      if (changed == true && mounted) {
        _selected.clear();
        _load(_current!);
      }
    } catch (e) {
      _snack('Erreur de compression : $e');
    } finally {
      try {
        if (await workDir.exists()) await workDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _extractTo(File zipFile) async {
    final tmpDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(
      tmpDir.path,
      'pulsefile_extract',
      DateTime.now().microsecondsSinceEpoch.toString(),
    ));
    final destDir = Directory(p.join(workDir.path,
        p.basenameWithoutExtension(zipFile.path)));

    try {
      await destDir.create(recursive: true);
      await extractFileToDisk(zipFile.path, destDir.path);

      UniversalClipboard.set([
        ClipItem(
          kind: ClipKind.local,
          name: p.basename(destDir.path),
          isDir: true,
          path: destDir.path,
        ),
      ], cut: false);

      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => TransferDestinationScreen(
            title: 'Décompresser vers…',
            initialLocalPath: _current?.path ?? p.dirname(zipFile.path),
          ),
        ),
      );

      if (changed == true && mounted && _current != null) {
        _load(_current!);
      }
    } catch (e) {
      _snack('Erreur de décompression : $e');
    } finally {
      try {
        if (await workDir.exists()) await workDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  String _fmtDateFull(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showProperties(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    FileStat? st;
    try { st = FileStat.statSync(entity.path); } catch (_) {}
    final rows = <PropertiesRow>[
      PropertiesRow('Type', isDir ? 'Dossier' : 'Fichier'),
      PropertiesRow('Chemin', entity.path),
      if (!isDir && st != null) PropertiesRow('Taille', _RecentFilesTabState._fmtSize(st.size)),
      if (st != null) PropertiesRow('Modifié', _fmtDateFull(st.modified)),
    ];
    if (isDir) {
      try {
        final children = (entity).listSync();
        final files = children.whereType<File>().length;
        final dirs  = children.whereType<Directory>().length;
        rows.add(PropertiesRow('Contenu', '$dirs dossier(s), $files fichier(s)'));
      } catch (_) {}
    }
    await showPropertiesDialog(context, name: name, isDir: isDir, rows: rows);
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final accent  = PfColors.accent;
    final bg      = isDark ? const Color(0xFF111110) : const Color(0xFFF6F5F0);
    final cardBg  = isDark ? const Color(0xFF1C1C1A) : const Color(0xFFEFEDE6);
    final border  = isDark ? const Color(0xFF2E2B42) : const Color(0xFFD3D1C7);
    final txtPri  = isDark ? const Color(0xFFE8E6DC) : const Color(0xFF1A1A1A);
    final txtSec  = const Color(0xFF888780);
    final selecting = _selected.isNotEmpty;

    return SwipeNav(
      enableBack: _canGoUp,
      onSwipeBack: () { if (_canGoUp) _load(_current!.parent); },
      enableForward: _lastOpenedSubDir != null,
      onSwipeForward: () {
        if (_lastOpenedSubDir != null) _load(_lastOpenedSubDir!);
      },
      child: Scaffold(
      backgroundColor: bg,
      appBar: SwipeRecentsAppBar(child: AppBar(
        backgroundColor: bg,
        leading: _searchActive
            ? IconButton(icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _searchActive = false; _searchQuery = ''; _searchCtrl.clear();
                }))
            : (_canGoUp
                ? IconButton(icon: const Icon(Icons.arrow_upward),
                    onPressed: () => _load(_current!.parent))
                : null),
        title: _searchActive
            ? TextField(controller: _searchCtrl, autofocus: true,
                decoration: const InputDecoration(border: InputBorder.none,
                    hintText: 'Rechercher dans ce dossier…'),
                style: const TextStyle(fontSize: 14),
                onChanged: (v) => setState(() => _searchQuery = v))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
                Text(_relPath, style: TextStyle(fontSize: 10, color: txtSec),
                    overflow: TextOverflow.ellipsis),
              ]),
        actions: [
          if (selecting) ...[
            IconButton(icon: const Icon(Icons.copy_outlined),
                onPressed: () => _copy(_selected.map(
                    (s) => _entries.firstWhere((e) => e.path == s)).toList())),
            IconButton(icon: const Icon(Icons.cut_outlined),
                onPressed: () => _cut(_selected.map(
                    (s) => _entries.firstWhere((e) => e.path == s)).toList())),
            PopupMenuButton<String>(
              tooltip: 'Actions sur la sélection',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                final items = _selected.map(
                    (s) => _entries.firstWhere((e) => e.path == s)).toList();
                switch (action) {
                  case 'compress':
                    _compressTo(items);
                  case 'extract':
                    if (items.length == 1 && items.first is File &&
                        p.extension(items.first.path).toLowerCase() == '.zip') {
                      _extractTo(items.first as File);
                    }
                }
              },
              itemBuilder: (_) {
                final items = _selected.map(
                    (s) => _entries.firstWhere((e) => e.path == s)).toList();
                final hasZip = items.length == 1 && items.first is File &&
                    p.extension(items.first.path).toLowerCase() == '.zip';
                return [
                  const PopupMenuItem(
                    value: 'compress',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.folder_zip_outlined),
                      title: Text('Compresser vers…'),
                    ),
                  ),
                  if (hasZip)
                    const PopupMenuItem(
                      value: 'extract',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.unarchive_outlined),
                        title: Text('Décompresser vers…'),
                      ),
                    ),
                ];
              },
            ),
            IconButton(icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(_selected.map(
                    (s) => _entries.firstWhere((e) => e.path == s)).toList())),
            IconButton(icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected.clear())),
          ] else if (!_searchActive) ...[
            IconButton(icon: const Icon(Icons.search),
                tooltip: 'Rechercher',
                onPressed: () => setState(() => _searchActive = true)),
            IconButton(
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border,
                  color: _isFavorite ? Colors.amber : null),
              tooltip: _isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
              onPressed: _toggleFavorite,
            ),
            PopupMenuButton<_SortField>(
              icon: const Icon(Icons.sort),
              tooltip: 'Trier',
              onSelected: (f) => setState(() {
                if (_sortField == f) { _sortAsc = !_sortAsc; } else { _sortField = f; _sortAsc = true; }
              }),
              itemBuilder: (_) => [
                _sortMenuItem(_SortField.name, 'Nom'),
                _sortMenuItem(_SortField.date, 'Date'),
                _sortMenuItem(_SortField.size, 'Taille'),
              ],
            ),
            if (!UniversalClipboard.isEmpty)
              IconButton(icon: const Icon(Icons.content_paste_outlined),
                  onPressed: _paste),
            IconButton(icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _newFolder),
            IconButton(
              icon: Icon(_gridView ? Icons.view_list_outlined : Icons.grid_view_outlined),
              tooltip: _gridView ? 'Vue liste' : 'Miniatures',
              onPressed: () => setState(() => _gridView = !_gridView),
            ),
            const StorageSwitcherButton(current: StorageKind.local),
          ],
        ],
      )),
      body: _error != null
          ? _ErrorView(error: _error!, onRetry: () => _init(), isDark: isDark)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _displayEntries.isEmpty
                  ? Center(child: Text(
                        _searchQuery.isNotEmpty ? 'Aucun résultat' : 'Dossier vide',
                        style: TextStyle(color: txtSec)))
                  : _gridView
                    ? _buildGrid(accent, cardBg, border, txtPri, txtSec, selecting)
                    : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _displayEntries.length,
                      itemBuilder: (_, i) => _buildListItem(
                          _displayEntries[i], accent, cardBg, border, txtPri, txtSec, selecting)),
    ),
    );
  }

  // ── Helpers de rendu ─────────────────────────────────────────────────────────

  static const _kImageExts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'};
  bool _isImage(FileSystemEntity e) =>
      e is File && _kImageExts.contains(p.extension(e.path).toLowerCase());

  void _toggleLocalSelection(FileSystemEntity entity) {
    setState(() {
      if (_selected.contains(entity.path)) {
        _selected.remove(entity.path);
      } else {
        _selected.add(entity.path);
      }
    });
  }

  void _openLocalEntity(FileSystemEntity entity) {
    if (entity is Directory) {
      _lastOpenedSubDir = entity;
      _load(entity);
    } else if (entity is File) {
      _openFile(entity);
    }
  }

  void _onLongPress(FileSystemEntity entity, bool isSel) =>
      setState(() { if (isSel) _selected.remove(entity.path);
        else _selected.add(entity.path); });

  void _onMenuAction(FileSystemEntity entity, String v) {
    switch (v) {
      case 'rename': _rename(entity);
      case 'copy_to': _copyTo([entity]);
      case 'move_to': _moveTo([entity]);
      case 'copy':   _copy([entity]);
      case 'cut':    _cut([entity]);
      case 'compress': _compressTo([entity]);
      case 'extract':
        if (entity is File) _extractTo(entity);
      case 'properties': _showProperties(entity);
      case 'delete': _delete([entity]);
      case 'share':
        widget.ch.invokeMethod('shareFile', {'path': entity.path});
    }
  }

  PopupMenuItem<_SortField> _sortMenuItem(_SortField field, String label) {
    final active = _sortField == field;
    return PopupMenuItem(value: field, child: Row(children: [
      SizedBox(width: 22, child: active
          ? Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16)
          : null),
      const SizedBox(width: 4),
      Text(label, style: active ? const TextStyle(fontWeight: FontWeight.w700) : null),
    ]));
  }

  List<PopupMenuEntry<String>> _menuItemsFor(FileSystemEntity entity) {
    final isZip = entity is File && p.extension(entity.path).toLowerCase() == '.zip';
    return [
      _mi('rename', Icons.edit_outlined,  'Renommer'),
      _mi('copy_to', Icons.copy_outlined,  'Copier vers…'),
      _mi('move_to', Icons.drive_file_move_outlined, 'Déplacer vers…'),
      _mi('copy',   Icons.copy_outlined,  'Copier'),
      _mi('cut',    Icons.cut_outlined,   'Couper'),
      _mi('compress', Icons.folder_zip_outlined, 'Compresser vers…'),
      if (isZip) _mi('extract', Icons.unarchive_outlined, 'Décompresser vers…'),
      if (entity is File)
        _mi('share', Icons.share_outlined, 'Partager'),
      _mi('properties', Icons.info_outline, 'Propriétés'),
      _mi('delete', Icons.delete_outline, 'Supprimer', color: Colors.red),
    ];
  }

  Widget _contextMenu(FileSystemEntity entity, Color txtSec) =>
    Theme(
      data: Theme.of(context).copyWith(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap))),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, size: 18, color: txtSec),
        onSelected: (v) => _onMenuAction(entity, v),
        itemBuilder: (_) => _menuItemsFor(entity),
      ));

  /// Affiche le menu contextuel au clic droit (Windows/desktop) à la position du curseur.
  Future<void> _showContextMenu(
      BuildContext context, Offset globalPosition, FileSystemEntity entity) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _menuItemsFor(entity),
    );
    if (selected != null && context.mounted) _onMenuAction(entity, selected);
  }

  Widget _buildListItem(FileSystemEntity entity, Color accent, Color cardBg,
      Color border, Color txtPri, Color txtSec, bool selecting) {
    final isDir = entity is Directory;
    final name  = p.basename(entity.path);
    final isSel = _selected.contains(entity.path);
    return Material(
      color: isSel ? accent.withOpacity(0.18) : cardBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggleLocalSelection(entity),
        onDoubleTap: () => _openLocalEntity(entity),
        onLongPress: () => _onLongPress(entity, isSel),
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition, entity),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? accent : border, width: isSel ? 1.5 : 1)),
          child: Row(children: [
            _FileIcon(entity: entity, accent: accent),
            const SizedBox(width: 10),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: txtPri))),
            const SizedBox(width: 8),
            Text(_subtitle(entity), style: TextStyle(fontSize: 11, color: txtSec)),
            if (!selecting) _contextMenu(entity, txtSec),
            if (isSel) Icon(Icons.check_circle, color: accent, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildGrid(Color accent, Color cardBg, Color border,
      Color txtPri, Color txtSec, bool selecting) =>
    GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: SettingsService.notifier.value.gridColumns,
          crossAxisSpacing: 6, mainAxisSpacing: 6,
          childAspectRatio: 0.75),
      itemCount: _displayEntries.length,
      itemBuilder: (_, i) => _buildGridItem(
          _displayEntries[i], accent, cardBg, border, txtPri, txtSec, selecting),
    );

  Widget _buildGridItem(FileSystemEntity entity, Color accent, Color cardBg,
      Color border, Color txtPri, Color txtSec, bool selecting) {
    final name  = p.basename(entity.path);
    final isSel = _selected.contains(entity.path);
    final isImg = _isImage(entity);

    return GestureDetector(
      onTap: () => _toggleLocalSelection(entity),
      onDoubleTap: () => _openLocalEntity(entity),
      onLongPress: () => _onLongPress(entity, isSel),
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition, entity),
      child: Container(
        decoration: BoxDecoration(
          color: isSel ? accent.withOpacity(0.18) : cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? accent : border, width: isSel ? 1.5 : 1)),
        child: Column(children: [
          Expanded(child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            child: isImg
              ? Image.file(entity as File, fit: BoxFit.cover, width: double.infinity,
                  errorBuilder: (_, __, ___) => _gridIcon(entity, accent))
              : _gridIcon(entity, accent),
          )),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: TextStyle(fontSize: 10, color: txtPri),
                    overflow: TextOverflow.ellipsis, maxLines: 2)),
                if (!selecting)
                  GestureDetector(
                    onTap: () {},
                    child: SizedBox(width: 20, height: 20,
                      child: _contextMenu(entity, txtSec)),
                  ),
                if (isSel)
                  Icon(Icons.check_circle, color: accent, size: 14),
              ]),
              Text(_subtitle(entity), style: TextStyle(fontSize: 9, color: txtSec),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _gridIcon(FileSystemEntity entity, Color accent) {
    final isDir = entity is Directory;
    return Center(child: Icon(
      isDir ? Icons.folder_rounded : _iconForFile(entity.path),
      size: 52,
      color: isDir ? accent : const Color(0xFF888780),
    ));
  }

  IconData _iconForFile(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.pdf':                        return Icons.picture_as_pdf_outlined;
      case '.jpg': case '.jpeg':
      case '.png': case '.gif':
      case '.webp':                       return Icons.image_outlined;
      case '.mp4': case '.mov':
      case '.avi': case '.mkv':           return Icons.movie_outlined;
      case '.mp3': case '.wav':
      case '.m4a': case '.ogg':           return Icons.audiotrack_outlined;
      case '.zip': case '.rar':
      case '.7z':                         return Icons.folder_zip_outlined;
      case '.txt': case '.md':            return Icons.article_outlined;
      case '.json': case '.xml':
      case '.yaml': case '.yml':          return Icons.code_outlined;
      case '.apk':                        return Icons.android_outlined;
      case '.doc': case '.docx':          return Icons.description_outlined;
      case '.xls': case '.xlsx':          return Icons.table_chart_outlined;
      case '.ppt': case '.pptx':          return Icons.slideshow_outlined;
      default:                            return Icons.insert_drive_file_outlined;
    }
  }

  void _init() => _load(widget.root);

  String _subtitle(FileSystemEntity e) {
    try {
      final stat = FileStat.statSync(e.path);
      final date = _fmtDate(stat.modified);
      if (e is Directory) {
        final count = (e).listSync().length;
        final label = '$count élément${count != 1 ? 's' : ''}';
        return date.isEmpty ? label : '$date  ·  $label';
      }
      final size = _RecentFilesTabState._fmtSize(stat.size);
      return date.isEmpty ? size : '$date  ·  $size';
    } catch (_) { return ''; }
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final local = d.toLocal();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year.toString().substring(2)}';
  }

  void _openFile(File file) {
    smartOpenLocalFile(context, file, widget.ch,
        onChanged: () { if (_current != null) _load(_current!); });
  }

  PopupMenuItem<String> _mi(String v, IconData icon, String label, {Color? color}) =>
      PopupMenuItem(value: v, child: ListTile(dense: true,
          leading: Icon(icon, color: color, size: 20),
          title: Text(label, style: color != null ? TextStyle(color: color) : null)));
}

// ── Icône de fichier ──────────────────────────────────────────

class _FileIcon extends StatelessWidget {
  final FileSystemEntity entity;
  final Color accent;
  const _FileIcon({required this.entity, required this.accent});

  @override
  Widget build(BuildContext context) {
    final isDir = entity is Directory;
    final ext = isDir ? '' : p.extension(entity.path).toLowerCase();
    final (icon, color) = _resolve(isDir, ext);
    return Container(width: 38, height: 38,
      decoration: BoxDecoration(color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, color: color, size: 20));
  }

  static (IconData, Color) _resolve(bool isDir, String ext) {
    if (isDir) return (Icons.folder_outlined, const Color(0xFFFFB300));
    switch (ext) {
      case '.jpg': case '.jpeg': case '.png': case '.gif':
      case '.webp': case '.bmp':
        return (Icons.image_outlined,          const Color(0xFF42A5F5));
      case '.mp4': case '.mkv': case '.avi': case '.mov': case '.webm':
        return (Icons.videocam_outlined,       const Color(0xFFEF5350));
      case '.mp3': case '.wav': case '.flac': case '.aac': case '.ogg':
        return (Icons.music_note_outlined,     const Color(0xFFAB47BC));
      case '.pdf':
        return (Icons.picture_as_pdf_outlined, const Color(0xFFEF5350));
      case '.doc': case '.docx':
        return (Icons.description_outlined,    const Color(0xFF42A5F5));
      case '.xls': case '.xlsx':
        return (Icons.table_chart_outlined,    const Color(0xFF66BB6A));
      case '.zip': case '.rar': case '.7z': case '.tar': case '.gz':
        return (Icons.folder_zip_outlined,     const Color(0xFFFFB300));
      case '.apk':
        return (Icons.android_outlined,        const Color(0xFF66BB6A));
      case '.txt': case '.md': case '.log':
        return (Icons.article_outlined,        const Color(0xFF78909C));
      default:
        return (Icons.insert_drive_file_outlined, const Color(0xFF90A4AE));
    }
  }
}

// ── Visionneuse / éditeur texte ───────────────────────────────

class _TextViewerScreen extends StatefulWidget {
  final File file;
  const _TextViewerScreen({required this.file});
  @override
  State<_TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<_TextViewerScreen> {
  String _content = '';
  bool _loading = true, _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final c = await widget.file.readAsString();
      _ctrl = TextEditingController(text: c);
      setState(() { _content = c; _loading = false; });
    } catch (e) { setState(() { _content = 'Erreur : $e'; _loading = false; }); }
  }

  Future<void> _save() async {
    await widget.file.writeAsString(_ctrl.text);
    setState(() => _editing = false);
  }

  bool get _dirty => _editing && _ctrl.text != _content;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = PfColors.accent;
    final bg     = isDark ? const Color(0xFF111110) : const Color(0xFFF6F5F0);
    final txtPri = isDark ? const Color(0xFFE8E6DC) : const Color(0xFF1A1A1A);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg,
        title: Text(p.basename(widget.file.path),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        actions: [
          if (!_loading) ...[
            if (_editing) TextButton.icon(onPressed: _save,
                icon: Icon(Icons.save_outlined, color: accent, size: 18),
                label: Text('Sauv.', style: TextStyle(color: accent))),
            IconButton(icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
                onPressed: () { if (_editing) { _ctrl.text = _content;
                  setState(() => _editing = false); }
                  else setState(() => _editing = true); }),
          ]],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : Padding(padding: const EdgeInsets.all(12),
              child: _editing
                  ? TextField(controller: _ctrl,
                      style: TextStyle(fontSize: 13, color: txtPri,
                          fontFamily: 'monospace', height: 1.5),
                      maxLines: null, expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(border: InputBorder.none))
                  : SingleChildScrollView(child: SelectableText(_content,
                      style: TextStyle(fontSize: 13, color: txtPri,
                          fontFamily: 'monospace', height: 1.5)))),
    ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final bool isDark;
  const _ErrorView({required this.error, required this.onRetry, required this.isDark});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.folder_off_outlined, size: 48, color: Color(0xFF888780)),
      const SizedBox(height: 12),
      const Text('Accès refusé ou stockage introuvable',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: onRetry,
          icon: const Icon(Icons.refresh), label: const Text('Réessayer'),
          style: ElevatedButton.styleFrom(
              backgroundColor: PfColors.accent,
              foregroundColor: Colors.white)),
    ])));
}
