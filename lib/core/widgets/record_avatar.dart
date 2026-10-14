import 'dart:io';

import 'package:flutter/material.dart';

/// Circular avatar that shows the stored profile photo when available, and
/// falls back to the person's initials otherwise.
class RecordAvatar extends StatelessWidget {
  const RecordAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.radius = 24,
  });

  final String name;
  final String? photoPath;
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
    final path = photoPath;
    ImageProvider? image;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        image = FileImage(file);
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: image,
      child: image == null
          ? Text(
              _initials,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: radius * 0.72,
              ),
            )
          : null,
    );
  }
}
