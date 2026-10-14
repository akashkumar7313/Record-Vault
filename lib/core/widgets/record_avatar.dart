import 'dart:io';

import 'package:flutter/material.dart';

/// Circular avatar that shows the stored profile photo when available, and
/// falls back to the person's initials whenever no photo exists or the remote
/// image cannot be decoded.
class RecordAvatar extends StatelessWidget {
  const RecordAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.photoUrl,
    this.radius = 24,
  });

  final String name;
  final String? photoPath;

  /// Remote (Google Drive) photo URL used when no local copy exists.
  final String? photoUrl;
  final double radius;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content;
    final path = photoPath;
    final localFile = (path != null && path.isNotEmpty) ? File(path) : null;

    if (localFile != null && localFile.existsSync()) {
      content = Image(
        image: FileImage(localFile),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _initialsView(scheme),
      );
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      content = Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        // Drives files are private by default, so a failed load is expected and
        // must degrade to initials instead of throwing.
        errorBuilder: (_, _, _) => _initialsView(scheme),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _initialsView(scheme),
      );
    } else {
      content = _initialsView(scheme);
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: content,
    );
  }

  Widget _initialsView(ColorScheme scheme) {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}
