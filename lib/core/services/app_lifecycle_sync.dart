import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/data/profile_repository.dart';

class AppLifecycleSync extends ConsumerStatefulWidget {
  const AppLifecycleSync({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<AppLifecycleSync> createState() => _AppLifecycleSyncState();
}

class _AppLifecycleSyncState extends ConsumerState<AppLifecycleSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOnlineStatus(true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isOnline = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => false,
      AppLifecycleState.hidden => false,
      AppLifecycleState.paused => false,
      AppLifecycleState.detached => false,
    };
    _syncOnlineStatus(isOnline);
  }

  void _syncOnlineStatus(bool isOnline) {
    Future<void>(() async {
      try {
        await ref.read(profileRepositoryProvider).setOnlineStatus(
              isOnline: isOnline,
            );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
