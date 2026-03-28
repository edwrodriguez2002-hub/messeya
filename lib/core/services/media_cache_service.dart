import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/message.dart';

final mediaCacheServiceProvider = Provider<MediaCacheService>((ref) {
  return MediaCacheService();
});

class MediaCacheService {
  Future<File?> getCachedFile(Message message) async {
    final file = await _targetFile(message);
    if (await file.exists()) return file;
    return null;
  }

  Future<File?> ensureCached(Message message) async {
    if (message.attachmentUrl.isEmpty) return null;
    final target = await _targetFile(message);
    if (await target.exists()) return target;

    final response = await http.get(Uri.parse(message.attachmentUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('No se pudo descargar el archivo recibido.');
    }
    await target.parent.create(recursive: true);
    await target.writeAsBytes(response.bodyBytes, flush: true);
    return target;
  }

  Future<File> _targetFile(Message message) async {
    final directory = await getApplicationDocumentsDirectory();
    final mediaDir =
        Directory(path.join(directory.path, 'media_cache', message.chatId));
    final extension = _resolveExtension(message);
    final fileName = extension.isEmpty ? message.id : '${message.id}$extension';
    return File(path.join(mediaDir.path, fileName));
  }

  String _resolveExtension(Message message) {
    final fromName = path.extension(message.fileName);
    if (fromName.isNotEmpty) return fromName;
    return switch (message.type) {
      'image' => '.jpg',
      'video' => '.mp4',
      'audio' => '.m4a',
      _ => '',
    };
  }
}
