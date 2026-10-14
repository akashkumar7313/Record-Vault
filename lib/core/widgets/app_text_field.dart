import 'package:flutter/material.dart';

/// Consistent, accessible text input used across every form.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.hint,
    this.helperText,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.textCapitalization = TextCapitalization.sentences,
    this.autofillHints,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? hint;
  final String? helperText;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffix,
        alignLabelWithHint: maxLines > 1,
        counterText: maxLines > 1 ? '' : null,
      ),
    );
  }
}
