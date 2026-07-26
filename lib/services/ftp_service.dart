// lib/services/ftp_service.dart
//
// Gestion des connexions FTP persistantes via le package ftpconnect.
// Les mots de passe sont stockés via flutter_secure_storage (chiffré par l'OS).
// Les métadonnées (nom, host, port...) sont en SQLite dans pulseit.db.
//
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'saf_mirror_service.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ── Modèle ────────────────────────────────────────────────────────────────────

class FtpConnection {
  final int?   id;
  final String name;
  final String host;
  final int    port;
  final String user;
  final String password; // en clair en mémoire, chiffré via secure_storage
  final bool   passive;
  final String initialPath;
  final String? defaultDownloadPath;

  const FtpConnection({
    this.id,
    required this.name,
    required this.host,
    this.port = 21,
    this.user = 'anonymous',
    this.password = '',
    this.passive = true,
    this.initialPath = '/',
    this.defaultDownloadPath,
  });

  FtpConnection copyWith({int? id, String? name, String? host, int? port,
      String? user, String? password, bool? passive, String? initialPath,
      String? defaultDownloadPath, bool clearDefaultDownloadPath = false}) =>
    FtpConnection(
      id: id ?? this.id, name: name ?? this.name, host: host ?? this.host,
      port: port ?? this.port, user: user ?? this.user,
      password: password ?? this.password, passive: passive ?? this.passive,
      initialPath: initialPath ?? this.initialPath,
      defaultDownloadPath: clearDefaultDownloadPath
          ? null : (defaultDownloadPath ?? this.defaultDownloadPath),
    );
}

// ── Entrée FTP ────────────────────────────────────────────────────────────────

class FtpEntry {
  final String   name;
  final String   path;
  final bool     isDir;
  final int      size;
  final DateTime? modified;

  const FtpEntry({required this.name, required this.path,
      required this.isDir, required this.size, this.modified});
}

// ── Service ───────────────────────────────────────────────────────────────────

class FtpService {
  static const _storage = FlutterSecureStorage();

  // ── DB ────────────────────────────────────────────────────

