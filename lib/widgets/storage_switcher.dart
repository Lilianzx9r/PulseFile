// lib/widgets/storage_switcher.dart
//
// Bouton d'en-tête permettant de changer de source (local, FTP, HTTP) sans
// repasser par l'écran d'accueil à onglets — affiché dans l'AppBar des trois
// explorateurs pour un accès identique quelle que soit la source actuelle.
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ftp_service.dart';
import '../services/http_service.dart';
import '../theme/pf_colors.dart';
import '../utils/quick_paths.dart';
import '../screens/file_manager_screen.dart';
import '../screens/ftp_screen.dart';
import '../screens/http_explorer_screen.dart';

enum StorageKind { local, ftp, http }

const _filesChannel = MethodChannel('com.pulsefile/files');


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

class StorageSwitcherButton extends StatelessWidget {
  final StorageKind current;
  final int? currentConnectionId; // null pour le local
  const StorageSwitcherButton({super.key, required this.current, this.currentConnectionId});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.swap_horiz),
      tooltip: 'Changer de stockage',
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final volumes = Platform.isAndroid
        ? await resolveVolumes()
        : <QuickPath>[];
    final localRoots = Platform.isWindows || Platform.isMacOS || Platform.isLinux
        ? await _localRoots()
        : <Directory>[];
    final ftpList  = await FtpService.listConnections();
    final httpList = await HttpService.listConnections();
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
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (localRoots.isNotEmpty || volumes.isNotEmpty) ...[
              _section('Local', subCol),
              for (final root in localRoots)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.computer_outlined, color: accent, size: 20),
                  title: Text(root.path.replaceAll(Platform.pathSeparator, ''),
                      style: TextStyle(fontSize: 13, color: textCol)),
                  trailing: current == StorageKind.local
                      ? Icon(Icons.check, size: 18, color: accent) : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => FileBrowserScreen(
                            root: root,
                            title: root.path.replaceAll(Platform.pathSeparator, ''),
                            ch: _filesChannel)));
                  },
                ),
              for (final v in volumes)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.smartphone, color: accent, size: 20),
                  title: Text(v.label, style: TextStyle(fontSize: 13, color: textCol)),
                  trailing: current == StorageKind.local
                      ? Icon(Icons.check, size: 18, color: accent) : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => FileBrowserScreen(
                            root: Directory(v.path), title: v.label, ch: _filesChannel)));
                  },
                ),
            ],
            if (ftpList.isNotEmpty) ...[
              _section('FTP', subCol),
              for (final c in ftpList)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.dns_outlined, color: accent, size: 20),
                  title: Text(c.name, style: TextStyle(fontSize: 13, color: textCol)),
                  subtitle: Text(c.host, style: TextStyle(fontSize: 11, color: subCol)),
                  trailing: (current == StorageKind.ftp && currentConnectionId == c.id)
                      ? Icon(Icons.check, size: 18, color: accent) : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => FtpExplorerScreen(connection: c)));
                  },
                ),
            ],
            if (httpList.isNotEmpty) ...[
              _section('HTTP', subCol),
              for (final c in httpList)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.cloud_outlined, color: accent, size: 20),
                  title: Text(c.name, style: TextStyle(fontSize: 13, color: textCol)),
                  subtitle: Text(c.url, style: TextStyle(fontSize: 11, color: subCol),
                      overflow: TextOverflow.ellipsis),
                  trailing: (current == StorageKind.http && currentConnectionId == c.id)
                      ? Icon(Icons.check, size: 18, color: accent) : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => HttpExplorerScreen(connection: c)));
                  },
                ),
            ],
            if (localRoots.isEmpty && volumes.isEmpty && ftpList.isEmpty && httpList.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Aucune autre source disponible',
                    style: TextStyle(color: subCol), textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label, Color subCol) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: subCol)),
      );
}
