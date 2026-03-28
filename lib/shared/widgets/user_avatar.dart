import 'dart:io';

import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 24,
  });

  final String photoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      final isRemote =
          photoUrl.startsWith('http://') || photoUrl.startsWith('https://');
      return CircleAvatar(
        radius: radius,
        backgroundImage: isRemote
            ? NetworkImage(photoUrl)
            : FileImage(File(photoUrl)) as ImageProvider<Object>,
      );
    }

    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
