import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ftp_service.dart';
import 'http_service.dart';

/// Transferts inter-connexions.
///
/// Le flux passe par un fichier temporaire local lorsque les deux extrémités
/// sont des connexions distantes. Cela permet notamment :
///   HTTP -> FTP
///   FTP  -> HTTP
///
/// Le même mécanisme pourra ensuite être étendu à d'autres adaptateurs.
class CrossConnectionTransferService {
  static Future<void> httpToFtp({
    required HttpConnection source,
    required String sourcePath,
    required FtpConnection destination,
    required String destinationPath,
    void Function(int transferred, int total)? onProgress,
    bool deleteSource = false,
  }) async {
    final temp = await _tempFile(sourcePath);
    try {
      await HttpService.download(
        source,
        sourcePath,
        localPath: temp.path,
        onProgress: onProgress,
      );
      await FtpService.upload(
        destination,
        temp.path,
        destinationPath,
        onProgress: (percent, sent, total) {
          onProgress?.call(sent, total);
        },
      );
      if (deleteSource) {
        await HttpService.delete(source, sourcePath);
      }
    } finally {
      await _deleteTemp(temp);
    }
  }

  static Future<void> ftpToHttp({
    required FtpConnection source,
    required String sourcePath,
    required HttpConnection destination,
    required String destinationPath,
    void Function(int transferred, int total)? onProgress,
    bool deleteSource = false,
  }) async {
    final temp = await _tempFile(sourcePath);
    try {
      await FtpService.download(
        source,
        sourcePath,
        localPath: temp.path,
        onProgress: (percent, received, total) {
          onProgress?.call(received, total);
        },
      );
      await HttpService.upload(
        destination,
        temp.path,
        destinationPath,
        onProgress: onProgress,
      );
      if (deleteSource) {
        await FtpService.delete(source, sourcePath);
      }
    } finally {
      await _deleteTemp(temp);
    }
  }

  static Future<File> _tempFile(String sourcePath) async {
    final dir = await getTemporaryDirectory();
    final name = p.basename(sourcePath).isEmpty
        ? 'transfer.bin'
        : p.basename(sourcePath);
    return File(p.join(
      dir.path,
      'pulse_transfer_${DateTime.now().microsecondsSinceEpoch}_$name',
    ));
  }

  static Future<void> _deleteTemp(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
