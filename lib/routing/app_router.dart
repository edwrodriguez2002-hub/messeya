import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/app_preferences_service.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/calls/presentation/calls_page.dart';
import '../features/chats/presentation/create_space_page.dart';
import '../features/chats/presentation/home_page.dart';
import '../features/chats/presentation/archived_chats_page.dart';
import '../features/chats/presentation/space_info_page.dart';
import '../features/linked_devices/presentation/desktop_link_page.dart';
import '../features/linked_devices/presentation/link_desktop_scan_page.dart';
import '../features/linked_devices/presentation/linked_devices_page.dart';
import '../features/messages/presentation/chat_page.dart';
import '../features/messages/presentation/compose_page.dart';
import '../features/messages/presentation/drafts_page.dart';
import '../features/profile/presentation/blocked_contacts_page.dart';
import '../features/profile/presentation/contact_info_page.dart';
import '../features/profile/presentation/edit_profile_page.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/presentation/legal_document_page.dart';
import '../features/settings/presentation/app_lock_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/statuses/presentation/statuses_page.dart';
import '../features/statuses/presentation/hidden_status_contacts_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateChangesProvider);
  final preferences = ref.watch(appPreferencesServiceProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(
      ref.watch(authRepositoryProvider).authStateChanges(),
    ),
    redirect: (context, state) {
      final user = auth.valueOrNull;
      final isLoggedIn = user != null;
      final isAnonymous = user?.isAnonymous ?? false;
      final isWindowsDesktop =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
      final isDeprecatedAuthRoute = state.matchedLocation == '/register' ||
          state.matchedLocation == '/login/phone';
      if (isDeprecatedAuthRoute) {
        return '/login';
      }
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/desktop-link';
      final isDesktopLinkRoute = state.matchedLocation == '/desktop-link';
      final hasDesktopLink = preferences.getDesktopLinkedDeviceId().isNotEmpty;

      if (isWindowsDesktop && (!isLoggedIn || isAnonymous)) {
        if (hasDesktopLink && isDesktopLinkRoute) {
          return '/home';
        }
        if (!hasDesktopLink && !isDesktopLinkRoute) {
          return '/desktop-link';
        }
        return null;
      }

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/desktop-link',
        builder: (context, state) => const DesktopLinkPage(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/compose',
        builder: (context, state) {
          final draftId = state.uri.queryParameters['draftId'];
          return ComposePage(draftId: draftId);
        },
      ),
      GoRoute(
        path: '/drafts',
        builder: (context, state) => const DraftsPage(),
      ),
      GoRoute(
        path: '/spaces/create',
        builder: (context, state) => const CreateSpacePage(),
      ),
      GoRoute(
        path: '/spaces/:chatId',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          return SpaceInfoPage(chatId: chatId);
        },
      ),
      GoRoute(
        path: '/archived-chats',
        builder: (context, state) => const ArchivedChatsPage(),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/statuses',
        builder: (context, state) => const StatusesPage(),
      ),
      GoRoute(
        path: '/statuses/hidden',
        builder: (context, state) => const HiddenStatusContactsPage(),
      ),
      GoRoute(
        path: '/calls',
        builder: (context, state) => const CallsPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/settings/linked-devices',
        builder: (context, state) => const LinkedDevicesPage(),
      ),
      GoRoute(
        path: '/settings/linked-devices/scan',
        builder: (context, state) => const LinkDesktopScanPage(),
      ),
      GoRoute(
        path: '/settings/app-lock',
        builder: (context, state) => const AppLockPage(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: '/blocked-contacts',
        builder: (context, state) => const BlockedContactsPage(),
      ),
      GoRoute(
        path: '/legal/:documentType',
        builder: (context, state) {
          final documentType =
              state.pathParameters['documentType'] ?? 'privacy';
          return LegalDocumentPage(documentType: documentType);
        },
      ),
      GoRoute(
        path: '/contact/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId'] ?? '';
          return ContactInfoPage(userId: userId);
        },
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          final otherUserId = state.uri.queryParameters['uid'] ?? '';
          final otherUserName = state.uri.queryParameters['name'] ?? 'Chat';
          final otherUsername = state.uri.queryParameters['username'] ?? '';
          final otherUserPhoto = state.uri.queryParameters['photo'] ?? '';

          return ChatPage(
            chatId: chatId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUsername: otherUsername,
            otherUserPhoto: otherUserPhoto,
          );
        },
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
