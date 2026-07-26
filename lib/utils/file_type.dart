// lib/utils/file_type.dart
//
// Classifie un fichier par extension pour déterminer comment l'ouvrir
// (visualiseur intégré, extraction, installation, ou application système
// par défaut). Utilisé par les trois explorateurs (local, FTP, HTTP).
//
import 'package:path/path.dart' as p;

enum FileKind { text, image, video, audio, apk, archive, other }

const kTextExtensions = {
  '.txt', '.md', '.log', '.json', '.xml', '.csv', '.dart', '.kt', '.py',
  '.js', '.html', '.css', '.yaml', '.yml', '.ini', '.conf', '.sh', '.bat',
};

const kImageExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic',
};

const kVideoExtensions = {
  '.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v', '.3gp',
};

const kAudioExtensions = {
  '.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg',
};

const kArchiveExtensions = {'.zip'};

FileKind classifyFile(String name) {
  final ext = p.extension(name).toLowerCase();
  if (ext == '.apk') return FileKind.apk;
  if (kArchiveExtensions.contains(ext)) return FileKind.archive;
  if (kTextExtensions.contains(ext)) return FileKind.text;
  if (kImageExtensions.contains(ext)) return FileKind.image;
  if (kVideoExtensions.contains(ext)) return FileKind.video;
  if (kAudioExtensions.contains(ext)) return FileKind.audio;
  return FileKind.other;
}
