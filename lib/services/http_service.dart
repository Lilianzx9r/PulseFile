// lib/services/http_service.dart
//
// Connexion PHP/HTTP pour PulseIt — adaptée depuis Pulsia.
// Upload/download via multipart HTTP.
// Authentification : HMAC-SHA256 (token + timestamp) + Basic Auth optionnelle.
// Persistance : flutter_secure_storage (chiffrement OS).
//
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'saf_mirror_service.dart';

// ── Modèle ────────────────────────────────────────────────────────────────────

class HttpConnection {
  final int?   id;
  final String name;
  final String url;
  final String token;
  final String basicUser;
  final String basicPassword;
  final String? defaultDownloadPath;

  const HttpConnection({
    this.id,
    required this.name,
    required this.url,
    this.token         = '',
    this.basicUser     = '',
    this.basicPassword = '',
    this.defaultDownloadPath,
  });

  bool get isValid =>
      url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'));

  bool get hasBasicAuth => basicUser.isNotEmpty;

  HttpConnection copyWith({int? id, String? name, String? url,
      String? token, String? basicUser, String? basicPassword,
      String? defaultDownloadPath, bool clearDefaultDownloadPath = false}) =>
    HttpConnection(
      id:            id            ?? this.id,
      name:          name          ?? this.name,
      url:           url           ?? this.url,
      token:         token         ?? this.token,
      basicUser:     basicUser     ?? this.basicUser,
      basicPassword: basicPassword ?? this.basicPassword,
      defaultDownloadPath: clearDefaultDownloadPath
          ? null : (defaultDownloadPath ?? this.defaultDownloadPath),
    );
}

// ── Service ───────────────────────────────────────────────────────────────────

class HttpService {
  static const _storage = FlutterSecureStorage();
  static const _timeout = Duration(seconds: 60);

  // ── Persistance (une connexion par "slot" nommé) ───────────────────────────
  // Stockage : liste des IDs en JSON dans secure_storage, métadonnées par ID.

  static const _kIds = 'http_conn_ids';

  static Future<List<HttpConnection>> listConnections() async {
    final raw  = await _storage.read(key: _kIds) ?? '[]';
    final ids  = (jsonDecode(raw) as List).cast<int>();
    final list = <HttpConnection>[];
    for (final id in ids) {
      final conn = await _loadById(id);
      if (conn != null) list.add(conn);
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  static Future<HttpConnection?> _loadById(int id) async {
    final name = await _storage.read(key: 'http_${id}_name') ?? '';
    final url  = await _storage.read(key: 'http_${id}_url')  ?? '';
    if (url.isEmpty) return null;
    return HttpConnection(
      id:            id,
      name:          name,
      url:           url,
      token:         await _storage.read(key: 'http_${id}_token')      ?? '',
      basicUser:     await _storage.read(key: 'http_${id}_basic_user') ?? '',
      basicPassword: await _storage.read(key: 'http_${id}_basic_pass') ?? '',
      defaultDownloadPath: await _storage.read(key: 'http_${id}_dl_path'),
    );
  }

  static Future<HttpConnection> saveConnection(HttpConnection conn) async {
    final raw = await _storage.read(key: _kIds) ?? '[]';
    final ids = List<int>.from((jsonDecode(raw) as List).cast<int>());
    final id  = conn.id ?? (ids.isEmpty ? 1 : ids.reduce((a, b) => a > b ? a : b) + 1);
    if (!ids.contains(id)) ids.add(id);
    await _storage.write(key: _kIds, value: jsonEncode(ids));
    await _storage.write(key: 'http_${id}_name',       value: conn.name);
    await _storage.write(key: 'http_${id}_url',        value: conn.url);
    await _storage.write(key: 'http_${id}_token',      value: conn.token);
    await _storage.write(key: 'http_${id}_basic_user', value: conn.basicUser);
    await _storage.write(key: 'http_${id}_basic_pass', value: conn.basicPassword);
    if (conn.defaultDownloadPath == null) {
      await _storage.delete(key: 'http_${id}_dl_path');
    } else {
      await _storage.write(key: 'http_${id}_dl_path', value: conn.defaultDownloadPath);
    }
    final saved = conn.copyWith(id: id);
    await _syncSafMirror();
    return saved;
  }

  static Future<void> deleteConnection(int id) async {
    final raw = await _storage.read(key: _kIds) ?? '[]';
    final ids = List<int>.from((jsonDecode(raw) as List).cast<int>())..remove(id);
    await _storage.write(key: _kIds, value: jsonEncode(ids));
    for (final key in ['name','url','token','basic_user','basic_pass','dl_path']) {
      await _storage.delete(key: 'http_${id}_$key');
    }
    await SafMirrorService.syncHttp(await _safMirrorData());
  }

  /// Construit les données du miroir SAF (voir SafMirrorService) à partir
  /// des connexions HTTP actuellement enregistrées.
  static Future<List<Map<String, dynamic>>> _safMirrorData() async {
    final list = await listConnections();
    return list.where((c) => c.id != null).map((c) => {
          'id': c.id,
          'name': c.name,
          'url': c.url,
          'token': c.token,
          'basicUser': c.basicUser,
          'basicPassword': c.basicPassword,
        }).toList();
  }

  static Future<void> refreshSafMirror() async {
    await SafMirrorService.syncHttp(await _safMirrorData());
  }

  static Future<void> _syncSafMirror() async {
    await SafMirrorService.syncHttp(await _safMirrorData());
  }

  // ── Opérations HTTP ────────────────────────────────────────────────────────

  static Future<bool> testConnection(HttpConnection conn) async {
    try {
      final uri = _sign(Uri.parse('${conn.url}?action=ping'), conn);
      final res = await http.get(uri, headers: _headers(conn)).timeout(_timeout);
      if (res.statusCode != 200) return false;
      final ct   = res.headers['content-type'] ?? '';
      if (!ct.contains('json')) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } catch (_) { return false; }
  }

  /// Liste les fichiers dans un sous-dossier du serveur.
  static Future<List<HttpRemoteEntry>> list(HttpConnection conn,
      {String subdir = '.'}) async {
    final uri = _sign(
        Uri.parse('${conn.url}?action=list&dir=$subdir'), conn);
    final res = await http.get(uri, headers: _headers(conn)).timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }

    // Le serveur PHP peut renvoyer du HTML (erreur, page de redirection,
    // page de login hébergeur) au lieu de JSON — message clair dans ce cas.
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Réponse inattendue du serveur (pas un objet JSON)');
      }
      body = decoded;
    } on FormatException {
      throw Exception('Le serveur n\'a pas renvoyé de JSON valide. '
          'Réponse reçue : ${_shortBody(res.body)}');
    }

