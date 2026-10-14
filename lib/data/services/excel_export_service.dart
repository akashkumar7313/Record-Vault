import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/utils/formatters.dart';
import '../models/personal_record.dart';

/// Builds an Excel-compatible `.xlsx` workbook from a list of records.
///
/// The service is intentionally pure with respect to the filesystem apart from
/// [writeToFile]; [buildBytes] can be unit-tested without touching disk.
class ExcelExportService {
  const ExcelExportService();

  static const String sheetName = 'Records';

  static const List<String> headers = <String>[
    'Record ID',
    'Full Name',
    "Father's Name",
    "Mother's Name",
    'Mobile Number',
    'Email',
    'Address',
    'Date of Birth',
    'Gender',
    'Profile Photo',
    'Created At',
    'Updated At',
    'Sync Status',
  ];

  /// Produces the `.xlsx` byte content. An empty [records] list yields a valid
  /// workbook containing only the header row.
  List<int> buildBytes(List<PersonalRecord> records) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, sheetName);
    final sheet = excel[sheetName];

    final headerStyle = CellStyle(bold: true);
    for (var col = 0; col < headers.length; col++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
        TextCellValue(headers[col]),
        cellStyle: headerStyle,
      );
    }

    for (final record in records) {
      sheet.appendRow(<CellValue?>[
        TextCellValue(record.id),
        TextCellValue(record.fullName),
        TextCellValue(record.fatherName),
        TextCellValue(record.motherName),
        TextCellValue(record.mobileNumber),
        TextCellValue(record.email),
        TextCellValue(record.address),
        TextCellValue(Formatters.date(record.dateOfBirth)),
        TextCellValue(record.gender.label),
        TextCellValue(record.photoPath ?? ''),
        TextCellValue(Formatters.dateTime(record.createdAt)),
        TextCellValue(Formatters.dateTime(record.updatedAt)),
        TextCellValue(record.syncStatus.storageValue),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw const AppException(
        AppErrorType.export,
        'Could not generate the Excel file.',
      );
    }
    return bytes;
  }

  /// Writes the workbook to [directory] and returns the created file.
  Future<File> writeToFile(
    String directory,
    List<PersonalRecord> records, {
    DateTime? timestamp,
  }) async {
    try {
      final bytes = buildBytes(records);
      final stamp = Formatters.fileStamp(timestamp ?? DateTime.now());
      final file = File(p.join(directory, 'recordvault_$stamp.xlsx'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on FileSystemException catch (e, s) {
      throw AppException(
        AppErrorType.export,
        'Could not save the export file. Please check storage permissions.',
        cause: e,
        stackTrace: s,
      );
    }
  }
}
