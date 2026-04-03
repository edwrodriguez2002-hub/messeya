import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/models/chat.dart';
import '../../../../shared/widgets/messeya_ui.dart';
import '../../../../shared/widgets/profile_aware_avatar.dart';
import '../../../profile/data/profile_repository.dart';

class ChatListTile extends ConsumerWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.onTap,
    this.accountBadgeText,
    this.onLongPress,
  });

  final Chat chat;
  final String currentUserId;
  final VoidCallback onTap;
  final String? accountBadgeText;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUserId = chat.otherMemberId(currentUserId);
    final isSpace = chat.type != 'direct';
    
    final otherUser = isSpace ? null : ref.watch(userProfileProvider(otherUserId)).valueOrNull;
    final isVerified = otherUser?.isVerified ?? false;

    final name = isSpace
        ? (chat.title.isEmpty ? 'Espacio' : chat.title)
        : chat.memberNames[otherUserId] ?? 'Nuevo chat';
    final username = isSpace ? '' : chat.memberUsernames[otherUserId] ?? '';
    final photo =
        isSpace ? chat.photoUrl : chat.memberPhotos[otherUserId] ?? '';
    final lastMessage =
        chat.lastMessage.isEmpty ? 'Aun no hay mensajes' : chat.lastMessage;
    final requestLabel = chat.type == 'direct' &&
            chat.directMessageRequestStatus == 'pending' &&
            chat.directMessageRequestRecipientId == currentUserId
        ? 'Solicitud pendiente'
        : '';
    final subtitle = requestLabel.isNotEmpty
        ? requestLabel
        : username.isEmpty
            ? lastMessage
            : '@$username - $lastMessage';
    final time = chat.lastMessageAt == null
        ? ''
        : DateFormat('hh:mm a').format(chat.lastMessageAt!);
    final unreadCount = chat.unreadCounts[currentUserId] ?? 0;
    final previewText = subtitle.replaceAll('\n', ' ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(28), // REDUCIDO DE 32
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), // REDUCIDO DE 20/20
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileAwareAvatar(
                  userId: isSpace ? '' : otherUserId,
                  fallbackPhotoUrl: photo,
                  name: name,
                  radius: 28, // REDUCIDO DE 31
                ),
                if (!isSpace)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14, // REDUCIDO DE 18
                      height: 14,
                      decoration: BoxDecoration(
                        color: unreadCount > 0
                            ? MesseyaUi.success
                            : const Color(0xFF4D7FFF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF111A33),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14), // REDUCIDO DE 18
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17, // REDUCIDO DE 20
                                ),
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                color: Colors.blueAccent,
                                size: 15, // REDUCIDO DE 18
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            color: MesseyaUi.textMuted,
                            fontSize: 13, // REDUCIDO DE 16
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4), // REDUCIDO DE 6
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          username.isEmpty
                              ? previewText
                              : '@$username · $lastMessage',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MesseyaUi.textMuted,
                            fontSize: 14, // REDUCIDO DE 16
                            fontWeight: FontWeight.w500,
                          ),
                          ),
                        ),
                      if (accountBadgeText != null &&
                          accountBadgeText!.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            accountBadgeText!,
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: unreadCount > 9 ? 24 : 20, // REDUCIDO
                          height: 20,
                          decoration: const BoxDecoration(
                            color: MesseyaUi.accent,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11, // REDUCIDO
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
