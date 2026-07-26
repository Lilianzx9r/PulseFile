// lib/widgets/swipe_recents_appbar.dart
//
// Enveloppe une AppBar pour détecter un balayage vertical (vers le bas) et
// afficher la liste des 20 derniers dossiers utilisés, tous modes confondus.
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/recent_folders_service.dart';
import '../services/ftp_service.dart';
import '../services/http_service.dart';
import '../theme/pf_colors.dart';
import '../screens/file_manager_screen.dart';
import '../screens/ftp_screen.dart';
import '../screens/http_explorer_screen.dart';

const _recentsFilesChannel = MethodChannel('com.pulsefile/files');

class SwipeRecentsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final PreferredSizeWidget child;
  const SwipeRecentsAppBar({super.key, required this.child});

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 200) {
          _showRecents(context);
        }
      },
      child: child,
    );
  }

  Future<void> _showRecents(BuildContext context) async {
    final recents = await RecentFoldersService.list();
    if (!context.mounted) return;

    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = PfColors.bg(isDark);
    final textCol = PfColors.text(isDark);
    final subCol  = PfColors.subtext;
    final accent  = PfColors.accent;

    await showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Icon(Icons.history, size: 18, color: subCol),
              const SizedBox(width: 8),
              Text('Dossiers récents', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: textCol)),
            ]),
          ),
          Flexible(
            child: recents.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Aucun dossier récent pour l\'instant',
                        style: TextStyle(color: subCol), textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: recents.length,
                    itemBuilder: (c, i) {
                      final r = recents[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(_iconFor(r.kind), color: accent, size: 20),
                        title: Text(r.label, style: TextStyle(fontSize: 13, color: textCol),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(r.path, style: TextStyle(fontSize: 11, color: subCol),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _openRecent(context, r);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  IconData _iconFor(RecentFolderKind kind) => switch (kind) {
        RecentFolderKind.local => Icons.smartphone,
        RecentFolderKind.ftp   => Icons.dns_outlined,
        RecentFolderKind.http  => Icons.cloud_outlined,
      };

  Future<void> _openRecent(BuildContext context, RecentFolder r) async {
    if (r.kind == RecentFolderKind.local) {
      if (!Directory(r.path).existsSync()) {
        _notFound(context);
        return;
      }
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => FileBrowserScreen(
              root: Directory(r.path), title: r.label, ch: _recentsFilesChannel)));
    } else if (r.kind == RecentFolderKind.ftp) {
      final conns = await FtpService.listConnections();
      final conn = conns.where((c) => c.id == r.connectionId).toList();
      if (conn.isEmpty) { _notFound(context); return; }
      if (!context.mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => FtpExplorerScreen(connection: conn.first, initialPath: r.path)));
    } else {
      final conns = await HttpService.listConnections();
      final conn = conns.where((c) => c.id == r.connectionId).toList();
      if (conn.isEmpty) { _notFound(context); return; }
      if (!context.mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => HttpExplorerScreen(connection: conn.first, initialPath: r.path)));
    }
  }

  void _notFound(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce dossier ou cette connexion n\'existe plus')));
  }
}
