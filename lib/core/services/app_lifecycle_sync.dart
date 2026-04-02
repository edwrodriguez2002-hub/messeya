import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/hybrid_sync_service.dart';
import '../../core/services/stream_chat_service.dart';
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
      _syncRealtimeState(true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncRealtimeState(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isOnline = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => true,
      AppLifecycleState.hidden => false,
      AppLifecycleState.paused => false,
      AppLifecycleState.detached => false,
    };
    _syncRealtimeState(isOnline);
  }

  void _syncRealtimeState(bool isOnline) {
    Future<void>(() async {
      try {
        await ref.read(streamChatServiceProvider).setAppActive(isOnline);
        await ref.read(profileRepositoryProvider).setOnlineStatus(
              isOnline: isOnline,
            );
        if (isOnline) {
          await ref.read(hybridSyncServiceProvider).flushPendingToCloud();
          await ref.read(hybridSyncServiceProvider).flushPendingToMesh();
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
