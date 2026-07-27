// lib/screens/save_destination_screen.dart
//
// Écran racine affiché quand une app tierce demande à PulseFile d'enregistrer
// un ou plusieurs fichiers quelque part — soit via "Enregistrer sous"
// (ACTION_SAVE_TO, ex. PulseIt, un seul fichier), soit via le menu Partager
// système standard (ACTION_SEND/ACTION_SEND_MULTIPLE, un ou plusieurs
// fichiers, depuis n'importe quelle app Android). Remplace l'app normale
// tant que la demande n'est pas traitée (voir main.dart).
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/pending_save_service.dart';
import '../services/ftp_service.dart';
import '../services/http_service.dart';
import '../theme/pf_colors.dart';
import '../utils/quick_paths.dart';
import '../widgets/local_folder_picker.dart';
import '../widgets/remote_folder_picker.dart';
import '../widgets/transfer_progress_dialog.dart';

class SaveDestinationApp extends StatelessWidget {
  final List<PendingSaveRequest> requests;
  const SaveDestinationApp({super.key, required this.requests});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D7CF4)),
        useMaterial3: true,
      ),
      home: SaveDestinationScreen(requests: requests),
    );
  }
}

class SaveDestinationScreen extends StatefulWidget {
  final List<PendingSaveRequest> requests;
  const SaveDestinationScreen({super.key, required this.requests});

  @override
  State<SaveDestinationScreen> createState() => _SaveDestinationScreenState();
}

class _SaveDestinationScreenState extends State<SaveDestinationScreen> {
  List<QuickPath> _volumes = [];
  List<FtpConnection> _ftpList = [];
  List<HttpConnection> _httpList = [];
  bool _loading = true;

