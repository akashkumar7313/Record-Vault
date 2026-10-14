import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';

/// Copies user-selected images into the app's private documents directory so
/// the app never depends on transient picker/temporary file locations.
class PhotoStorageService {
  PhotoStorageService({
    ImagePicker? picker,
    Future<Directory> Function()? documentsDir,
    http.Client? httpClient,
  }) : _picker = picker ?? ImagePicker(),
       _documentsDir = documentsDir ?? getApplicationDocumentsDirectory,
       _httpClient = httpClient ?? http.Client();

  final ImagePicker _picker;
  final Future<Directory> Function() _documentsDir;
  final http.Client _httpClient;

  /// Opens the gallery and returns the picked file, or null if cancelled.
  Future<XFile?> pickImage() async {
    try {
      return await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
    } catch (e, s) {
      throw AppException(
        AppErrorType.storage,
        'Could not access the photo library.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Persists [source] under a stable per-record filename and returns the path.
  Future<String> persist(XFile source, String aadhaarNumber) async {
    try {
      final length = await source.length();
      if (length > AppConstants.maxPhotoSizeBytes) {
        throw const AppException(
          AppErrorType.storage,
          'The selected photo is too large. Please choose a smaller image.',
        );
      }

      final docs = await _documentsDir();
      final photosDir = Directory(
        p.join(docs.path, AppConstants.photoDirectory),
      );
      if (!photosDir.existsSync()) {
        await photosDir.create(recursive: true);
      }

      var extension = p.extension(source.path);
      if (extension.isEmpty) extension = '.jpg';
      final destination = File(
        p.join(photosDir.path, '$aadhaarNumber$extension'),
      );
      await destination.writeAsBytes(await source.readAsBytes(), flush: true);
      return destination.path;
    } on AppException {
      rethrow;
    } catch (e, s) {
      throw AppException(
        AppErrorType.storage,
        'Could not save the selected photo.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Best-effort removal of a previously stored photo.
  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Deletion is best-effort; a leftover file is harmless.
    }
  }

  /// Reads a stored photo as a base64 string for upload, or null when there is
  /// no readable file at [path].
  Future<String?> readAsBase64(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return base64Encode(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// Downloads a remote (Google Drive) photo to private storage and returns the
  /// local path, or null when the image is unavailable or not actually an image.
  Future<String?> download(String url, String aadhaarNumber) async {
    if (url.isEmpty) return null;
    try {
      final response = await _httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final contentType = response.headers['content-type'] ?? '';
      // A private/unshared Drive link returns HTML, which we must not save.
      if (!contentType.startsWith('image/')) return null;

      final docs = await _documentsDir();
      final photosDir = Directory(
        p.join(docs.path, AppConstants.photoDirectory),
      );
      if (!photosDir.existsSync()) {
        await photosDir.create(recursive: true);
      }
      final destination = File(p.join(photosDir.path, '$aadhaarNumber.jpg'));
      await destination.writeAsBytes(response.bodyBytes, flush: true);
      return destination.path;
    } catch (_) {
      return null;
    }
  }
}
