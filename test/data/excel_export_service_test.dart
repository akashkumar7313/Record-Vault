import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/services/excel_export_service.dart';

PersonalRecord sample() => PersonalRecord(
  aadhaarNumber: '123456789012',
  fullName: 'Asha Verma',
  fatherName: 'Ramesh Verma',
  motherName: 'Sunita Verma',
  mobileNumber: '9876543210',
  email: 'asha@example.com',
  address: '12 Main Street',
  dateOfBirth: DateTime.utc(1990, 5, 20),
  gender: Gender.female,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2024, 1, 2),
);

void main() {
  const service = ExcelExportService();

  test('builds a workbook with headers and one data row', () {
    final bytes = service.buildBytes([sample()]);
    expect(bytes, isNotEmpty);

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[ExcelExportService.sheetName];
    expect(sheet, isNotNull);

    final rows = sheet!.rows;
    expect(rows.first.first!.value.toString(), contains('Aadhaar Number'));
    expect(rows.length, 2);

    final firstDataRow = rows[1];
    final name = firstDataRow[1]!.value as TextCellValue;
    expect(name.value.text, 'Asha Verma');
    final gender = firstDataRow[8]!.value as TextCellValue;
    expect(gender.value.text, 'Female');
  });

  test('empty input still produces a valid header-only workbook', () {
    final bytes = service.buildBytes([]);
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[ExcelExportService.sheetName]!;
    expect(sheet.rows.length, 1);
    expect(
      sheet.rows.first.first!.value.toString(),
      contains('Aadhaar Number'),
    );
  });

  test('header count matches the exported column list', () {
    final bytes = service.buildBytes([sample()]);
    final excel = Excel.decodeBytes(bytes);
    final header = excel.tables[ExcelExportService.sheetName]!.rows.first;
    expect(header.length, ExcelExportService.headers.length);
  });
}
