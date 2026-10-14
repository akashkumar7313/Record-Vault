import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:record_vault/data/database/app_database.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';
import 'package:record_vault/data/repositories/record_repository.dart';
import 'package:record_vault/data/services/google_sheets_service.dart';
import 'package:record_vault/data/services/sync_service.dart';

import '../helpers/test_database.dart';

final _endpoint = Uri.parse('https://example.com/exec');

PersonalRecord sample({
  String id = 'id-1',
  String name = 'Asha Verma',
  DateTime? updatedAt,
}) {
  final stamp = updatedAt ?? DateTime.utc(2024, 1, 1);
  return PersonalRecord(
    id: id,
    fullName: name,
    mobileNumber: '9876543210',
    email: 'asha@example.com',
    address: '12 Main Street',
    dateOfBirth: DateTime.utc(1990, 5, 20),
    gender: Gender.female,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

MockClient router({
  http.Response Function(http.Request request)? onGet,
  http.Response Function(http.Request request)? onPost,
}) {
  return MockClient((request) async {
    if (request.method == 'GET') {
      return onGet?.call(request) ?? http.Response('{"records":[]}', 200);
    }
    return onPost?.call(request) ?? http.Response('{"status":"success"}', 200);
  });
}

void main() {
  late RecordRepository repository;
  late AppDatabase database;

  setUp(() async {
    database = await createTestDatabase();
    repository = RecordRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  SyncService serviceUsing(MockClient client) => SyncService(
    repository,
    GoogleSheetsService(
      endpoint: _endpoint,
      client: client,
      readRetries: 1,
      writeRetries: 1,
    ),
  );

  test('confirmed push marks the record synced', () async {
    await repository.create(sample());
    final service = serviceUsing(router(onPost: null, onGet: null));

    final report = await service.syncAll();

    expect(report.serverReachable, isTrue);
    expect(report.pushed, 1);
    final record = (await repository.getById('id-1'))!;
    expect(record.syncStatus, SyncStatus.synced);
    expect(report.conflicts, 0);
  });

  test('offline push keeps local data and marks it failed', () async {
    await repository.create(sample());
    final service = serviceUsing(
      MockClient((_) async => throw const SocketException('offline')),
    );

    final report = await service.syncAll();

    expect(report.serverReachable, isFalse);
    expect(report.failed, 1);
    final record = (await repository.getById('id-1'))!;
    expect(record.syncStatus, SyncStatus.failed);
    expect(await repository.count(), 1);
  });

  test('unconfirmed push does not lose or duplicate the record', () async {
    await repository.create(sample());
    final service = serviceUsing(
      router(onPost: (_) => http.Response('{}', 200)),
    );

    final report = await service.syncAll();

    expect(report.pushed, 0);
    expect(report.failed, 1);
    expect(await repository.count(), 1);
    final record = (await repository.getById('id-1'))!;
    expect(record.syncStatus, SyncStatus.failed);
  });

  test(
    'updates use the update action and never re-add (no duplicates)',
    () async {
      final created = await repository.create(sample());
      await repository.markSynced(created.id);

      // Local edit makes it dirty again.
      await repository.update(
        (await repository.getById(created.id))!
            .copyWith(fullName: 'Asha Verma'),
      );

      final methods = <String>[];
      final bodies = <String>[];
      final service = serviceUsing(
        MockClient((request) async {
          methods.add(request.method);
          bodies.add(request.body);
          if (request.method == 'GET') {
            return http.Response('{"records":[]}', 200);
          }
          return http.Response('{"error":"Unknown action: update"}', 200);
        }),
      );

      final report = await service.syncAll();

      expect(report.pushed, 0);
      expect(report.failed, 1);
      expect(await repository.count(), 1);
      expect(
        bodies.any((b) => b.contains('"action":"update"')),
        isTrue,
        reason: 'edited records must be pushed with the update action',
      );
      expect(
        bodies.any((b) => b.contains('"action":"add"')),
        isFalse,
        reason: 'must not re-add, which could create a duplicate',
      );
    },
  );

  test('pull applies newer remote changes to synced records', () async {
    final remote = sample(name: 'Asha V.', updatedAt: DateTime.utc(2024, 6, 1));
    await repository.upsertFromRemote(
      remote.copyWith(updatedAt: DateTime.utc(2024, 1, 1)),
    );

    final service = serviceUsing(
      router(
        onGet: (_) => http.Response(
          '{"records":[{"id":"id-1","fullName":"Asha V.",'
          '"updatedAt":"2024-06-01T00:00:00.000Z"}]}',
          200,
        ),
      ),
    );

    final report = await service.syncAll();

    expect(report.pulled, 1);
    final record = (await repository.getById('id-1'))!;
    expect(record.fullName, 'Asha V.');
    expect(record.updatedAt, DateTime.utc(2024, 6, 1));
  });

  test('conflicting changes are flagged, not overwritten', () async {
    // Local dirty copy updated 2024-05-01.
    await repository.create(
      sample(name: 'Local Version', updatedAt: DateTime.utc(2024, 5, 1)),
    );

    final service = serviceUsing(
      router(
        onPost: (_) => http.Response('{}', 200), // unconfirmed -> stays dirty
        onGet: (_) => http.Response(
          '{"records":[{"id":"id-1","fullName":"Server Version",'
          '"updatedAt":"2024-07-01T00:00:00.000Z"}]}',
          200,
        ),
      ),
    );

    final report = await service.syncAll();

    expect(report.conflicts, 1);
    final record = (await repository.getById('id-1'))!;
    expect(record.syncStatus, SyncStatus.conflict);
    expect(record.fullName, 'Local Version');

    // Conflicts are not auto-pushed.
    expect(await repository.getPending(), isEmpty);
  });

  test('failed delete keeps the tombstone until confirmed', () async {
    final created = await repository.create(sample());
    await repository.markSynced(created.id);
    await repository.markDeleted(created.id);

    final service = serviceUsing(
      router(
        onPost: (_) => http.Response('{"error":"Unknown action: delete"}', 200),
      ),
    );

    final report = await service.syncAll();

    expect(report.failed, 1);
    final stillThere = await repository.getById('id-1');
    expect(stillThere, isNotNull);
    expect(stillThere!.isDeleted, isTrue);
  });

  test('confirmed delete removes the tombstone locally', () async {
    final created = await repository.create(sample());
    await repository.markSynced(created.id);
    await repository.markDeleted(created.id);

    final service = serviceUsing(router(onPost: null, onGet: null));

    await service.syncAll();

    expect(await repository.getById('id-1'), isNull);
  });
}
