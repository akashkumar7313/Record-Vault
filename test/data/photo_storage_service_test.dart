import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:record_vault/data/services/photo_storage_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('record_vault_photos');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  PhotoStorageService serviceWith(MockClient client) =>
      PhotoStorageService(documentsDir: () async => temp, httpClient: client);

  group('PhotoStorageService.download', () {
    test('saves an image under the Aadhaar filename', () async {
      final bytes = [1, 2, 3, 4];
      final service = serviceWith(
        MockClient(
          (_) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/jpeg'},
          ),
        ),
      );

      final path = await service.download(
        'https://drive.example/x',
        '123456789012',
      );

      expect(path, isNotNull);
      expect(path, endsWith('123456789012.jpg'));
      expect(File(path!).readAsBytesSync(), bytes);
    });

    test('rejects a non-image response (private/unshared link)', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response(
            '<html>Sign in</html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );

      expect(
        await service.download('https://drive.example/x', '123456789012'),
        isNull,
      );
    });

    test('returns null when the request fails', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('nope', 404)),
      );

      expect(
        await service.download('https://drive.example/x', '123456789012'),
        isNull,
      );
    });
  });
}
