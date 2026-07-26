// lib/screens/ftp_screen.dart
//
// Gestionnaire de connexions FTP : liste, création, édition, suppression,
// et explorateur de fichiers FTP (parcourir, uploader, télécharger, supprimer,
// renommer, créer un dossier, éditer les fichiers texte).
//
import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/ftp_service.dart';
import '../services/last_access_service.dart';
import '../services/favorites_service.dart';
import '../services/settings_service.dart';
import '../theme/pf_colors.dart';
import '../utils/top_snack.dart';
import '../widgets/remote_folder_picker.dart';
import '../widgets/local_folder_picker.dart';
import '../widgets/local_file_picker.dart';
import '../widgets/properties_dialog.dart';
import '../widgets/swipe_nav.dart';
import '../utils/open_external.dart';
import '../utils/file_type.dart';
import '../widgets/image_viewer_screen.dart';
import '../widgets/transfer_progress_dialog.dart';
import '../services/universal_clipboard.dart';
import '../widgets/text_editor_screen.dart';
import '../widgets/storage_switcher.dart';
import '../widgets/swipe_recents_appbar.dart';
import '../services/recent_folders_service.dart';
import 'package:archive/archive_io.dart';

// ── Écran principal : liste des connexions ─────────────────────────────────────

class FtpScreen extends StatefulWidget {
  const FtpScreen({super.key});
  @override State<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends State<FtpScreen> {
  List<FtpConnection> _connections = [];
  List<FavoriteEntry> _favorites = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await FtpService.listConnections();
    final favs = await FavoritesService.list();
    if (mounted) setState(() {
      _connections = list;
      _favorites = favs.where((f) => f.kind == FavoriteKind.ftp).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final accent  = PfColors.accent;
    final bg      = isDark ? const Color(0xFF111110) : const Color(0xFFF6F5F0);
    final cardBg  = isDark ? const Color(0xFF1C1C1A) : Colors.white;
    final border  = isDark ? const Color(0xFF2C2C2A) : const Color(0xFFE8E6DC);
    final textCol = isDark ? Colors.white             : const Color(0xFF1A1A18);
    final subCol  = const Color(0xFF888780);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: const Text('Connexions FTP', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: accent),
            tooltip: 'Nouvelle connexion',
            onPressed: () => _editConnection(context, null),
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _connections.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: subCol),
              const Gap(12),
              Text('Aucune connexion FTP', style: TextStyle(color: subCol)),
              const Gap(8),
              TextButton.icon(
                onPressed: () => _editConnection(context, null),
                icon: Icon(Icons.add, color: accent),
                label: Text('Ajouter', style: TextStyle(color: accent)),
              ),
            ]))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_favorites.isNotEmpty) ...[
                  Text('Favoris', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subCol)),
                  const Gap(8),
                  for (final fav in _favorites) ...[
                    Material(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          final conn = _connections.where((c) => c.id == fav.connectionId).toList();
                          if (conn.isEmpty) {
                            FavoritesService.remove(FavoriteKind.ftp, fav.connectionId, fav.path);
                            _load();
                            return;
                          }
                          if (conn.first.id != null) {
                            LastAccessService.save(LastAccessType.ftp, conn.first.id!);
                          }
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => FtpExplorerScreen(
                                  connection: conn.first, initialPath: fav.path)));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: border)),
                          child: Row(children: [
                            Icon(Icons.star, color: Colors.amber, size: 20),
                            const Gap(10),
                            Expanded(child: Text(fav.label, style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w500, color: textCol),
                                overflow: TextOverflow.ellipsis)),
                            Icon(Icons.chevron_right, color: subCol),
                          ]),
                        ),
                      ),
                    ),
                    const Gap(8),
                  ],
                  const Gap(8),
                  Text('Connexions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subCol)),
                  const Gap(8),
                ],
                for (final conn in _connections) ...[
                Material(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (conn.id != null) LastAccessService.save(LastAccessType.ftp, conn.id!);
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => FtpExplorerScreen(connection: conn)));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.dns_outlined, size: 20, color: accent),
                        ),
                        const Gap(12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(conn.name, style: TextStyle(fontWeight: FontWeight.w600,
                              fontSize: 14, color: textCol)),
                          Text('${conn.user}@${conn.host}:${conn.port}',
                              style: TextStyle(fontSize: 12, color: subCol)),
                        ])),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: subCol),
                          onPressed: () => _editConnection(context, conn),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFE24B4A)),
                          onPressed: () => _deleteConnection(context, conn),
                        ),
                      ]),
                    ),
                  ),
                ),
                ],
              ],
            ),
    );
  }

  Future<void> _editConnection(BuildContext context, FtpConnection? existing) async {
    final result = await showModalBottomSheet<FtpConnection>(
      context: context, isScrollControlled: true,
      builder: (_) => _ConnectionEditor(existing: existing),
    );
    if (result != null) {
      await FtpService.saveConnection(result);
      _load();
    }
  }

  Future<void> _deleteConnection(BuildContext context, FtpConnection conn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cette connexion ?'),
        content: Text('${conn.name} (${conn.host}) sera supprimée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE24B4A)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FtpService.deleteConnection(conn.id!);
      final last = await LastAccessService.load();
      if (last != null && last.$1 == LastAccessType.ftp && last.$2 == conn.id) {
        await LastAccessService.clear();
      }
      _load();
    }
  }
}

// ── Éditeur de connexion (bottom sheet) ───────────────────────────────────────

