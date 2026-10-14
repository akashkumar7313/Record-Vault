import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Date/time formatting helpers. All persisted timestamps are UTC ISO-8601.
class Formatters {
  Formatters._();

  static final DateFormat _date = DateFormat(AppConstants.dateFormat);
  static final DateFormat _dateTime = DateFormat(AppConstants.dateTimeFormat);

  static String date(DateTime value) => _date.format(value.toLocal());

  static String dateTime(DateTime value) => _dateTime.format(value.toLocal());

  static String? dateOrNull(DateTime? value) =>
      value == null ? null : date(value);

  static String? dateTimeOrNull(DateTime? value) =>
      value == null ? null : dateTime(value);

  /// "12 Oct 1990 (35 years)" style age label.
  static String age(DateTime dob, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var years = reference.year - dob.year;
    final hasHadBirthday =
        (reference.month > dob.month) ||
        (reference.month == dob.month && reference.day >= dob.day);
    if (!hasHadBirthday) years--;
    return '$years ${years == 1 ? 'year' : 'years'}';
  }

  static String fileStamp(DateTime value) {
    final d = DateFormat('yyyyMMdd_HHmmss').format(value.toLocal());
    return d;
  }
}
