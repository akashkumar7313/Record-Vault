import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/providers/data_providers.dart';

/// How the exported file was delivered to the user.
enum ExportMethod { shared, saved }

class ExportOutcome {
  const ExportOutcome({
    required this.path,
    required this.fileName,
    required this.count,
    required this.method,
  });

  final String path;
  final String fileName;
  final int count;
  final ExportMethod method;
}

/// Controls Excel export: building the workbook, then either sharing it via
/// the OS share sheet or letting the user pick a save location.
final exportControllerProvider =
    NotifierProvider<ExportController, AsyncValue<ExportOutcome?>>(
      ExportController.new,
    );

class ExportController extends Notifier<AsyncValue<ExportOutcome?>> {
  static const String _mimeXlsx =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  @override
  AsyncValue<ExportOutcome?> build() => const AsyncData(null);

  Future<ExportOutcome?> export(
    List<PersonalRecord> records, {
    bool share = true,
    Rect? shareOrigin,
  }) async {
    state = const AsyncLoading();
    try {
      final bytes = ref.read(excelExportServiceProvider).buildBytes(records);
      final fileName =
          'recordvault_${Formatters.fileStamp(DateTime.now())}.xlsx';

      final outcome = share
          ? await _share(fileName, bytes, records.length, shareOrigin)
          : await _save(fileName, bytes, records.length);

      state = AsyncData(outcome);
      return outcome;
    } catch (e, s) {
      final exception = AppException.from(e, s);
      state = AsyncError(exception, s);
      return null;
    }
  }

  Future<ExportOutcome> _share(
    String fileName,
    List<int> bytes,
    int count,
    Rect? origin,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: _mimeXlsx)],
        subject: 'RecordVault export',
        text: 'RecordVault export ($count records)',
        sharePositionOrigin: origin,
      ),
    );

    return ExportOutcome(
      path: file.path,
      fileName: fileName,
      count: count,
      method: ExportMethod.shared,
    );
  }

  Future<ExportOutcome> _save(
    String fileName,
    List<int> bytes,
    int count,
  ) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      mimeType: _mimeXlsx,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      dialogTitle: 'Save RecordVault export',
    );

    if (uri == null) {
      throw const AppException(AppErrorType.export, 'Export cancelled.');
    }

    return ExportOutcome(
      path: uri.toString(),
      fileName: fileName,
      count: count,
      method: ExportMethod.saved,
    );
  }
}
