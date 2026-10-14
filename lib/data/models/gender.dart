/// Supported gender options. Stored as the stable [storageValue] string so
/// renaming the enum label never corrupts persisted data.
enum Gender {
  male('male', 'Male'),
  female('female', 'Female'),
  other('other', 'Other');

  const Gender(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static Gender fromStorage(String? value) {
    final normalised = (value ?? '').trim().toLowerCase();
    for (final gender in Gender.values) {
      if (gender.storageValue == normalised) return gender;
    }
    return Gender.other;
  }

  static Gender? tryParse(String? value) {
    if (value == null) return null;
    final normalised = value.trim().toLowerCase();
    for (final gender in Gender.values) {
      if (gender.storageValue == normalised) return gender;
    }
    return null;
  }
}
