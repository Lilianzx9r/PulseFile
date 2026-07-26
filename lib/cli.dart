// lib/cli.dart
//
// Pilotage de PulseFile en ligne de commande (Windows cmd / PowerShell).
//
// L'exécutable Windows généré par Flutter transmet déjà les arguments de la
// ligne de commande à main() — voir windows/runner/main.cpp qui appelle
// project.set_dart_entrypoint_arguments(GetCommandLineArguments()). Aucune
// modification du code natif n'est donc nécessaire.
//
// Limite connue (commandes "silencieuses") : la fenêtre native est créée par
// le runner AVANT que Dart n'exécute main() ; elle apparaîtra donc brièvement
// (fenêtre vide) puis se fermera dès que la commande se termine (exit()).
// Ce n'est pas un mode totalement invisible — juste un flash bref.
// Les commandes pick-folder/pick-file, elles, affichent une vraie fenêtre
// interactive (c'est le but) et se ferment une fois le choix fait.
//
// Usage :
//   pulsefile.exe connections
//   pulsefile.exe list        --conn "MonFTP"  [--remote /chemin] [--type ftp|http]
//   pulsefile.exe download    --conn "MonFTP"  --remote /chemin/fichier --out "C:\Dest"
//   pulsefile.exe upload      --conn "MonFTP"  --local "C:\fichier"     [--remote /dossier]
//   pulsefile.exe move        --conn "MonFTP"  --from /a --to /b/a
//   pulsefile.exe delete      --conn "MonFTP"  --remote /chemin [--dir]
//   pulsefile.exe mkdir       --conn "MonFTP"  --remote /nouveau-dossier
//   pulsefile.exe pick-folder [--start "C:\Dossier"]
//   pulsefile.exe pick-file   [--start "C:\Dossier"] [--multiple]
//   pulsefile.exe help
//
// pick-folder/pick-file ouvrent une fenêtre PulseFile avec le sélecteur
// concerné ; le(s) chemin(s) choisi(s) sont écrits sur stdout (un par ligne),
// avec un code de sortie 0. Si l'utilisateur annule, rien n'est écrit et le
// code de sortie est 1. Permet à un script ou une autre application
// d'utiliser PulseFile comme sélecteur de dossier/fichier externe :
//   for /f "delims=" %%D in ('pulsefile.exe pick-folder') do set DEST=%%D
//
// --type est optionnel : déduit automatiquement si le nom de connexion
// n'existe que d'un seul côté (FTP ou HTTP). Obligatoire en cas d'ambiguïté
// (même nom utilisé pour une connexion FTP et une connexion HTTP).
//
import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'services/ftp_service.dart';
import 'services/http_service.dart';
import 'widgets/local_folder_picker.dart';
import 'widgets/local_file_picker.dart';

const _commands = {
  'connections', 'list', 'download', 'upload', 'move', 'delete', 'mkdir',
  'pick-folder', 'pick-file', 'help',
};

enum CliGuiAction { pickFolder, pickFile }

/// Résultat de l'analyse des arguments CLI.
class CliOutcome {
  /// true si une commande a déjà été exécutée (silencieusement) — l'appelant
  /// doit quitter le processus juste après.
  final bool handled;
  /// non-null si une fenêtre interactive doit être affichée (pick-folder/
  /// pick-file) — l'appelant doit lancer [CliPickerApp] au lieu de l'app normale.
  final CliGuiAction? guiAction;
  final String? startPath;
  final bool allowMultiple;
  const CliOutcome({
    this.handled = false,
    this.guiAction,
    this.startPath,
    this.allowMultiple = false,
  });
}

/// Point d'entrée CLI. Voir [CliOutcome] pour l'interprétation du résultat.
/// Si aucun argument n'est reconnu, l'app doit démarrer normalement en mode
/// graphique standard.
Future<CliOutcome> runCli(List<String> args) async {
  if (args.isEmpty) return const CliOutcome();
  final command = args.first;
  if (!_commands.contains(command)) return const CliOutcome();

  final parser = ArgParser()
    ..addOption('conn')
    ..addOption('type', allowed: ['ftp', 'http'])
    ..addOption('remote')
    ..addOption('local')
    ..addOption('out')
    ..addOption('from')
    ..addOption('to')
    ..addOption('start')
    ..addFlag('dir', defaultsTo: false)
    ..addFlag('multiple', defaultsTo: false);

  ArgResults res;
  try {
    res = parser.parse(args.sublist(1));
  } catch (e) {
    stderr.writeln('Erreur d\'arguments : $e');
    exitCode = 2;
    return const CliOutcome(handled: true);
  }

  if (command == 'pick-folder' || command == 'pick-file') {
    return CliOutcome(
      guiAction: command == 'pick-folder' ? CliGuiAction.pickFolder : CliGuiAction.pickFile,
      startPath: res['start'] as String?,
      allowMultiple: res['multiple'] == true,
    );
  }

  try {
    switch (command) {
      case 'help':
        _printHelp();
      case 'connections':
        await _cmdConnections();
      case 'list':
        await _cmdList(res);
      case 'download':
        await _cmdDownload(res);
      case 'upload':
        await _cmdUpload(res);
      case 'move':
        await _cmdMove(res);
      case 'delete':
        await _cmdDelete(res);
      case 'mkdir':
        await _cmdMkdir(res);
    }
  } catch (e) {
    stderr.writeln('Erreur : $e');
    exitCode = 1;
  }
  return const CliOutcome(handled: true);
}

