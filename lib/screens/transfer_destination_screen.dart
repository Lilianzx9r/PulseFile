import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/ftp_service.dart';
import '../services/http_service.dart';
import '../services/universal_clipboard.dart';
import '../theme/pf_colors.dart';
import '../widgets/local_folder_picker.dart';
import '../widgets/remote_folder_picker.dart';
import '../widgets/transfer_progress_dialog.dart';

/// Destination commune pour les transferts depuis PulseFile.
/// Utilisé par les opérations locales « Copier vers… » et « Déplacer vers… ».
class TransferDestinationScreen extends StatefulWidget {
  final String title;
  final String initialLocalPath;

  const TransferDestinationScreen({
    super.key,
    required this.title,
    required this.initialLocalPath,
  });

  @override
  State<TransferDestinationScreen> createState() =>
      _TransferDestinationScreenState();
}

class _TransferDestinationScreenState
    extends State<TransferDestinationScreen> {
  List<FtpConnection> _ftp = [];
  List<HttpConnection> _http = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ftp = await FtpService.listConnections();
    final http = await HttpService.listConnections();
    if (mounted) {
      setState(() {
        _ftp = ftp;
        _http = http;
        _loading = false;
      });
    }
  }

  Future<void> _chooseLocal() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalFolderPickerScreen(
          initialPath: widget.initialLocalPath,
        ),
      ),
    );
    if (path == null || !mounted) return;
    await _paste(
      destKind: ClipKind.local,
      destPath: path,
      title: 'Copie vers le stockage local',
    );
  }

  Future<void> _chooseFtp(FtpConnection conn) async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteFolderPickerScreen(
          title: '${widget.title} dans…',
          initialPath: conn.initialPath,
          listFolder: (path) async {
            final entries = await FtpService.list(conn, path);
            return entries
                .where((e) => e.isDir)
                .map((e) => RemoteFolderEntry(name: e.name, path: e.path))
                .toList();
          },
          parentOf: (path) {
            final parts =
                path.split('/').where((s) => s.isNotEmpty).toList();
            if (parts.isEmpty) return '/';
            parts.removeLast();
            return parts.isEmpty ? '/' : '/${parts.join('/')}';
          },
          canGoUp: (path) => path != '/' && path.isNotEmpty,
        ),
      ),
    );
    if (path == null || !mounted) return;
    await _paste(
      destKind: ClipKind.ftp,
      destPath: path,
      destFtpConn: conn,
      title: 'Transfert vers ${conn.name}',
    );
  }

  Future<void> _chooseHttp(HttpConnection conn) async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteFolderPickerScreen(
          title: '${widget.title} dans…',
          initialPath: '.',
          listFolder: (path) async {
            final entries = await HttpService.list(conn, subdir: path);
            return entries
                .where((e) => e.isDir)
                .map((e) =>
                    RemoteFolderEntry(name: e.name, path: e.remotePath))
                .toList();
          },
          parentOf: (path) {
            final parts = path
                .split('/')
                .where((s) => s.isNotEmpty && s != '.')
                .toList();
            if (parts.isEmpty) return '.';
            parts.removeLast();
            return parts.isEmpty ? '.' : parts.join('/');
          },
          canGoUp: (path) => path != '.' && path.isNotEmpty,
        ),
      ),
    );
    if (path == null || !mounted) return;
    await _paste(
      destKind: ClipKind.http,
      destPath: path,
      destHttpConn: conn,
      title: 'Transfert vers ${conn.name}',
    );
  }

  Future<void> _paste({
    required ClipKind destKind,
    required String destPath,
    FtpConnection? destFtpConn,
    HttpConnection? destHttpConn,
    required String title,
  }) async {
    if (UniversalClipboard.isEmpty || !mounted) return;
    final ctrl = showTransferProgressDialog(context, title: title);
    final result = await pasteClipboardInto(
      destKind: destKind,
      destPath: destPath,
      destFtpConn: destFtpConn,
      destHttpConn: destHttpConn,
      onProgress: (fraction, label) => ctrl.update(fraction, label: label),
    );
    if (mounted) await closeTransferProgressDialog(context, ctrl);

    if (!mounted) return;
    final parts = <String>[];
    if (result.ok > 0) parts.add('${result.ok} transféré(s)');
    if (result.errors > 0) parts.add('${result.errors} échec(s)');
    if (result.skipped > 0) parts.add('${result.skipped} ignoré(s)');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.isEmpty ? 'Rien à transférer' : parts.join(', '))),
    );
    if (result.errors == 0 && result.ok > 0) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = PfColors.bg(isDark);
    final card = PfColors.card(isDark);
    final border = PfColors.border(isDark);
    final text = PfColors.text(isDark);
    final sub = PfColors.subtext;
    final accent = PfColors.accent;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _section('Local', sub),
                _tile(card, border, text, sub, Icons.folder_outlined, accent,
                    'Stockage local', widget.initialLocalPath, _chooseLocal),
                if (_ftp.isNotEmpty) ...[
                  _section('FTP', sub),
                  for (final conn in _ftp)
                    _tile(card, border, text, sub, Icons.dns_outlined, accent,
                        conn.name, '${conn.host}:${conn.port}',
                        () => _chooseFtp(conn)),
                ],
                if (_http.isNotEmpty) ...[
                  _section('HTTP', sub),
                  for (final conn in _http)
                    _tile(card, border, text, sub, Icons.cloud_outlined, accent,
                        conn.name, conn.url, () => _chooseHttp(conn)),
                ],
              ],
            ),
    );
  }

  Widget _section(String label, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _tile(Color card, Color border, Color text, Color sub, IconData icon,
      Color iconColor, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(children: [
              Icon(icon, color: iconColor, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: text)),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11, color: sub),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: sub),
            ]),
          ),
        ),
      ),
    );
  }
}
