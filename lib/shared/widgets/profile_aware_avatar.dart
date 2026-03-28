import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/data/profile_repository.dart';
import 'user_avatar.dart';

class ProfileAwareAvatar extends ConsumerWidget {
  const ProfileAwareAvatar({
    super.key,
    required this.userId,
    required this.fallbackPhotoUrl,
    required this.name,
    this.radius = 24,
  });

  final String userId;
  final String fallbackPhotoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) {
      return UserAvatar(
        photoUrl: fallbackPhotoUrl,
        name: name,
        radius: radius,
      );
    }

    final liveUser = ref.watch(userProfileProvider(userId)).valueOrNull;
    return UserAvatar(
      photoUrl: (liveUser?.photoUrl.isNotEmpty == true)
          ? liveUser!.photoUrl
          : fallbackPhotoUrl,
      name: (liveUser?.name.isNotEmpty == true) ? liveUser!.name : name,
      radius: radius,
    );
  }
}
