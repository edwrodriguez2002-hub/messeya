import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/models/chat.dart';
import '../../../../shared/widgets/messeya_ui.dart';
import '../../../../shared/widgets/profile_aware_avatar.dart';

class ChatListTile extends ConsumerWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.onTap,
    this.onLongPress,
  });

  final Chat chat;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherUserId = chat.otherMemberId(currentUserId);
    final isSpace = chat.type != 'direct';
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
      borderRadius: BorderRadius.circular(32),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
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
                  radius: 31,
                ),
                if (!isSpace)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: unreadCount > 0
                            ? MesseyaUi.success
                            : const Color(0xFF4D7FFF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF111A33),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            color: MesseyaUi.textMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 12),
                        Container(
                          width: unreadCount > 9 ? 30 : 26,
                          height: 26,
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
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (chat.pinnedBy.contains(currentUserId)) ...[
                    const SizedBox(height: 6),
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 15,
                      color: MesseyaUi.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