  String get _titleText => widget.requests.length == 1
      ? 'Enregistrer « ${widget.requests.first.fileName} »'
      : 'Enregistrer ${widget.requests.length} fichiers';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final volumes  = Platform.isAndroid ? await resolveVolumes() : <QuickPath>[];
    final ftpList  = await FtpService.listConnections();
    final httpList = await HttpService.listConnections();
    if (mounted) setState(() {
      _volumes = volumes; _ftpList = ftpList; _httpList = httpList; _loading = false;
    });
  }

  Future<void> _cancel() async {
    await returnSaveResult(ok: false);
  }

  Future<void> _saveToLocal(QuickPath volume) async {
    final destDir = await Navigator.push<String>(context, MaterialPageRoute(
        builder: (_) => LocalFolderPickerScreen(initialPath: volume.path)));
    if (destDir == null || !mounted) return;
    final ctrl = showTransferProgressDialog(context, title: _titleText);
    var lastPath = '';
    var okCount = 0, errCount = 0;
    for (var i = 0; i < widget.requests.length; i++) {
      final req = widget.requests[i];
      ctrl.update(widget.requests.length == 1 ? null : i / widget.requests.length,
          label: '${req.fileName} (${i + 1}/${widget.requests.length})');
      try {
        final dest = p.join(destDir, req.fileName);
        await File(req.localPath).copy(dest);
        lastPath = dest;
        okCount++;
      } catch (_) {
        errCount++;
      }
    }
    if (mounted) await closeTransferProgressDialog(context, ctrl);
    if (errCount == 0) {
      await returnSaveResult(ok: true, savedPath: lastPath);
    } else if (mounted) {
      _showError('$okCount enregistré(s), $errCount échec(s)');
    }
  }

  Future<void> _saveToFtp(FtpConnection conn) async {
    final destDir = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => RemoteFolderPickerScreen(
        title: '$_titleText dans…',
        initialPath: conn.initialPath,
        listFolder: (path) async {
          final entries = await FtpService.list(conn, path);
          return entries.where((e) => e.isDir)
              .map((e) => RemoteFolderEntry(name: e.name, path: e.path)).toList();
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
    if (destDir == null || !mounted) return;
    final ctrl = showTransferProgressDialog(context, title: _titleText);
    var lastPath = '';
    var okCount = 0, errCount = 0;
    for (var i = 0; i < widget.requests.length; i++) {
      final req = widget.requests[i];
      try {
        final remotePath = '$destDir/${req.fileName}'.replaceAll('//', '/');
        await FtpService.upload(conn, req.localPath, remotePath,
            onProgress: (percent, sent, total) => ctrl.update(percent / 100,
                label: '${req.fileName} (${i + 1}/${widget.requests.length})'));
        lastPath = remotePath;
        okCount++;
      } catch (_) {
        errCount++;
      }
    }
    if (mounted) await closeTransferProgressDialog(context, ctrl);
    if (errCount == 0) {
      await returnSaveResult(ok: true, savedPath: lastPath);
    } else if (mounted) {
      _showError('$okCount envoyé(s), $errCount échec(s)');
    }
  }

  Future<void> _saveToHttp(HttpConnection conn) async {
    final destDir = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => RemoteFolderPickerScreen(
        title: '$_titleText dans…',
        initialPath: '.',
        listFolder: (path) async {
          final entries = await HttpService.list(conn, subdir: path);
          return entries.where((e) => e.isDir)
              .map((e) => RemoteFolderEntry(name: e.name, path: e.remotePath)).toList();
        },
        parentOf: (path) {
          final parts = path.split('/').where((s) => s.isNotEmpty && s != '.').toList();
          if (parts.isEmpty) return '.';
          parts.removeLast();
          return parts.isEmpty ? '.' : parts.join('/');
        },
        canGoUp: (path) => path != '.' && path.isNotEmpty,
      ),
    ));
    if (destDir == null || !mounted) return;
    final ctrl = showTransferProgressDialog(context, title: _titleText);
    var lastPath = '';
    var okCount = 0, errCount = 0;
    for (var i = 0; i < widget.requests.length; i++) {
      final req = widget.requests[i];
      try {
        final remotePath = (destDir == '.' ? req.fileName : '$destDir/${req.fileName}')
            .replaceAll('//', '/');
        await HttpService.upload(conn, req.localPath, remotePath,
            onProgress: (sent, total) => ctrl.update(progressFraction(sent, total),
                label: '${req.fileName} (${i + 1}/${widget.requests.length})'));
        lastPath = remotePath;
        okCount++;
      } catch (_) {
        errCount++;
      }
    }
    if (mounted) await closeTransferProgressDialog(context, ctrl);
    if (errCount == 0) {
      await returnSaveResult(ok: true, savedPath: lastPath);
    } else if (mounted) {
      _showError('$okCount envoyé(s), $errCount échec(s)');
    }
  }

  void _showError(Object err) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $err'), backgroundColor: const Color(0xFFE24B4A)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = PfColors.bg(isDark);
    final cardBg  = PfColors.card(isDark);
    final border  = PfColors.border(isDark);
    final textCol = PfColors.text(isDark);
    final subCol  = PfColors.subtext;
    final accent  = PfColors.accent;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _cancel();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          automaticallyImplyLeading: false,
          title: Text(_titleText,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(onPressed: _cancel, child: const Text('Annuler')),
          ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (widget.requests.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        widget.requests.map((r) => r.fileName).join(', '),
                        style: TextStyle(fontSize: 11, color: subCol),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                if (_volumes.isNotEmpty) ...[
                  _section('Local', subCol),
                  for (final v in _volumes)
                    _tile(cardBg, border, textCol, subCol,
                        icon: Icons.smartphone, iconColor: accent,
                        title: v.label, subtitle: v.path,
                        onTap: () => _saveToLocal(v)),
                  const SizedBox(height: 8),
                ],
                if (_ftpList.isNotEmpty) ...[
                  _section('FTP', subCol),
                  for (final c in _ftpList)
                    _tile(cardBg, border, textCol, subCol,
                        icon: Icons.dns_outlined, iconColor: accent,
                        title: c.name, subtitle: '${c.host}:${c.port}',
                        onTap: () => _saveToFtp(c)),
                  const SizedBox(height: 8),
                ],
                if (_httpList.isNotEmpty) ...[
                  _section('HTTP', subCol),
                  for (final c in _httpList)
                    _tile(cardBg, border, textCol, subCol,
                        icon: Icons.cloud_outlined, iconColor: accent,
                        title: c.name, subtitle: c.url,
                        onTap: () => _saveToHttp(c)),
                ],
                if (_volumes.isEmpty && _ftpList.isEmpty && _httpList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Aucune destination disponible — ajoute une connexion FTP ou HTTP dans PulseFile.',
                        style: TextStyle(color: subCol), textAlign: TextAlign.center),
                  ),
              ],
            ),
      ),
    );
  }

  Widget _section(String label, Color subCol) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: subCol)),
      );

  Widget _tile(Color cardBg, Color border, Color textCol, Color subCol, {
    required IconData icon, required Color iconColor,
    required String title, required String subtitle, required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border)),
            child: Row(children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textCol)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: subCol),
                    overflow: TextOverflow.ellipsis),
              ])),
              Icon(Icons.chevron_right, color: subCol),
            ]),
          ),
        ),
      ),
    );
  }
}
