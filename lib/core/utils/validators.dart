/// Pure, dependency-free validation helpers used by the record form and tests.
class Validators {
  Validators._();

  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+'
    r'(?:\.[a-zA-Z0-9-]+)+$',
  );

  static final RegExp _mobileRegExp = RegExp(r'^[0-9]{10}$');

  static final RegExp _aadhaarRegExp = RegExp(r'^[0-9]{12}$');

  /// Returns an error string, or `null` when [value] is valid.
  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  static String? fullName(String? value) {
    final base = required(value, field: 'Full name');
    if (base != null) return base;
    if (value!.trim().length < 2) {
      return 'Enter a valid name';
    }
    return null;
  }

  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Email is required';
    }
    if (!_emailRegExp.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Optional email: empty is allowed, otherwise it must be well formed.
  static String? optionalEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return email(trimmed);
  }

  static String? mobile(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Mobile number is required';
    }
    final normalised = normaliseMobile(trimmed);
    if (!_mobileRegExp.hasMatch(normalised)) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  /// Validates the 12-digit Aadhaar number used as the unique record identity.
  static String? aadhaar(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Aadhaar number is required';
    }
    final normalised = normaliseAadhaar(trimmed);
    if (!_aadhaarRegExp.hasMatch(normalised)) {
      return 'Enter a valid 12-digit Aadhaar number';
    }
    return null;
  }

  static String? optionalMobile(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return mobile(trimmed);
  }

  static String? dateOfBirth(DateTime? value, {DateTime? now}) {
    if (value == null) {
      return 'Date of birth is required';
    }
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final dob = DateTime(value.year, value.month, value.day);
    if (dob.isAfter(today)) {
      return 'Date of birth cannot be in the future';
    }
    if (today.year - dob.year > 130) {
      return 'Enter a realistic date of birth';
    }
    return null;
  }

  static String? address(String? value) {
    final base = required(value, field: 'Address');
    if (base != null) return base;
    if (value!.trim().length < 3) {
      return 'Enter a complete address';
    }
    return null;
  }

  /// Normalises a mobile number for storage/search.
  ///
  /// Keeps digits only and drops a leading Indian country code (`91`) or trunk
  /// `0` so the result is the 10-digit national number.
  static String normaliseMobile(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 10 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length > 10 && digits.startsWith('0')) {
      digits = digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Normalises an Aadhaar number by removing spaces and dashes.
  static String normaliseAadhaar(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '');
}
