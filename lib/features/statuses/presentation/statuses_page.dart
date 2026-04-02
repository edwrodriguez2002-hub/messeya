import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/models/status_item.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/profile_aware_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/statuses_repository.dart';
import 'status_view_page.dart';

class StatusesPage extends ConsumerStatefulWidget {
  const StatusesPage({super.key});

  @override
  ConsumerState<StatusesPage> createState() => _StatusesPageState();
}

class _StatusesPageState extends ConsumerState<StatusesPage> {
  final _controller = TextEditingController();
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _publishStatus({
    File? imageFile,
    File? videoFile,
  }) async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty && imageFile == null && videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega texto, imagen o video para publicar.'),
        ),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      await ref.read(statusesRepositoryProvider).createStatus(
            text: trimmed,
            imageFile: imageFile,
            videoFile: videoFile,
          );
      _controller.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estado publicado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _openComposer() async {
    final picker = ImagePicker();
    File? imageFile;
    File? videoFile;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nuevo estado',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Comparte algo con tus contactos',
                      hintStyle: TextStyle(color: Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () async {
                          final file = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 85,
                          );
                          if (file == null) return;
                          setModalState(() {
                            imageFile = File(file.path);
                            videoFile = null;
                          });
                        },
                        icon: Icon(
                          Icons.image_outlined,
                          color: imageFile != null ? Colors.blue : Colors.white70,
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          final file = await picker.pickVideo(
                            source: ImageSource.gallery,
                          );
                          if (file == null) return;
                          setModalState(() {
                            videoFile = File(file.path);
                            imageFile = null;
                          });
                        },
                        icon: Icon(
                          Icons.videocam_outlined,
                          color: videoFile != null ? Colors.blue : Colors.white70,
                        ),
                      ),
                      const Spacer(),
                      if (imageFile != null || videoFile != null)
                        const Text(
                          'Archivo listo',
                          style: TextStyle(color: Colors.blue, fontSize: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _publishing
                          ? null
                          : () => _publishStatus(
                                imageFile: imageFile,
                                videoFile: videoFile,
                              ),
                      child: _publishing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Publicar estado'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusesAsync = ref.watch(statusesProvider);
    final currentUserId = ref.watch(effectiveMessagingUserIdProvider);
    final isDesktopLinked = ref.watch(currentUserProvider)?.isAnonymous == true;

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: MesseyaTopBar(
                  title: 'Estados',
                  actions: [
                    MesseyaRoundIconButton(
                      icon: Icons.more_vert_rounded,
                      onTap: () => context.push('/statuses/hidden'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ListView(
                    children: [
                      if (!isDesktopLinked) _OwnStatusCard(onTap: _openComposer),
                      const SizedBox(height: 24),
                      const MesseyaSectionLabel('Estados recientes'),
                      const SizedBox(height: 14),
                      AsyncValueWidget(
                        value: statusesAsync,
                        data: (items) {
                          if (items.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Text(
                                  'Todavía no hay estados nuevos.',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ),
                            );
                          }

                          // AGRUPAR POR USUARIO
                          final Map<String, List<StatusItem>> grouped = {};
                          for (var item in items) {
                            grouped.putIfAbsent(item.userId, () => []).add(item);
                          }

                          // Separar vistos de no vistos
                          final List<String> recentUserIds = [];
                          final List<String> viewedUserIds = [];

                          for (var userId in grouped.keys) {
                            final userStatuses = grouped[userId]!;
                            final hasUnviewed = userStatuses.any((s) => !s.viewedBy.contains(currentUserId));
                            if (hasUnviewed) {
                              recentUserIds.add(userId);
                            } else {
                              viewedUserIds.add(userId);
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // RECIENTES
                              ...recentUserIds.map((uid) => _buildUserStatusTile(
                                context, uid, grouped[uid]!, false
                              )),
                              
                              if (viewedUserIds.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                const MesseyaSectionLabel('Vistos'),
                                const SizedBox(height: 14),
                                ...viewedUserIds.map((uid) => _buildUserStatusTile(
                                  context, uid, grouped[uid]!, true
                                )),
                              ],
                              const SizedBox(height: 100),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserStatusTile(BuildContext context, String userId, List<StatusItem> userStatuses, bool isViewed) {
    final lastStatus = userStatuses.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _StatusTile(
        status: lastStatus,
        count: userStatuses.length,
        isViewed: isViewed,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StatusViewPage(
                statuses: userStatuses.reversed.toList(),
                userName: lastStatus.userName,
              ),
            ),
          );
        },
        trailingText: _relativeStatusTime(lastStatus.createdAt),
      ),
    );
  }

  String _relativeStatusTime(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} d';
  }
}

class _OwnStatusCard extends ConsumerWidget {
  const _OwnStatusCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider);
    return appUser.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return MesseyaPanel(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            onTap: onTap,
            child: Row(
              children: [
                Stack(
                  children: [
                    ProfileAwareAvatar(
                      userId: user.uid,
                      fallbackPhotoUrl: user.photoUrl,
                      name: user.name,
                      radius: 28,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mi estado',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Toca para añadir una actualización',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.count,
    required this.isViewed,
    required this.onTap,
    required this.trailingText,
  });

  final StatusItem status;
  final int count;
  final bool isViewed;
  final VoidCallback onTap;
  final String trailingText;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isViewed ? Colors.white24 : Colors.blue,
            width: 2,
          ),
        ),
        child: ProfileAwareAvatar(
          userId: status.userId,
          fallbackPhotoUrl: status.userPhoto,
          name: status.userName,
          radius: 26,
        ),
      ),
      title: Text(
        status.userName,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
      ),
      subtitle: Text(
        trailingText,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}
