import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

final cloudinaryMediaServiceProvider = Provider<CloudinaryMediaService>((ref) {
  return CloudinaryMediaService(
    cloudName: const String.fromEnvironment(
      'CLOUDINARY_CLOUD_NAME',
      defaultValue: 'dvpouzvpq',
    ),
    uploadPreset: const String.fromEnvironment(
      'CLOUDINARY_UPLOAD_PRESET',
      defaultValue: 'messeya_unsigned',
    ),
  );
});

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
    required this.resourceType,
    required this.folder,
  });

  final String secureUrl;
  final String publicId;
  final String resourceType;
  final String folder;
}

class CloudinaryMediaService {
  CloudinaryMediaService({
    required this.cloudName,
    required this.uploadPreset,
  });

  final String cloudName;
  final String uploadPreset;

  bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;

  Future<String> uploadImage({
    File? file,
    Uint8List? bytes,
    String? fileName,
    required String folder,
    String? publicId,
  }) async {
    return (await uploadImageAsset(
      file: file,
      bytes: bytes,
      fileName: fileName,
      folder: folder,
      publicId: publicId,
    ))
        .secureUrl;
  }

  Future<CloudinaryUploadResult> uploadImageAsset({
    File? file,
    Uint8List? bytes,
    String? fileName,
    required String folder,
    String? publicId,
  }) {
    return _upload(
      resourceType: 'image',
      file: file,
      bytes: bytes,
      fileName: fileName,
      folder: folder,
      publicId: publicId,
    );
  }

  Future<String> uploadVideo({
    required File file,
    required String folder,
    String? publicId,
  }) async {
    return (await uploadVideoAsset(
      file: file,
      folder: folder,
      publicId: publicId,
    ))
        .secureUrl;
  }

  Future<CloudinaryUploadResult> uploadVideoAsset({
    required File file,
    required String folder,
    String? publicId,
  }) {
    return _upload(
      resourceType: 'video',
      file: file,
      folder: folder,
      publicId: publicId,
    );
  }

  Future<String> uploadRaw({
    File? file,
    Uint8List? bytes,
    String? fileName,
    required String folder,
    String? publicId,
  }) async {
    return (await uploadRawAsset(
      file: file,
      bytes: bytes,
      fileName: fileName,
      folder: folder,
      publicId: publicId,
    ))
        .secureUrl;
  }

  Future<CloudinaryUploadResult> uploadRawAsset({
    File? file,
    Uint8List? bytes,
    String? fileName,
    required String folder,
    String? publicId,
  }) {
    return _upload(
      resourceType: 'auto',
      file: file,
      bytes: bytes,
      fileName: fileName,
      folder: folder,
      publicId: publicId,
    );
  }

  Future<CloudinaryUploadResult> _upload({
    required String resourceType,
    File? file,
    Uint8List? bytes,
    String? fileName,
    required String folder,
    String? publicId,
  }) async {
    if (!isConfigured) {
      throw Exception(
        'Cloudinary no esta configurado. Define CLOUDINARY_CLOUD_NAME y CLOUDINARY_UPLOAD_PRESET.',
      );
    }
    if (file == null && bytes == null) {
      throw Exception('No encontramos el archivo para subir.');
    }

    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = folder;

    if (publicId != null && publicId.trim().isNotEmpty) {
      request.fields['public_id'] = publicId.trim();
    }

    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
    } else {
      final resolvedName = fileName?.trim().isNotEmpty == true
          ? fileName!.trim()
          : 'upload${path.extension(fileName ?? '')}';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes!,
          filename: resolvedName,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String details = '';
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final error = body['error'];
          if (error is Map<String, dynamic>) {
            details = error['message'] as String? ?? '';
          }
        }
      } catch (_) {}
      throw Exception(
        details.isEmpty
            ? 'No pudimos subir el archivo a Cloudinary (${response.statusCode}).'
            : 'No pudimos subir el archivo a Cloudinary (${response.statusCode}): $details',
      );
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('La respuesta de Cloudinary no fue valida.');
    }
    final secureUrl = body['secure_url'] as String? ?? '';
    if (secureUrl.isEmpty) {
      throw Exception('Cloudinary no devolvio una URL valida.');
    }
    final resolvedPublicId = body['public_id'] as String? ?? publicId ?? '';
    return CloudinaryUploadResult(
      secureUrl: secureUrl,
      publicId: resolvedPublicId,
      resourceType: body['resource_type'] as String? ?? resourceType,
      folder: folder,
    );
  }
}
