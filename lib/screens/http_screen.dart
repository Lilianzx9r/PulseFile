// lib/screens/http_screen.dart
//
// Gestionnaire de connexions PHP/HTTP pour PulseIt.
// Interface identique aux connexions FTP : liste, créer, modifier, supprimer, tester.
//
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../services/http_service.dart';
import '../services/last_access_service.dart';
import '../services/favorites_service.dart';
import 'http_explorer_screen.dart';
import '../theme/pf_colors.dart';
import '../utils/top_snack.dart';
import '../widgets/local_folder_picker.dart';

// ── Liste des connexions HTTP ─────────────────────────────────────────────────

class HttpScreen extends StatefulWidget {
  const HttpScreen({super.key});
  @override State<HttpScreen> createState() => _HttpScreenState();
}

class _HttpScreenState extends State<HttpScreen> {
  List<HttpConnection> _connections = [];
  List<FavoriteEntry> _favorites = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await HttpService.listConnections();
    final favs = await FavoritesService.list();
    if (mounted) setState(() {
      _connections = list;
      _favorites = favs.where((f) => f.kind == FavoriteKind.http).toList();
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
        title: const Text('Connexions PHP/HTTP',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: accent),
            tooltip: 'Nouvelle connexion',
            onPressed: () => _edit(context, null),
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _connections.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.language_outlined, size: 48, color: subCol),
              const Gap(12),
              Text('Aucune connexion PHP/HTTP', style: TextStyle(color: subCol)),
              const Gap(4),
              Text('Nécessite un script pulsia_sync.php\nsur votre serveur web',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: subCol)),
              const Gap(8),
              TextButton.icon(
                onPressed: () => _edit(context, null),
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
                            FavoritesService.remove(FavoriteKind.http, fav.connectionId, fav.path);
                            _load();
                            return;
                          }
                          if (conn.first.id != null) {
                            LastAccessService.save(LastAccessType.http, conn.first.id!);
                          }
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => HttpExplorerScreen(
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
                      if (conn.id != null) LastAccessService.save(LastAccessType.http, conn.id!);
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => HttpExplorerScreen(connection: conn)));
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
                          child: Icon(Icons.language_outlined, size: 20, color: accent),
                        ),
                        const Gap(12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(conn.name, style: TextStyle(fontWeight: FontWeight.w600,
                              fontSize: 14, color: textCol)),
                          Text(conn.url, style: TextStyle(fontSize: 11, color: subCol),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (conn.hasBasicAuth)
                            Text('Basic Auth : ${conn.basicUser}',
                                style: TextStyle(fontSize: 11, color: subCol)),
                        ])),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: subCol),
                          onPressed: () => _edit(context, conn),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: Color(0xFFE24B4A)),
                          onPressed: () => _delete(context, conn),
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

  Future<void> _edit(BuildContext context, HttpConnection? existing) async {
    final result = await showModalBottomSheet<HttpConnection>(
      context: context, isScrollControlled: true,
      builder: (_) => _HttpEditor(existing: existing),
    );
    if (result != null) {
      await HttpService.saveConnection(result);
      _load();
    }
  }

  Future<void> _delete(BuildContext context, HttpConnection conn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cette connexion ?'),
        content: Text('${conn.name} sera supprimée.'),
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
      await HttpService.deleteConnection(conn.id!);
      final last = await LastAccessService.load();
      if (last != null && last.$1 == LastAccessType.http && last.$2 == conn.id) {
        await LastAccessService.clear();
      }
      _load();
    }
  }
}

// ── Éditeur de connexion ──────────────────────────────────────────────────────

class _HttpEditor extends StatefulWidget {
  final HttpConnection? existing;
  const _HttpEditor({this.existing});
  @override State<_HttpEditor> createState() => _HttpEditorState();
}