    // Le script PHP de Pulsia ne renvoie pas de champ "success" pour l'action
    // list — il renvoie directement {"files": [...]}. On ne vérifie "success"
    // que s'il est explicitement présent ET faux ; sinon on continue tant que
    // "files" est exploitable.
    if (body.containsKey('success') && body['success'] != true) {
      throw Exception(body['error']?.toString() ??
          'Le serveur a renvoyé success=false. '
          'Réponse complète : ${_shortBody(res.body)}');
    }

    final rawFiles = body['files'];
    if (rawFiles is! List) {
      throw Exception('Champ "files" manquant ou invalide dans la réponse');
    }

    final result = <HttpRemoteEntry>[];
    for (final f in rawFiles) {
      if (f is! Map) continue;
      final name = f['name'];
      if (name is! String || name.isEmpty) continue;
      final isDir = f['isDir'] == true || f['type'] == 'dir' || f['type'] == 'directory';
      result.add(HttpRemoteEntry(
        name:       name,
        remotePath: '$subdir/$name'.replaceAll('//', '/'),
        size:       (f['size'] as num?)?.toInt() ?? 0,
        isDir:      isDir,
        modified:   DateTime.tryParse(f['modifiedAt']?.toString() ?? ''),
      ));
    }
    return result;
  }

  /// Tronque le corps de réponse pour un message d'erreur lisible.
  static String _shortBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '(réponse vide)';
    return trimmed.length > 400 ? '${trimmed.substring(0, 400)}…' : trimmed;
  }

  /// Upload un fichier local vers le serveur.
  /// Callback de progression : [sent]/[total] octets transférés. [total]
  /// peut être -1 si la taille n'est pas connue à l'avance.
  static Future<void> upload(HttpConnection conn, String localPath,
      String remotePath, {void Function(int sent, int total)? onProgress}) async {
    final parts  = remotePath.split('/');
    final subdir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '.';
    final name   = parts.last;
    final uri    = _sign(
        Uri.parse('${conn.url}?action=upload&dir=$subdir&file=$name'), conn);

    final file   = File(localPath);
    final length = await file.length();
    var sent = 0;
    final stream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          sent += data.length;
          onProgress?.call(sent, length);
          sink.add(data);
        },
      ),
    );
    final multipartFile = http.MultipartFile('file', stream, length, filename: name);

    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers(conn))
      ..files.add(multipartFile);
    final streamed = await req.send().timeout(const Duration(minutes: 10));
    final res      = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw Exception(_extractError(res.body) ??
          'HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }
  }

  /// Télécharge un fichier depuis le serveur, en flux (pas de mise en
  /// mémoire complète du fichier — nécessaire pour les gros fichiers).
  /// [onProgress] : [received]/[total] octets ([total] = -1 si inconnu).
  static Future<String> download(HttpConnection conn, String remotePath,
      {String? localPath, void Function(int received, int total)? onProgress}) async {
    final parts  = remotePath.split('/');
    final subdir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '.';
    final name   = parts.last;
    final uri    = _sign(
        Uri.parse('${conn.url}?action=download&dir=$subdir&file=$name'), conn);

    final client = http.Client();
    try {
      final req = http.Request('GET', uri)..headers.addAll(_headers(conn));
      final streamed = await client.send(req).timeout(const Duration(minutes: 30));
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        throw Exception(_extractError(body) ?? 'HTTP ${streamed.statusCode}');
      }
      final total = streamed.contentLength ?? -1;
      var received = 0;
      final dest = File(localPath ??
          p.join((await getTemporaryDirectory()).path,
              'http_${DateTime.now().millisecondsSinceEpoch}_$name'));
      await dest.parent.create(recursive: true);
      final sink = dest.openWrite();
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.close();
      return dest.path;
    } finally {
      client.close();
    }
  }

  /// Supprime un fichier sur le serveur.
  static Future<void> delete(HttpConnection conn, String remotePath) async {
    final parts  = remotePath.split('/');
    final subdir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '.';
    final name   = parts.last;
    final uri    = _sign(
        Uri.parse('${conn.url}?action=delete&dir=$subdir&file=$name'), conn);
    final res    = await http.delete(uri, headers: _headers(conn)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_extractError(res.body) ??
          'HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }
  }

  /// Crée un dossier sur le serveur.
  static Future<void> mkdir(HttpConnection conn, String remotePath) async {
    final parts  = remotePath.split('/').where((s) => s.isNotEmpty).toList();
    final name   = parts.isNotEmpty ? parts.last : remotePath;
    final subdir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '.';
    final uri    = _sign(
        Uri.parse('${conn.url}?action=mkdir&dir=$subdir&name=$name'), conn);
    final res    = await http.post(uri, headers: _headers(conn)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }
    // Vérifier success seulement s'il est présent dans la réponse
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic> &&
          decoded.containsKey('success') && decoded['success'] != true) {
        throw Exception(decoded['error']?.toString() ??
            'Échec création dossier : ${_shortBody(res.body)}');
      }
    } on FormatException {
      // Réponse non-JSON avec statut 200 : on considère que ça a fonctionné
      // si le serveur n'a pas explicitement signalé une erreur.
    }
  }

  /// Renomme un fichier ou dossier sur le serveur.
  static Future<void> rename(HttpConnection conn, String fromPath, String toName) async {
    final parts  = fromPath.split('/');
    final subdir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '.';
    final from   = parts.last;
    final uri    = _sign(
        Uri.parse('${conn.url}?action=rename&dir=$subdir&from=$from&to=$toName'), conn);
    final res    = await http.post(uri, headers: _headers(conn)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_extractError(res.body) ??
          'HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }
  }

  /// Compte récursivement le nombre de fichiers et sous-dossiers contenus
  /// dans un dossier distant (pour affichage avant suppression par ex).
  static Future<({int files, int dirs})> dirStats(
      HttpConnection conn, String remotePath) async {
    final uri = _sign(
        Uri.parse('${conn.url}?action=dir_stats'
            '&path=${Uri.encodeQueryComponent(remotePath)}'), conn);
    final res = await http.get(uri, headers: _headers(conn)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_extractError(res.body) ??
          'HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (files: (body['files'] as num?)?.toInt() ?? 0,
            dirs:  (body['dirs']  as num?)?.toInt() ?? 0);
  }

  /// Déplace un fichier ou dossier vers un autre chemin (peut changer de dossier parent).
  /// [fromPath] et [toPath] sont des chemins relatifs complets depuis la racine
  /// (ex: "./old/name" -> "./new/place/name").
  static Future<void> move(HttpConnection conn, String fromPath, String toPath) async {
    final uri = _sign(
        Uri.parse('${conn.url}?action=move&from=${Uri.encodeQueryComponent(fromPath)}'
            '&to=${Uri.encodeQueryComponent(toPath)}'), conn);
    final res = await http.post(uri, headers: _headers(conn)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(_extractError(res.body) ??
          'HTTP ${res.statusCode} — ${_shortBody(res.body)}');
    }
  }

  /// Extrait le champ "error" d'une réponse JSON si possible, sinon null
  /// (ne lève jamais d'exception même si la réponse n'est pas du JSON valide).
  static String? _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded['error']?.toString();
    } catch (_) {}
    return null;
  }

  // ── Crypto / headers ───────────────────────────────────────────────────────

  static Map<String, String> _headers(HttpConnection conn) {
    final h = <String, String>{'Accept': 'application/json'};
    if (conn.hasBasicAuth) {
      final creds = base64Encode(utf8.encode('${conn.basicUser}:${conn.basicPassword}'));
      h['Authorization'] = 'Basic $creds';
    }
    return h;
  }

  /// Signe l'URI avec HMAC-SHA256 (timestamp + signature en query params).
  static Uri _sign(Uri uri, HttpConnection conn) {
    if (conn.token.isEmpty) return uri;
    final ts   = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final hmac = Hmac(sha256, utf8.encode(conn.token));
    final sig  = hmac.convert(utf8.encode(ts)).toString();
    final params = Map<String, String>.from(uri.queryParameters)
      ..['_ts']  = ts
      ..['_sig'] = sig;
    return uri.replace(queryParameters: params);
  }
}

// ── Entrée distante (utilisée par SaveDestinationPicker) ─────────────────────

class HttpRemoteEntry {
  final String   name;
  final String   remotePath;
  final int      size;
  final bool     isDir;
  final DateTime? modified;
  const HttpRemoteEntry({required this.name, required this.remotePath,
      required this.size, this.isDir = false, this.modified});
}
