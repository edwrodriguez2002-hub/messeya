import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/profile_aware_avatar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../search/data/search_repository.dart';
import '../data/calls_repository.dart';

class CallsPage extends ConsumerWidget {
  const CallsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(callLogsProvider);
    final currentUser = ref.watch(currentUserProvider);
    final effectiveUserId = ref.watch(effectiveMessagingUserIdProvider);
    final isDesktopLinked =
        currentUser?.isAnonymous == true && effectiveUserId.isNotEmpty;
    final desktopSession = ref.watch(desktopClientSessionProvider);

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: const MesseyaTopBar(
                  title: 'Llamadas',
                  actions: [
                    MesseyaRoundIconButton(icon: Icons.search_rounded),
                    MesseyaRoundIconButton(icon: Icons.more_vert_rounded),
                  ],
                ),
              ),
              if (isDesktopLinked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: MesseyaPanel(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 22,
                    child: Text(
                      desktopSession.valueOrNull?.ownerName.isNotEmpty == true
                          ? 'Las llamadas que inicies aqui se enviaran al Android principal de ${desktopSession.valueOrNull!.ownerName}.'
                          : 'Las llamadas de Windows se envian al Android principal vinculado.',
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MesseyaSectionLabel('Historial'),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AsyncValueWidget(
                    value: logs,
                    data: (items) {
                      if (items.isEmpty) {
                        return const Center(
                          child: Text('Aun no hay llamadas registradas.'),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 150),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final log = items[index];
                          final isIncoming = log.direction == 'incoming';
                          final isMissed = log.status == 'missed';
                          final accent = isIncoming && !isMissed
                              ? MesseyaUi.success
                              : MesseyaUi.danger;
                          final statusLabel =
                              isIncoming && !isMissed ? 'Entrante' : 'Perdida';

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
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
                                      userId: log.contactId,
                                      fallbackPhotoUrl: log.contactPhoto,
                                      name: log.contactName,
                                      radius: 31,
                                    ),
                                    Positioned(
                                      right: 1,
                                      bottom: 1,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: accent,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.contactName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '@${log.contactUsername}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: MesseyaUi.textMuted,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            isIncoming
                                                ? Icons.call_received_rounded
                                                : Icons.call_made_rounded,
                                            color: accent,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            statusLabel,
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _formatCallDate(log.startedAt),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: MesseyaUi.textMuted,
                                    fontSize: 17,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 118),
                  child: SizedBox(
                    height: 70,
                    child: MesseyaPillButton(
                      onTap: () => _openContactPicker(
                        context,
                        ref,
                        isDesktopLinked,
                        effectiveUserId,
                      ),
                      filled: true,
                      icon: Icons.call_rounded,
                      label: 'Nueva llamada',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCallDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return DateFormat('hh:mm a').format(date);
    if (diff == 1) return 'Ayer\n${DateFormat('hh:mm a').format(date)}';
    return '${DateFormat('d \'de\' MMM').format(date)}\n${DateFormat('hh:mm a').format(date)}';
  }

  Future<void> _openContactPicker(
    BuildContext context,
    WidgetRef ref,
    bool isDesktopLinked,
    String effectiveUserId,
  ) async {
    final currentUid = effectiveUserId;
    if (currentUid.isEmpty) return;

    final users = await ref.read(searchRepositoryProvider).searchUsers(
          '',
          excludeUid: currentUid,
        );

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        if (users.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Todavia no hay contactos disponibles para llamar.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: UserAvatar(photoUrl: user.photoUrl, name: user.name),
                title: Text(user.name),
                subtitle: Text('@${user.username}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        if (isDesktopLinked) {
                          await ref
                              .read(callsRepositoryProvider)
                              .enqueueLinkedDesktopCallRequest(
                                ownerUid: effectiveUserId,
                                contact: user,
                                type: 'audio',
                              );
                        } else {
                          await ref.read(callsRepositoryProvider).startCall(
                                contact: user,
                                type: 'audio',
                              );
                        }
                      },
                      icon: const Icon(Icons.call_rounded),
                    ),
                    IconButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        if (isDesktopLinked) {
                          await ref
                              .read(callsRepositoryProvider)
                              .enqueueLinkedDesktopCallRequest(
                                ownerUid: effectiveUserId,
                                contact: user,
                                type: 'video',
                              );
                        } else {
                          await ref.read(callsRepositoryProvider).startCall(
                                contact: user,
                                type: 'video',
                              );
                        }
                      },
                      icon: const Icon(Icons.videocam_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