class _ConnectionEditor extends StatefulWidget {
  final FtpConnection? existing;
  const _ConnectionEditor({this.existing});
  @override State<_ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<_ConnectionEditor> {
  final _name    = TextEditingController();
  final _host    = TextEditingController();
  final _port    = TextEditingController(text: '21');
  final _user    = TextEditingController(text: 'anonymous');
  final _pass    = TextEditingController();
  final _path    = TextEditingController(text: '/');
  bool _passive  = true;
  bool _testing  = false;
  bool _obscure  = true;
  String? _downloadPath;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final c = widget.existing!;
      _name.text = c.name; _host.text = c.host;
      _port.text = c.port.toString(); _user.text = c.user;
      _pass.text = c.password; _path.text = c.initialPath;
      _passive = c.passive;
      _downloadPath = c.defaultDownloadPath;
    }
  }

  Future<void> _pickDownloadPath() async {
    final picked = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => LocalFolderPickerScreen(initialPath: _downloadPath)));
    if (picked != null) setState(() => _downloadPath = picked);
  }

  @override
  Widget build(BuildContext context) {
    final accent = PfColors.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1C1C1A) : Colors.white;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFF888780).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2))),
          Text(widget.existing == null ? 'Nouvelle connexion FTP' : 'Modifier la connexion',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Gap(16),
          _field(_name,  'Nom',       Icons.label_outlined),
          const Gap(10),
          Row(children: [
            Expanded(flex: 3, child: _field(_host, 'Hôte / IP', Icons.dns_outlined)),
            const Gap(10),
            Expanded(child: _field(_port, 'Port', Icons.numbers, keyboard: TextInputType.number)),
          ]),
          const Gap(10),
          _field(_user, 'Utilisateur', Icons.person_outlined),
          const Gap(10),
          TextField(
            controller: _pass, obscureText: _obscure,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outlined),
              labelText: 'Mot de passe',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const Gap(10),
          _field(_path, 'Chemin initial', Icons.folder_outlined),
          const Gap(10),
          SwitchListTile(
            value: _passive, activeColor: accent,
            onChanged: (v) => setState(() => _passive = v),
            title: const Text('Mode passif'),
            subtitle: const Text('Recommandé derrière un pare-feu'),
            contentPadding: EdgeInsets.zero,
          ),
          const Gap(10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Dossier de téléchargement par défaut'),
            subtitle: Text(_downloadPath ?? 'Non défini (demande à chaque fois)',
                style: TextStyle(fontSize: 11,
                    color: _downloadPath == null ? Colors.grey : null),
                overflow: TextOverflow.ellipsis),
            trailing: _downloadPath == null
                ? IconButton(icon: const Icon(Icons.folder_open_outlined),
                    tooltip: 'Choisir', onPressed: _pickDownloadPath)
                : IconButton(icon: const Icon(Icons.close), tooltip: 'Effacer',
                    onPressed: () => setState(() => _downloadPath = null)),
            onTap: _pickDownloadPath,
          ),
          const Gap(16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConn,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find_outlined, size: 18),
                label: const Text('Tester'),
              ),
            ),
            const Gap(10),
            Expanded(
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(backgroundColor: accent),
                child: const Text('Enregistrer'),
              ),
            ),
          ]),
        ])),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text}) =>
    TextField(
      controller: ctrl, keyboardType: keyboard,
      decoration: InputDecoration(
        prefixIcon: Icon(icon), labelText: label, border: const OutlineInputBorder()),
    );

  Future<void> _testConn() async {
    setState(() => _testing = true);
    final conn = _buildConn();
    final ok   = await FtpService.testConnection(conn);
    if (mounted) {
      setState(() => _testing = false);
      showTopSnack(context,
          ok ? 'Connexion réussie !' : 'Connexion échouée',
          backgroundColor: ok ? const Color(0xFF0F6E56) : const Color(0xFFE24B4A));
    }
  }

  void _save() {
    if (_name.text.isEmpty || _host.text.isEmpty) {
      showTopSnack(context, 'Nom et hôte requis', backgroundColor: const Color(0xFFE24B4A));
      return;
    }
    Navigator.pop(context, _buildConn());
  }

  FtpConnection _buildConn() => FtpConnection(
    id:          widget.existing?.id,
    name:        _name.text.trim(),
    host:        _host.text.trim(),
    port:        int.tryParse(_port.text) ?? 21,
    user:        _user.text.trim(),
    password:    _pass.text,
    passive:     _passive,
    initialPath: _path.text.trim().isEmpty ? '/' : _path.text.trim(),
    defaultDownloadPath: _downloadPath,
  );
}

// ── Explorateur FTP ───────────────────────────────────────────────────────────

enum _SortField { name, date, size }

class FtpExplorerScreen extends StatefulWidget {
  final FtpConnection connection;
  final String? initialPath;
  const FtpExplorerScreen({super.key, required this.connection, this.initialPath});
  @override State<FtpExplorerScreen> createState() => _FtpExplorerScreenState();
}

class _FtpExplorerScreenState extends State<FtpExplorerScreen> {
  String _currentPath = '/';
  List<FtpEntry> _entries = [];
  bool _loading = true;
  String? _error;
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;
  String _searchQuery = '';
  bool _searchActive = false;
  final TextEditingController _searchCtrl = TextEditingController();
  _SortField _sortField = _SortField.name;
  bool _sortAsc = true;
  bool _isFavorite = false;
  bool _gridView = false;
  bool _dragging = false;
  String? _lastOpenedSubDir;