  static Future<Database> _db() async {
    final dbPath = p.join(await getDatabasesPath(), 'pulseit.db');
    final db = await openDatabase(dbPath);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ftp_connections (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT NOT NULL,
        host         TEXT NOT NULL,
        port         INTEGER NOT NULL DEFAULT 21,
        user         TEXT NOT NULL DEFAULT 'anonymous',
        passive      INTEGER NOT NULL DEFAULT 1,
        initial_path TEXT NOT NULL DEFAULT '/',
        default_download_path TEXT
      )
    ''');
    // Migration : ajoute la colonne si la table existait déjà sans elle.
    try {
      await db.execute('ALTER TABLE ftp_connections ADD COLUMN default_download_path TEXT');
    } catch (_) { /* colonne déjà présente */ }
    return db;
  }

  static String _pwKey(int id) => 'ftp_pw_$id';

  static Future<List<FtpConnection>> listConnections() async {
    final db   = await _db();
    final rows = await db.query('ftp_connections', orderBy: 'name ASC');
    final conns = <FtpConnection>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final pw = await _storage.read(key: _pwKey(id)) ?? '';
      conns.add(FtpConnection(
        id:          id,
        name:        row['name']        as String,
        host:        row['host']        as String,
        port:        row['port']        as int,
        user:        row['user']        as String,
        password:    pw,
        passive:     (row['passive']    as int) == 1,
        initialPath: row['initial_path'] as String? ?? '/',
        defaultDownloadPath: row['default_download_path'] as String?,
      ));
    }
    return conns;
  }

  static Future<FtpConnection> saveConnection(FtpConnection conn) async {
    final db  = await _db();
    final map = {
      'name':         conn.name,
      'host':         conn.host,
      'port':         conn.port,
      'user':         conn.user,
      'passive':      conn.passive ? 1 : 0,
      'initial_path': conn.initialPath,
      'default_download_path': conn.defaultDownloadPath,
    };
    int id;
    if (conn.id == null) {
      id = await db.insert('ftp_connections', map);
    } else {
      id = conn.id!;
      await db.update('ftp_connections', map, where: 'id=?', whereArgs: [id]);
    }
    // Mot de passe dans secure storage (chiffré par l'OS, Keystore sur Android)
    await _storage.write(key: _pwKey(id), value: conn.password);
    await _syncFtpMirror();
    return conn.copyWith(id: id);
  }

  static Future<void> refreshSafMirror() => _syncFtpMirror();

  static Future<void> _syncFtpMirror() async {
    final rows = await (await _db()).query('ftp_connections', columns: ['id']);
    final passwords = <int, String>{};
    for (final row in rows) {
      final id = row['id'] as int;
      passwords[id] = await _storage.read(key: _pwKey(id)) ?? '';
    }
    await SafMirrorService.syncFtpPasswords(passwords);
  }

  static Future<void> deleteConnection(int id) async {
    final db = await _db();
    await db.delete('ftp_connections', where: 'id=?', whereArgs: [id]);
    await _storage.delete(key: _pwKey(id));
    await _syncFtpMirror();
  }

  // ── Client ftpconnect ─────────────────────────────────────

  static FTPConnect _client(FtpConnection conn) => FTPConnect(
    conn.host,
    port:    conn.port,
    user:    conn.user,
    pass:    conn.password,
    timeout: 30,
  );

  static Future<bool> testConnection(FtpConnection conn) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      if (conn.initialPath.isNotEmpty && conn.initialPath != '/') {
        await ftp.changeDirectory(conn.initialPath);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  static Future<List<FtpEntry>> list(FtpConnection conn, String path) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      final dir = path.isEmpty ? '/' : path;
      await ftp.changeDirectory(dir);
      final entries = await ftp.listDirectoryContent();
      return entries
          .where((e) => e.name != '.' && e.name != '..')
          .map((e) {
            final name = e.name;
            final entryPath = dir.endsWith('/')
                ? '$dir$name' : '$dir/$name';
            return FtpEntry(
              name:     name,
              path:     entryPath,
              isDir:    e.type == FTPEntryType.dir,
              size:     e.size ?? 0,
              modified: e.modifyTime,
            );
          })
          .toList();
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  /// [onProgress] : pourcentage, octets reçus, taille totale du fichier.
  static Future<String> download(FtpConnection conn, String remotePath,
      {String? localPath, void Function(double, int, int)? onProgress}) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      final dir  = p.dirname(remotePath);
      final name = p.basename(remotePath);
      await ftp.changeDirectory(dir.isEmpty ? '/' : dir);
      final dest = File(localPath ??
          p.join((await getTemporaryDirectory()).path,
              'ftp_${DateTime.now().millisecondsSinceEpoch}_$name'));
      await ftp.downloadFile(name, dest, onProgress: onProgress);
      return dest.path;
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  /// [onProgress] : pourcentage, octets envoyés, taille totale du fichier.
  static Future<void> upload(FtpConnection conn, String localPath,
      String remotePath, {void Function(double, int, int)? onProgress}) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      final dir  = p.dirname(remotePath);
      final remoteDir = dir.isEmpty ? '/' : dir;
      // Créer les dossiers intermédiaires
      final parts = remoteDir.split('/').where((s) => s.isNotEmpty).toList();
      String current = '';
      for (final part in parts) {
        current = '$current/$part';
        try { await ftp.makeDirectory(current); } catch (_) {}
      }
      await ftp.changeDirectory(remoteDir);
      await ftp.uploadFile(File(localPath), onProgress: onProgress);
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  static Future<void> _deleteDirRecursive(FTPConnect ftp, String dirName) async {
    await ftp.changeDirectory(dirName);
    final entries = await ftp.listDirectoryContent();
    for (final entry in entries) {
      if (entry.name == '.' || entry.name == '..') continue;
      if (entry.type == FTPEntryType.dir) {
        await _deleteDirRecursive(ftp, entry.name);
      } else {
        await ftp.deleteFile(entry.name);
      }
    }
    await ftp.changeDirectory('..');
    await ftp.deleteDirectory(dirName);
  }

  static Future<void> delete(FtpConnection conn, String remotePath,
      {bool isDir = false}) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      final dir  = p.dirname(remotePath);
      final name = p.basename(remotePath);
      await ftp.changeDirectory(dir.isEmpty ? '/' : dir);
      if (isDir) {
        // RMD echoue sur un dossier non vide sur la plupart des serveurs FTP :
        // on vide recursivement avant de supprimer le dossier lui-meme.
        await _deleteDirRecursive(ftp, name);
      } else {
        await ftp.deleteFile(name);
      }
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  /// Compte récursivement le nombre de fichiers et sous-dossiers contenus
  /// dans un dossier distant (pour affichage avant suppression par ex).
  static Future<({int files, int dirs})> dirStats(
      FtpConnection conn, String remotePath) async {
    final ftp = _client(conn);
    final counts = <String, int>{'files': 0, 'dirs': 0};
    try {
      await ftp.connect();
      await ftp.changeDirectory(remotePath.isEmpty ? '/' : remotePath);
      await _countRecursive(ftp, counts);
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
    return (files: counts['files']!, dirs: counts['dirs']!);
  }

  static Future<void> _countRecursive(FTPConnect ftp, Map<String, int> counts) async {
    final entries = await ftp.listDirectoryContent();
    for (final entry in entries) {
      if (entry.name == '.' || entry.name == '..') continue;
      if (entry.type == FTPEntryType.dir) {
        counts['dirs'] = counts['dirs']! + 1;
        await ftp.changeDirectory(entry.name);
        await _countRecursive(ftp, counts);
        await ftp.changeDirectory('..');
      } else {
        counts['files'] = counts['files']! + 1;
      }
    }
  }

  /// Renomme un fichier ou dossier (chemins complets depuis la racine).
  static Future<void> rename(FtpConnection conn, String from, String to) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      await ftp.rename(from, to);
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  /// Déplace un fichier ou dossier vers un autre chemin (peut changer de
  /// dossier parent). Crée les dossiers intermédiaires de destination si besoin.
  static Future<void> move(FtpConnection conn, String fromPath, String toPath) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      final destDir = p.dirname(toPath);
      if (destDir.isNotEmpty && destDir != '.' && destDir != '/') {
        final parts = destDir.split('/').where((s) => s.isNotEmpty).toList();
        String current = '';
        for (final part in parts) {
          current = '$current/$part';
          try { await ftp.makeDirectory(current); } catch (_) {}
        }
      }
      await ftp.rename(fromPath, toPath);
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }

  static Future<void> mkdir(FtpConnection conn, String path) async {
    final ftp = _client(conn);
    try {
      await ftp.connect();
      await ftp.makeDirectory(path);
    } finally {
      try { await ftp.disconnect(); } catch (_) {}
    }
  }
}
