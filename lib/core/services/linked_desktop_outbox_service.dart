import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/calls/data/calls_repository.dart';
import '../../features/messages/data/messages_repository.dart';

final linkedDesktopOutboxServiceProvider =
    Provider<LinkedDesktopOutboxService>((ref) {
  return LinkedDesktopOutboxService(
    ref.watch(authRepositoryProvider),
    ref.watch(callsRepositoryProvider),
    ref.watch(messagesRepositoryProvider),
  );
});

class LinkedDesktopOutboxService {
  LinkedDesktopOutboxService(
    this._authRepository,
    this._callsRepository,
    this._messagesRepository,
  );

  final AuthRepository _authRepository;
  final CallsRepository _callsRepository;
  final MessagesRepository _messagesRepository;
  StreamSubscription<Object?>? _authSubscription;
  StreamSubscription<List<dynamic>>? _outboxSubscription;

  Future<void> initialize() async {
    _authSubscription?.cancel();
    _authSubscription = _authRepository.authStateChanges().listen((user) {
      _outboxSubscription?.cancel();
      if (user == null || user.isAnonymous) {
        return;
      }
      _outboxSubscription = _messagesRepository
          .watchPendingDesktopOutbox(user.uid)
          .listen((documents) async {
        for (final document in documents) {
          final type = document.data()['type'] as String? ?? 'text';
          if (type == 'call_request') {
            await _callsRepository.processDesktopCallRequest(document);
          } else {
            await _messagesRepository.processDesktopOutboxItem(document);
          }
        }
      });
    });
  }
}