/// App minimale affichée pour pick-folder/pick-file : pousse le sélecteur
/// concerné par-dessus un hôte vide, puis écrit le résultat sur stdout et
/// quitte le processus.
class CliPickerApp extends StatelessWidget {
  final CliOutcome outcome;
  const CliPickerApp({super.key, required this.outcome});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D7CF4)),
        useMaterial3: true,
      ),
      home: _CliPickerHost(outcome: outcome),
    );
  }
}

class _CliPickerHost extends StatefulWidget {
  final CliOutcome outcome;
  const _CliPickerHost({required this.outcome});

  @override
  State<_CliPickerHost> createState() => _CliPickerHostState();
}

class _CliPickerHostState extends State<_CliPickerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    dynamic result;
    if (widget.outcome.guiAction == CliGuiAction.pickFolder) {
      result = await Navigator.push<String>(context, MaterialPageRoute(
          builder: (_) => LocalFolderPickerScreen(initialPath: widget.outcome.startPath)));
    } else {
      result = await Navigator.push<List<String>>(context, MaterialPageRoute(
          builder: (_) => LocalFilePickerScreen(
              initialPath: widget.outcome.startPath,
              allowMultiple: widget.outcome.allowMultiple)));
    }
    if (result == null) {
      exitCode = 1; // annulé par l'utilisateur
    } else if (result is String) {
      stdout.writeln(result);
      exitCode = 0;
    } else if (result is List<String>) {
      if (result.isEmpty) {
        exitCode = 1;
      } else {
        for (final r in result) { stdout.writeln(r); }
        exitCode = 0;
      }
    }
    exit(exitCode);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

void _printHelp() {
  print('''
PulseFile — commandes disponibles :

  pulsefile.exe connections
  pulsefile.exe list        --conn "Nom"  [--remote /chemin] [--type ftp|http]
  pulsefile.exe download    --conn "Nom"  --remote /chemin/fichier --out "C:\\Dest"
  pulsefile.exe upload      --conn "Nom"  --local "C:\\fichier"     [--remote /dossier]
  pulsefile.exe move        --conn "Nom"  --from /a --to /b/a
  pulsefile.exe delete      --conn "Nom"  --remote /chemin [--dir]
  pulsefile.exe mkdir       --conn "Nom"  --remote /nouveau-dossier
  pulsefile.exe pick-folder [--start "C:\\Dossier"]
  pulsefile.exe pick-file   [--start "C:\\Dossier"] [--multiple]
  pulsefile.exe help

--type est optionnel, déduit automatiquement sauf ambiguïté de nom.
pick-folder/pick-file ouvrent une fenêtre interactive et affichent le(s)
chemin(s) choisi(s) sur stdout (code de sortie 1 si annulé).
''');
}

String _require(ArgResults res, String key) {
  final v = res[key] as String?;
  if (v == null || v.isEmpty) {
    throw Exception('Argument --$key requis pour cette commande');
  }
  return v;
}

// ── Résolution de connexion (FTP ou HTTP, par nom) ─────────────────────────

class _Resolved {
  final bool isFtp;
  final FtpConnection? ftp;
  final HttpConnection? http;
  _Resolved.ftp(this.ftp) : isFtp = true, http = null;
  _Resolved.http(this.http) : isFtp = false, ftp = null;
}

Future<_Resolved?> _resolveConnection(String name, String? forceType) async {
  final ftpList  = await FtpService.listConnections();
  final httpList = await HttpService.listConnections();
  final ftpMatch  = ftpList.where((c) => c.name == name).toList();
  final httpMatch = httpList.where((c) => c.name == name).toList();

  if (forceType == 'ftp') {
    return ftpMatch.isNotEmpty ? _Resolved.ftp(ftpMatch.first) : null;
  }
  if (forceType == 'http') {
    return httpMatch.isNotEmpty ? _Resolved.http(httpMatch.first) : null;
  }
  if (ftpMatch.isNotEmpty && httpMatch.isNotEmpty) {
    stderr.writeln('Ambigu : une connexion FTP et une connexion HTTP portent '
        'le nom "$name". Précise --type ftp ou --type http.');
    return null;
  }
  if (ftpMatch.isNotEmpty)  return _Resolved.ftp(ftpMatch.first);
  if (httpMatch.isNotEmpty) return _Resolved.http(httpMatch.first);
  return null;
}