class _HttpEditorState extends State<_HttpEditor> {
  final _name      = TextEditingController();
  final _url       = TextEditingController();
  final _token     = TextEditingController();
  final _basicUser = TextEditingController();
  final _basicPass = TextEditingController();
  bool _obscureToken = true;
  bool _obscurePass  = true;
  bool _useBasic     = false;
  bool _testing      = false;
  String? _downloadPath;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final c = widget.existing!;
      _name.text  = c.name;  _url.text   = c.url;
      _token.text = c.token; _basicUser.text = c.basicUser;
      _basicPass.text = c.basicPassword;
      _useBasic = c.hasBasicAuth;
      _downloadPath = c.defaultDownloadPath;
    }
  }

  Future<void> _pickDownloadPath() async {
    final picked = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => LocalFolderPickerScreen(initialPath: _downloadPath)));
    if (picked != null) setState(() => _downloadPath = picked);
  }

  HttpConnection get _conn => HttpConnection(
    id:            widget.existing?.id,
    name:          _name.text.trim(),
    url:           _url.text.trim(),
    token:         _token.text.trim(),
    basicUser:     _useBasic ? _basicUser.text.trim() : '',
    basicPassword: _useBasic ? _basicPass.text : '',
    defaultDownloadPath: _downloadPath,
  );

  @override
  Widget build(BuildContext context) {
    final accent = PfColors.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1C1C1A) : Colors.white;
    final subCol = const Color(0xFF888780);

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
              decoration: BoxDecoration(color: subCol.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2))),
          Text(widget.existing == null ? 'Nouvelle connexion PHP' : 'Modifier la connexion',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Gap(4),
          Text('Nécessite le script pulsia_sync.php côté serveur',
              style: TextStyle(fontSize: 11, color: subCol)),
          const Gap(16),

          // Nom
          _field(_name, 'Nom', Icons.label_outlined),
          const Gap(10),

          // URL
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.language_outlined),
              labelText: 'URL du script',
              hintText: 'https://monserveur.com/pulseit/pulseit_sync.php',
              border: OutlineInputBorder(),
            ),
          ),

          // Avertissement HTTP
          if (_url.text.startsWith('http://') && !_url.text.startsWith('https://')) ...[
            const Gap(6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
                const Gap(6),
                Expanded(child: Text(
                  'URL http:// — certains hébergeurs redirigent vers une page pub. '
                  'Préférez https:// si disponible.',
                  style: const TextStyle(fontSize: 11, color: Colors.orange))),
              ]),
            ),
          ],
          const Gap(10),

          // Token
          TextField(
            controller: _token, obscureText: _obscureToken,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.key_outlined),
              labelText: 'Token secret',
              hintText: 'Même valeur que SECRET_TOKEN dans le PHP',
              suffixIcon: IconButton(
                icon: Icon(_obscureToken
                    ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const Gap(14),

          // Auth Basic
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252523) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark
                  ? const Color(0xFF3C3C3A) : Colors.grey.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.lock_person_outlined, size: 16, color: subCol),
                const Gap(6),
                const Text('Auth HTTP Basic', style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500)),
                const Spacer(),
                Switch(value: _useBasic, activeColor: accent,
                    onChanged: (v) => setState(() => _useBasic = v)),
              ]),
              Text('Requis pour Free.fr clouddisk, etc.',
                  style: TextStyle(fontSize: 11, color: subCol)),
              if (_useBasic) ...[
                const Gap(10),
                _field(_basicUser, 'Login HTTP', Icons.person_outlined),
                const Gap(8),
                TextField(
                  controller: _basicPass, obscureText: _obscurePass,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.key_outlined),
                    labelText: 'Mot de passe HTTP',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass
                          ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    border: const OutlineInputBorder(), isDense: true,
                  ),
                ),
              ],
            ]),
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
            Expanded(child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_find_outlined, size: 18),
              label: const Text('Tester'),
            )),
            const Gap(10),
            Expanded(child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: accent),
              child: const Text('Enregistrer'),
            )),
          ]),
        ])),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) =>
    TextField(controller: ctrl,
        decoration: InputDecoration(prefixIcon: Icon(icon),
            labelText: label, border: const OutlineInputBorder(), isDense: true));

  Future<void> _test() async {
    if (_url.text.trim().isEmpty) {
      showTopSnack(context, 'URL requise', backgroundColor: const Color(0xFFE24B4A));
      return;
    }
    setState(() => _testing = true);
    final ok = await HttpService.testConnection(_conn);
    if (mounted) {
      setState(() => _testing = false);
      showTopSnack(context,
          ok ? 'Connexion réussie !' : 'Connexion échouée — vérifiez URL et token',
          backgroundColor: ok ? const Color(0xFF0F6E56) : const Color(0xFFE24B4A));
    }
  }

  void _save() {
    if (_name.text.isEmpty || _url.text.isEmpty) {
      showTopSnack(context, 'Nom et URL requis',
          backgroundColor: const Color(0xFFE24B4A));
      return;
    }
    Navigator.pop(context, _conn);
  }
}