  @override
  void initState() {
    super.initState();
    _gridView = SettingsService.notifier.value.defaultViewMode == DefaultViewMode.grid;
    _currentPath = widget.initialPath ?? widget.connection.initialPath;
    _load(_currentPath);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load(String path) async {
    final navigating = path != _currentPath;
    setState(() { _loading = true; _error = null; if (navigating) _selected.clear(); });
    try {
      final entries = await FtpService.list(widget.connection, path);
      if (mounted) setState(() { _currentPath = path; _entries = entries; _loading = false; });
      _checkFavorite();
      RecentFoldersService.touch(RecentFolderKind.ftp, path,
          '${widget.connection.name} — $path', connectionId: widget.connection.id);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _checkFavorite() async {
    final fav = await FavoritesService.isFavorite(
        FavoriteKind.ftp, widget.connection.id, _currentPath);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final label = '${widget.connection.name} — $_currentPath';
    await FavoritesService.toggle(FavoriteEntry(
        kind: FavoriteKind.ftp, connectionId: widget.connection.id,
        path: _currentPath, label: label));
    _checkFavorite();
  }

  /// Entrées affichées après application de la recherche et du tri.
  List<FtpEntry> get _displayEntries {
    var list = _entries;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    final sorted = List<FtpEntry>.from(list);
    sorted.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int cmp;
      switch (_sortField) {
        case _SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortField.date:
          cmp = (a.modified ?? DateTime(1970)).compareTo(b.modified ?? DateTime(1970));
        case _SortField.size:
          cmp = a.size.compareTo(b.size);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  bool get _canGoUp => _currentPath != '/' && _currentPath.isNotEmpty;

  String get _parentPath {
    final parts = _currentPath.split('/');
    if (parts.length <= 1) return '/';
    return parts.sublist(0, parts.length - 1).join('/').isEmpty ? '/' :
        parts.sublist(0, parts.length - 1).join('/');
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final accent  = PfColors.accent;
    final bg      = isDark ? const Color(0xFF111110) : const Color(0xFFF6F5F0);
    final cardBg  = isDark ? const Color(0xFF1C1C1A) : Colors.white;
    final border  = isDark ? const Color(0xFF2C2C2A) : const Color(0xFFE8E6DC);
    final textCol = isDark ? Colors.white             : const Color(0xFF1A1A18);
    final subCol  = const Color(0xFF888780);

    return SwipeNav(
      enableBack: _canGoUp,
      onSwipeBack: () { if (_canGoUp) _load(_parentPath); },
      enableForward: _lastOpenedSubDir != null,
      onSwipeForward: () {
        if (_lastOpenedSubDir != null) _load(_lastOpenedSubDir!);
      },
      child: DropTarget(
      enable: Platform.isWindows || Platform.isMacOS || Platform.isLinux,
      onDragDone: (detail) => _uploadDropped(detail.files),
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      child: Stack(children: [
      Scaffold(
      backgroundColor: bg,
      appBar: SwipeRecentsAppBar(child: AppBar(
        backgroundColor: bg,
        leading: _searchActive
            ? IconButton(icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _searchActive = false; _searchQuery = ''; _searchCtrl.clear();
                }))
            : (_selecting
                ? IconButton(icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selected.clear()))
                : (_canGoUp
                    ? IconButton(icon: const Icon(Icons.arrow_upward),
                        onPressed: () => _load(_parentPath))
                    : null)),
        title: _searchActive
            ? TextField(controller: _searchCtrl, autofocus: true,
                decoration: const InputDecoration(border: InputBorder.none,
                    hintText: 'Rechercher dans ce dossier…'),
                style: const TextStyle(fontSize: 14),
                onChanged: (v) => setState(() => _searchQuery = v))
            : (_selecting
                ? Text('${_selected.length} sélectionné(s)',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.connection.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(_currentPath, style: TextStyle(fontSize: 10, color: subCol),
                        overflow: TextOverflow.ellipsis),
                  ])),
        actions: _selecting
            ? [
                IconButton(icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Copier la sélection',
                    onPressed: () => _copy(_entries.where(
                        (e) => _selected.contains(e.path)).toList())),
                IconButton(icon: const Icon(Icons.cut_outlined),
                    tooltip: 'Couper la sélection',
                    onPressed: () => _cut(_entries.where(
                        (e) => _selected.contains(e.path)).toList())),
                IconButton(icon: const Icon(Icons.download_outlined),
                    tooltip: 'Télécharger la sélection',
                    onPressed: () => _downloadSelected(context)),
                IconButton(icon: const Icon(Icons.delete_outline),
                    tooltip: 'Supprimer la sélection',
                    onPressed: () => _deleteSelected(context)),
              ]
            : (_searchActive
                ? []
                : [
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
                        if (_sortField == f) { _sortAsc = !_sortAsc; }
                        else { _sortField = f; _sortAsc = true; }
                      }),
                      itemBuilder: (_) => [
                        _sortMenuItem(_SortField.name, 'Nom'),
                        _sortMenuItem(_SortField.date, 'Date'),
                        _sortMenuItem(_SortField.size, 'Taille'),
                      ],
                    ),
                    IconButton(
                      icon: Icon(_gridView ? Icons.view_list_outlined : Icons.grid_view_outlined),
                      tooltip: _gridView ? 'Vue liste' : 'Miniatures',
                      onPressed: () => setState(() => _gridView = !_gridView),
                    ),
                    if (!UniversalClipboard.isEmpty)
                      IconButton(icon: const Icon(Icons.content_paste_outlined),
                          tooltip: 'Coller', onPressed: () => _paste(context)),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(_currentPath)),
                    IconButton(icon: const Icon(Icons.create_new_folder_outlined),
                        tooltip: 'Nouveau dossier', onPressed: () => _mkdir(context)),
                    IconButton(icon: const Icon(Icons.upload_outlined),
                        tooltip: 'Envoyer des fichiers', onPressed: () => _uploadFile(context)),
                    StorageSwitcherButton(
                        current: StorageKind.ftp, currentConnectionId: widget.connection.id),
                  ]),
      )),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off, size: 40, color: subCol),
              const Gap(8),
              Text(_error!, style: TextStyle(color: subCol), textAlign: TextAlign.center),
              const Gap(8),
              TextButton(onPressed: () => _load(_currentPath), child: const Text('Réessayer')),
            ]))
        : _displayEntries.isEmpty
          ? Center(child: Text(_searchQuery.isNotEmpty ? 'Aucun résultat' : 'Dossier vide',
                style: TextStyle(color: subCol)))
          : _gridView
            ? GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: SettingsService.notifier.value.gridColumns,
                    crossAxisSpacing: 6, mainAxisSpacing: 6,
                    childAspectRatio: 0.82),
                itemCount: _displayEntries.length,
                itemBuilder: (c, i) => _buildGridItem(
                    _displayEntries[i], accent, cardBg, border, textCol, subCol),
              )
            : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: _displayEntries.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: border),
              itemBuilder: (c, i) {
                final e = _displayEntries[i];
                final isSel = _selected.contains(e.path);
                return Material(color: isSel ? accent.withOpacity(0.10) : cardBg, child: InkWell(
                  onTap: () {
                    if (_selecting) { _toggleSelect(e); return; }
                    if (e.isDir) { _lastOpenedSubDir = e.path; _load(e.path); }
                    else _downloadOrView(context, e);
                  },
                  onLongPress: () => _toggleSelect(e),
                  onSecondaryTapDown: (details) =>
                      _showContextMenu(context, details.globalPosition, e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Row(children: [
                      if (_selecting) ...[
                        Icon(isSel ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 20, color: isSel ? accent : subCol),
                        const Gap(8),
                      ],
                      Icon(e.isDir ? Icons.folder_outlined : _fileIcon(e.name),
                          size: 20, color: e.isDir ? accent : subCol),
                      const Gap(8),
                      Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textCol))),
                      if (_metaText(e).isNotEmpty) ...[
                        const Gap(8),
                        Text(_metaText(e), style: TextStyle(fontSize: 11, color: subCol)),
                      ],
                      if (!_selecting)
                        Theme(
                          data: Theme.of(context).copyWith(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap))),
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.more_vert, size: 18, color: subCol),
                            onSelected: (v) => _onMenuAction(context, v, e),
                            itemBuilder: (_) => _menuItems(e),
                          ),
                        ),
                    ]),
                  ),
                ));
              },
            ),
    ),
      if (_dragging)
        Positioned.fill(child: IgnorePointer(child: Container(
          color: accent.withOpacity(0.15),
          child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent, width: 2)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.upload_file, color: accent),
              const SizedBox(width: 8),
              Text('Déposer pour envoyer ici',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
            ]),
          )),
        ))),
      ]),
    ),
    );
  }

  Future<void> _uploadDropped(List<XFile> files) async {
    if (files.isEmpty) return;
    final tasks = <({String local, String remote})>[];
    for (final f in files) {
      final path = f.path;
      if (FileSystemEntity.isDirectorySync(path)) {
        final baseName = p.basename(path);
        try {
          await for (final entity in Directory(path).list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final rel = p.relative(entity.path, from: path).replaceAll('\\', '/');
              final remote = '$_currentPath/$baseName/$rel'.replaceAll('//', '/');
              tasks.add((local: entity.path, remote: remote));
            }
          }
        } catch (_) {}
      } else {
        final name = p.basename(path);
        final remote = '$_currentPath/$name'.replaceAll('//', '/');
        tasks.add((local: path, remote: remote));
      }
    }
    if (tasks.isEmpty || !mounted) return;
    var okCount = 0, errCount = 0;
    for (final t in tasks) {
      try {
        if (mounted) {
          showTopSnack(context,
              'Envoi de ${p.basename(t.local)}… (${okCount + errCount + 1}/${tasks.length})');
        }
        await FtpService.upload(widget.connection, t.local, t.remote);
        okCount++;
      } catch (_) {
        errCount++;
      }
    }
    if (mounted) {
      showTopSnack(context,
          errCount == 0
              ? 'Envoyé : $okCount fichier${okCount > 1 ? 's' : ''}'
              : 'Envoyé : $okCount, échec : $errCount',
          backgroundColor: errCount == 0
              ? const Color(0xFF0F6E56) : const Color(0xFFE24B4A));
      _load(_currentPath);
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

  Widget _buildGridItem(FtpEntry e, Color accent, Color cardBg,
      Color border, Color textCol, Color subCol) {
    final isSel = _selected.contains(e.path);
    return GestureDetector(
      onTap: () {
        if (_selecting) { _toggleSelect(e); return; }
        if (e.isDir) { _lastOpenedSubDir = e.path; _load(e.path); }
        else _downloadOrView(context, e);
      },
      onLongPress: () => _toggleSelect(e),
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition, e),
      child: Container(
        decoration: BoxDecoration(
          color: isSel ? accent.withOpacity(0.18) : cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? accent : border, width: isSel ? 1.5 : 1)),
        child: Column(children: [
          Expanded(child: Center(child: Icon(
              e.isDir ? Icons.folder_rounded : _fileIcon(e.name),
              size: 44, color: e.isDir ? accent : subCol))),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.name, style: TextStyle(fontSize: 10, color: textCol),
                    overflow: TextOverflow.ellipsis, maxLines: 2)),
                if (isSel) Icon(Icons.check_circle, color: accent, size: 14),
              ]),
              if (_metaText(e).isNotEmpty)
                Text(_metaText(e), style: TextStyle(fontSize: 9, color: subCol),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
            ]),
          ),
        ]),
      ),
    );
  }

  void _toggleSelect(FtpEntry e) {
    setState(() {
      if (_selected.contains(e.path)) _selected.remove(e.path);
      else _selected.add(e.path);
    });
  }

  List<PopupMenuEntry<String>> _menuItems(FtpEntry e) => [
        if (!e.isDir) ...[
          const PopupMenuItem(value: 'open',
              child: ListTile(dense: true, leading: Icon(Icons.open_in_new),
                  title: Text('Ouvrir'))),
          const PopupMenuItem(value: 'download',
              child: ListTile(dense: true, leading: Icon(Icons.download_outlined),
                  title: Text('Télécharger vers…'))),
          const PopupMenuItem(value: 'edit',
              child: ListTile(dense: true, leading: Icon(Icons.edit_outlined),
                  title: Text('Éditer'))),
          if (p.extension(e.name).toLowerCase() == '.zip')
            const PopupMenuItem(value: 'extract',
                child: ListTile(dense: true, leading: Icon(Icons.unarchive_outlined),
                    title: Text('Extraire'))),
        ],
        const PopupMenuItem(value: 'rename',
            child: ListTile(dense: true, leading: Icon(Icons.drive_file_rename_outline),
                title: Text('Renommer'))),
        const PopupMenuItem(value: 'copy',
            child: ListTile(dense: true, leading: Icon(Icons.copy_outlined),
                title: Text('Copier'))),
        const PopupMenuItem(value: 'cut',
            child: ListTile(dense: true, leading: Icon(Icons.cut_outlined),
                title: Text('Couper'))),
        const PopupMenuItem(value: 'move',
            child: ListTile(dense: true, leading: Icon(Icons.drive_file_move_outline),
                title: Text('Déplacer'))),
        const PopupMenuItem(value: 'properties',
            child: ListTile(dense: true, leading: Icon(Icons.info_outline),
                title: Text('Propriétés'))),
        const PopupMenuItem(value: 'delete',
            child: ListTile(dense: true,
                leading: Icon(Icons.delete_outline, color: Color(0xFFE24B4A)),
                title: Text('Supprimer',
                    style: TextStyle(color: Color(0xFFE24B4A))))),
      ];

  void _onMenuAction(BuildContext context, String v, FtpEntry e) {
    if (v == 'rename')     _rename(context, e);
    if (v == 'move')       _move(context, e);
    if (v == 'properties') _showProperties(context, e);
    if (v == 'delete')     _delete(context, e);
    if (v == 'download')   _downloadFile(context, e);
    if (v == 'edit')       _editTextFile(context, e);
    if (v == 'open')       _openRemoteFile(context, e);
    if (v == 'extract')    _extractRemoteZip(context, e);
    if (v == 'copy')       _copy([e]);
    if (v == 'cut')        _cut([e]);
  }

  void _copy(List<FtpEntry> items) {
    UniversalClipboard.set(items.map((e) => ClipItem(
        kind: ClipKind.ftp, name: e.name, isDir: e.isDir,
        path: e.path, ftpConn: widget.connection)).toList(), cut: false);
    setState(() => _selected.clear());
    showTopSnack(context, '${items.length} élément(s) copié(s)');
  }

  void _cut(List<FtpEntry> items) {
    UniversalClipboard.set(items.map((e) => ClipItem(
        kind: ClipKind.ftp, name: e.name, isDir: e.isDir,
        path: e.path, ftpConn: widget.connection)).toList(), cut: true);
    setState(() => _selected.clear());
    showTopSnack(context, '${items.length} élément(s) coupé(s)');
  }

  Future<void> _paste(BuildContext context) async {
    if (UniversalClipboard.isEmpty) return;
    final ctrl = showTransferProgressDialog(context, title: 'Collage en cours…');
    final result = await pasteClipboardInto(
      destKind: ClipKind.ftp,
      destPath: _currentPath,
      destFtpConn: widget.connection,
      onProgress: (frac, label) => ctrl.update(frac, label: label),
    );
    if (context.mounted) closeTransferProgressDialog(context, ctrl);
    final parts = <String>[];
    if (result.ok > 0) parts.add('${result.ok} collé(s)');
    if (result.errors > 0) parts.add('${result.errors} échec(s)');
    if (result.skipped > 0) parts.add('${result.skipped} ignoré(s) (dossier non transférable ici)');
    if (mounted) {
      showTopSnack(context, parts.isEmpty ? 'Rien à coller' : parts.join(', '));
      _load(_currentPath);
    }
  }

  Future<void> _showProperties(BuildContext context, FtpEntry e) async {
    final rows = <PropertiesRow>[
      PropertiesRow('Type', e.isDir ? 'Dossier' : 'Fichier'),
      PropertiesRow('Chemin', e.path),
      if (!e.isDir) PropertiesRow('Taille', _fmtSize(e.size)),
      if (e.modified != null) PropertiesRow('Modifié', _fmtDateFull(e.modified!)),
    ];
    await showPropertiesDialog(context, name: e.name, isDir: e.isDir, rows: rows);
  }

  String _fmtDateFull(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Affiche le menu contextuel au clic droit (Windows/desktop) à la position du curseur.
  Future<void> _showContextMenu(
      BuildContext context, Offset globalPosition, FtpEntry e) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _menuItems(e),
    );
    if (selected != null && context.mounted) _onMenuAction(context, selected, e);
  }

  Future<void> _downloadOrView(BuildContext context, FtpEntry e) async {
    switch (classifyFile(e.name)) {
      case FileKind.text:
        _editTextFile(context, e);
      case FileKind.image:
        _viewRemoteImage(context, e);
      case FileKind.archive:
        _extractRemoteZip(context, e);
      case FileKind.apk:
      case FileKind.video:
      case FileKind.audio:
      case FileKind.other:
        _openRemoteFile(context, e);
    }
  }

  /// Télécharge une image distante dans un dossier temporaire puis l'affiche
  /// dans le visualiseur intégré.
  Future<void> _viewRemoteImage(BuildContext context, FtpEntry e) async {
    final ctrl = showTransferProgressDialog(context, title: 'Chargement de ${e.name}');
    try {
      final tmp = await getTemporaryDirectory();
      final local = p.join(tmp.path, 'pulsefile_open', e.name);
      await Directory(p.dirname(local)).create(recursive: true);
      await FtpService.download(widget.connection, e.path, localPath: local,
          onProgress: (percent, recv, total) => ctrl.update(percent / 100,
              label: '${_fmtSize(recv)} / ${total > 0 ? _fmtSize(total) : '?'}'));
      if (!context.mounted) return;
      closeTransferProgressDialog(context, ctrl);
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ImageViewerScreen(file: File(local))));
    } catch (err) {
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  /// Télécharge [e] dans un dossier temporaire puis l'ouvre avec l'app par
  /// défaut du système — comme un double-clic dans un explorateur natif.
  /// Pour un enregistrement explicite dans un dossier choisi, voir le menu
  /// ⋮ → "Télécharger vers…" (_downloadFile).
  Future<void> _openRemoteFile(BuildContext context, FtpEntry e) async {
    final ctrl = showTransferProgressDialog(context, title: 'Ouverture de ${e.name}');
    try {
      final tmp = await getTemporaryDirectory();
      final local = p.join(tmp.path, 'pulsefile_open', e.name);
      await Directory(p.dirname(local)).create(recursive: true);
      await FtpService.download(widget.connection, e.path, localPath: local,
          onProgress: (percent, recv, total) => ctrl.update(percent / 100,
              label: '${_fmtSize(recv)} / ${total > 0 ? _fmtSize(total) : '?'}'));
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      final ok = await openFileExternally(local);
      if (!ok && mounted) {
        showTopSnack(context, 'Aucune application associée pour ouvrir ce fichier',
            backgroundColor: const Color(0xFFE24B4A));
      }
    } catch (err) {
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  /// Télécharge une archive .zip distante dans un dossier temporaire, puis
  /// l'extrait sur place (mêmes outils que le mode local).
  Future<void> _extractRemoteZip(BuildContext context, FtpEntry e) async {
    final ctrl = showTransferProgressDialog(context, title: 'Téléchargement de ${e.name}');
    try {
      final tmp = await getTemporaryDirectory();
      final zipPath = p.join(tmp.path, 'pulsefile_extract', e.name);
      await Directory(p.dirname(zipPath)).create(recursive: true);
      await FtpService.download(widget.connection, e.path, localPath: zipPath,
          onProgress: (percent, recv, total) => ctrl.update(percent / 100,
              label: '${_fmtSize(recv)} / ${total > 0 ? _fmtSize(total) : '?'}'));

      ctrl.update(null, label: 'Extraction…');
      final destName = p.basenameWithoutExtension(zipPath);
      final destDir = p.join(p.dirname(zipPath), destName);
      await Directory(destDir).create(recursive: true);
      await extractFileToDisk(zipPath, destDir);

      if (!context.mounted) return;
      closeTransferProgressDialog(context, ctrl);
      final opened = await openFolderExternally(destDir);
      showTopSnack(context,
          opened ? 'Extrait et ouvert' : 'Extrait dans : $destDir',
          backgroundColor: const Color(0xFF0F6E56));
    } catch (err) {
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  Future<void> _downloadFile(BuildContext context, FtpEntry e) async {
    final defaultPath = widget.connection.defaultDownloadPath;
    final dirPath = (defaultPath != null && defaultPath.isNotEmpty)
        ? defaultPath
        : await Navigator.push<String>(context, MaterialPageRoute(
            builder: (_) => const LocalFolderPickerScreen()));
    if (dirPath == null || !context.mounted) return;

    final local = p.join(dirPath, e.name);
    final ctrl = showTransferProgressDialog(context, title: 'Téléchargement de ${e.name}');
    try {
      await FtpService.download(widget.connection, e.path, localPath: local,
          onProgress: (percent, recv, total) => ctrl.update(percent / 100,
              label: '${_fmtSize(recv)} / ${total > 0 ? _fmtSize(total) : '?'}'));
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      if (mounted) showTopSnack(context, 'Enregistré : $local',
          backgroundColor: const Color(0xFF0F6E56));
    } catch (err) {
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  Future<void> _editTextFile(BuildContext context, FtpEntry e) async {
    final ctrl = showTransferProgressDialog(context, title: 'Chargement de ${e.name}');
    String local;
    try {
      local = await FtpService.download(widget.connection, e.path,
          onProgress: (percent, recv, total) => ctrl.update(percent / 100,
              label: '${_fmtSize(recv)} / ${total > 0 ? _fmtSize(total) : '?'}'));
    } catch (err) {
      if (context.mounted) closeTransferProgressDialog(context, ctrl);
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
      return;
    }
    if (!context.mounted) return;
    String content;
    try {
      content = await File(local).readAsString();
    } on FileSystemException {
      closeTransferProgressDialog(context, ctrl);
      if (mounted) {
        showTopSnack(context, 'Ce fichier n\'est pas un fichier texte lisible',
            backgroundColor: const Color(0xFFE24B4A));
        await _downloadFile(context, e);
      }
      return;
    }
    closeTransferProgressDialog(context, ctrl);
    final edited = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => TextEditorScreen(filename: e.name, content: content)));
    if (edited == null || !context.mounted) return;
    await File(local).writeAsString(edited);
    final saveCtrl = showTransferProgressDialog(context, title: 'Envoi de ${e.name}');
    try {
      await FtpService.upload(widget.connection, local, e.path,
          onProgress: (percent, sent, total) => saveCtrl.update(percent / 100,
              label: '${_fmtSize(sent)} / ${total > 0 ? _fmtSize(total) : '?'}'));
      if (context.mounted) closeTransferProgressDialog(context, saveCtrl);
      if (mounted) showTopSnack(context, 'Fichier mis à jour',
          backgroundColor: const Color(0xFF0F6E56));
    } catch (err) {
      if (context.mounted) closeTransferProgressDialog(context, saveCtrl);
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  Future<void> _uploadFile(BuildContext context) async {
    final paths = await Navigator.push<List<String>>(context, MaterialPageRoute(
        builder: (_) => const LocalFilePickerScreen()));
    if (paths == null || paths.isEmpty) return;
    final files = paths.map((path) => (path: path, name: p.basename(path))).toList();
    if (files.isEmpty) return;
    if (!context.mounted) return;
    final ctrl = showTransferProgressDialog(context,
        title: 'Envoi de ${files.length} fichier${files.length > 1 ? 's' : ''}');
    var okCount = 0, errCount = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final remotePath = '$_currentPath/${f.name}'.replaceAll('//', '/');
      ctrl.update(0, label: '${f.name} (${i + 1}/${files.length})');
      try {
        await FtpService.upload(widget.connection, f.path, remotePath,
            onProgress: (percent, sent, total) => ctrl.update(percent / 100,
                label: '${f.name} (${i + 1}/${files.length}) — ${_fmtSize(sent)} / ${total > 0 ? _fmtSize(total) : '?'}'));
        okCount++;
      } catch (_) {
        errCount++;
      }
    }
    if (context.mounted) closeTransferProgressDialog(context, ctrl);
    if (mounted) {
      showTopSnack(context,
          errCount == 0
              ? 'Envoyé : $okCount fichier${okCount > 1 ? 's' : ''}'
              : 'Envoyé : $okCount, échec : $errCount',
          backgroundColor: errCount == 0
              ? const Color(0xFF0F6E56) : const Color(0xFFE24B4A));
      _load(_currentPath);
    }
  }

  Future<void> _downloadSelected(BuildContext context) async {
    final targets = _entries.where((e) => _selected.contains(e.path)).toList();
    if (targets.isEmpty) return;
    final defaultPath = widget.connection.defaultDownloadPath;
    final dirPath = (defaultPath != null && defaultPath.isNotEmpty)
        ? defaultPath
        : await Navigator.push<String>(context, MaterialPageRoute(
            builder: (_) => const LocalFolderPickerScreen()));
    if (dirPath == null || !context.mounted) return;
    final downloadable = targets.where((e) => !e.isDir).toList();
    final skipCount = targets.length - downloadable.length;
    final ctrl = showTransferProgressDialog(context,
        title: 'Téléchargement de ${downloadable.length} fichier${downloadable.length > 1 ? 's' : ''}');
    var okCount = 0, errCount = 0;
    for (var i = 0; i < downloadable.length; i++) {
      final e = downloadable[i];
      final local = p.join(dirPath, e.name);
      ctrl.update(0, label: '${e.name} (${i + 1}/${downloadable.length})');
      try {
        await FtpService.download(widget.connection, e.path, localPath: local,
            onProgress: (percent, recv, total) => ctrl.update(percent / 100,
                label: '${e.name} (${i + 1}/${downloadable.length}) — ${_fmtSize(recv)} / ${total > 0 ? _fmtSize(total) : '?'}'));
        okCount++;
      } catch (_) {
        errCount++;
      }
    }
    if (context.mounted) closeTransferProgressDialog(context, ctrl);
    if (mounted) {
      final msg = StringBuffer('Téléchargé : $okCount fichier${okCount > 1 ? 's' : ''}');
      if (errCount  > 0) msg.write(', échec : $errCount');
      if (skipCount > 0) msg.write(', dossier${skipCount > 1 ? 's' : ''} ignoré${skipCount > 1 ? 's' : ''} : $skipCount');
      showTopSnack(context, msg.toString(),
          backgroundColor: errCount == 0
              ? const Color(0xFF0F6E56) : const Color(0xFFE24B4A));
      setState(() => _selected.clear());
    }
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final targets = _entries.where((e) => _selected.contains(e.path)).toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Supprimer ${targets.length} élément${targets.length > 1 ? 's' : ''} ?'),
        content: const Text('Cette action est définitive (fichiers et dossiers sélectionnés, '
            'y compris leur contenu).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE24B4A)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final targetPaths = targets.map((e) => e.path).toSet();
    setState(() {
      _entries = _entries.where((e) => !targetPaths.contains(e.path)).toList();
      _selected.clear();
    });
    var cancelled = false;
    final timer = Timer(const Duration(seconds: 4), () async {
      if (cancelled) return;
      for (final e in targets) {
        try { await FtpService.delete(widget.connection, e.path, isDir: e.isDir); } catch (_) {}
      }
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${targets.length} élément${targets.length > 1 ? 's' : ''} supprimé${targets.length > 1 ? 's' : ''}'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'Annuler', onPressed: () {
        cancelled = true;
        timer.cancel();
        _load(_currentPath);
      }),
    ));
  }

  Future<void> _rename(BuildContext context, FtpEntry e) async {
    final ctrl = TextEditingController(text: e.name);
    final ok   = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Renommer'),
        content: TextField(controller: ctrl,
            decoration: const InputDecoration(labelText: 'Nouveau nom')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Renommer')),
        ],
      ),
    );
    if (ok != true || ctrl.text.isEmpty) return;
    final newPath = '${e.path.substring(0, e.path.lastIndexOf('/'))}/${ctrl.text}';
    try {
      await FtpService.rename(widget.connection, e.path, newPath);
      _load(_currentPath);
    } catch (err) {
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  Future<void> _move(BuildContext context, FtpEntry e) async {
    final destFolder = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => RemoteFolderPickerScreen(
        title: 'Déplacer « ${e.name} » vers…',
        initialPath: _currentPath,
        listFolder: (path) async {
          final entries = await FtpService.list(widget.connection, path);
          return entries.where((x) => x.isDir && x.path != e.path)
              .map((x) => RemoteFolderEntry(name: x.name, path: x.path)).toList();
        },
        parentOf: (path) {
          final parts = path.split('/').where((s) => s.isNotEmpty).toList();
          if (parts.isEmpty) return '/';
          parts.removeLast();
          return parts.isEmpty ? '/' : '/${parts.join('/')}';
        },
        canGoUp: (path) => path != '/' && path.isNotEmpty,
      ),
    ));
    if (destFolder == null || !context.mounted) return;
    RecentFoldersService.touch(RecentFolderKind.ftp, destFolder,
        '${widget.connection.name} — $destFolder', connectionId: widget.connection.id);
    final newPath = '$destFolder/${e.name}'.replaceAll('//', '/');
    if (newPath == e.path) return;
    try {
      await FtpService.move(widget.connection, e.path, newPath);
      _load(_currentPath);
    } catch (err) {
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  Future<void> _delete(BuildContext context, FtpEntry e) async {
    String message = e.isDir
        ? 'Ce dossier et son contenu seront supprimés.'
        : 'Ce fichier sera supprimé définitivement.';
    if (e.isDir) {
      try {
        final stats = await FtpService.dirStats(widget.connection, e.path);
        final parts = <String>[];
        if (stats.dirs  > 0) parts.add('${stats.dirs} dossier${stats.dirs  > 1 ? 's' : ''}');
        if (stats.files > 0) parts.add('${stats.files} fichier${stats.files > 1 ? 's' : ''}');
        message = parts.isEmpty
            ? 'Ce dossier est vide.'
            : 'Ce dossier contient ${parts.join(' et ')}, qui seront supprimés définitivement.';
      } catch (_) {
        // Comptage échoué : on garde le message générique, pas bloquant.
      }
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Supprimer ${e.name} ?'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE24B4A)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _entries = _entries.where((x) => x.path != e.path).toList());
    var cancelled = false;
    final timer = Timer(const Duration(seconds: 4), () async {
      if (cancelled) return;
      try { await FtpService.delete(widget.connection, e.path, isDir: e.isDir); } catch (_) {}
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('« ${e.name} » supprimé'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(label: 'Annuler', onPressed: () {
        cancelled = true;
        timer.cancel();
        _load(_currentPath);
      }),
    ));
  }

  Future<void> _mkdir(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok   = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouveau dossier'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(labelText: 'Nom du dossier'),
            onSubmitted: (v) => Navigator.pop(c, true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true || ctrl.text.isEmpty) return;
    final path = '$_currentPath/${ctrl.text}'.replaceAll('//', '/');
    try {
      await FtpService.mkdir(widget.connection, path);
      _load(_currentPath);
    } catch (err) {
      if (mounted) showTopSnack(context, 'Erreur : $err',
          backgroundColor: const Color(0xFFE24B4A));
    }
  }

  IconData _fileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.pdf':                        return Icons.picture_as_pdf_outlined;
      case '.jpg': case '.jpeg':
      case '.png': case '.gif':           return Icons.image_outlined;
      case '.mp4': case '.mov':           return Icons.movie_outlined;
      case '.mp3': case '.wav':           return Icons.audiotrack_outlined;
      case '.zip': case '.rar':           return Icons.folder_zip_outlined;
      case '.txt': case '.md':            return Icons.article_outlined;
      case '.json': case '.xml':
      case '.yaml': case '.yml':          return Icons.code_outlined;
      default:                            return Icons.insert_drive_file_outlined;
    }
  }

  String _metaText(FtpEntry e) {
    final parts = <String>[];
    final date = _fmtDate(e.modified);
    if (date.isNotEmpty) parts.add(date);
    if (!e.isDir) parts.add(_fmtSize(e.size));
    return parts.join('  ·  ');
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
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

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  }
}