Future<_Resolved?> _requireConnection(ArgResults res) async {
  final name = _require(res, 'conn');
  final conn = await _resolveConnection(name, res['type'] as String?);
  if (conn == null) {
    stderr.writeln('Connexion "$name" introuvable.');
    exitCode = 1;
  }
  return conn;
}

// ── Commandes ────────────────────────────────────────────────────────────

Future<void> _cmdConnections() async {
  final ftpList  = await FtpService.listConnections();
  final httpList = await HttpService.listConnections();
  print('Connexions FTP :');
  if (ftpList.isEmpty) print('  (aucune)');
  for (final c in ftpList) {
    print('  - ${c.name}  (${c.host}:${c.port})'
        '${c.defaultDownloadPath != null ? '  [défaut: ${c.defaultDownloadPath}]' : ''}');
  }
  print('Connexions HTTP :');
  if (httpList.isEmpty) print('  (aucune)');
  for (final c in httpList) {
    print('  - ${c.name}  (${c.url})'
        '${c.defaultDownloadPath != null ? '  [défaut: ${c.defaultDownloadPath}]' : ''}');
  }
}

Future<void> _cmdList(ArgResults res) async {
  final conn = await _requireConnection(res);
  if (conn == null) return;
  final remote = res['remote'] as String? ?? (conn.isFtp ? '/' : '.');
  if (conn.isFtp) {
    final entries = await FtpService.list(conn.ftp!, remote);
    for (final e in entries) {
      print('${e.isDir ? '[D]' : '[F]'}  ${e.name}');
    }
  } else {
    final entries = await HttpService.list(conn.http!, subdir: remote);
    for (final e in entries) {
      print('${e.isDir ? '[D]' : '[F]'}  ${e.name}');
    }
  }
}

Future<void> _cmdDownload(ArgResults res) async {
  final conn = await _requireConnection(res);
  if (conn == null) return;
  final remote = _require(res, 'remote');
  final out    = _require(res, 'out');
  final fileName = remote.split('/').where((s) => s.isNotEmpty).last;
  final localPath = p.join(out, fileName);
  await Directory(out).create(recursive: true);
  final saved = conn.isFtp
      ? await FtpService.download(conn.ftp!, remote, localPath: localPath)
      : await HttpService.download(conn.http!, remote, localPath: localPath);
  print('OK : téléchargé vers $saved');
}

Future<void> _cmdUpload(ArgResults res) async {
  final conn = await _requireConnection(res);
  if (conn == null) return;
  final local = _require(res, 'local');
  final remoteDir = res['remote'] as String? ?? (conn.isFtp ? '/' : '.');
  final fileName = p.basename(local);
  final remotePath = '$remoteDir/$fileName'.replaceAll('//', '/');
  if (conn.isFtp) {
    await FtpService.upload(conn.ftp!, local, remotePath);
  } else {
    await HttpService.upload(conn.http!, local, remotePath);
  }
  print('OK : envoyé vers $remotePath');
}

Future<void> _cmdMove(ArgResults res) async {
  final conn = await _requireConnection(res);
  if (conn == null) return;
  final from = _require(res, 'from');
  final to   = _require(res, 'to');
  if (conn.isFtp) {
    await FtpService.move(conn.ftp!, from, to);
  } else {
    await HttpService.move(conn.http!, from, to);
  }
  print('OK : déplacé $from -> $to');
}

Future<void> _cmdDelete(ArgResults res) async {
  final conn = await _requireConnection(res);
  if (conn == null) return;
  final remote = _require(res, 'remote');
  if (conn.isFtp) {
    await FtpService.delete(conn.ftp!, remote, isDir: res['dir'] == true);
  } else {
    await HttpService.delete(conn.http!, remote);
  }
  print('OK : supprimé $remote');
}

Future<void> _cmdMkdir(ArgResults res) async {
  final conn = await _requireConnection(res);
  if (conn == null) return;
  final remote = _require(res, 'remote');
  if (conn.isFtp) {
    await FtpService.mkdir(conn.ftp!, remote);
  } else {
    await HttpService.mkdir(conn.http!, remote);
  }
  print('OK : dossier créé $remote');
}
